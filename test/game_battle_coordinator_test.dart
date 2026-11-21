import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:growup/state/game_battle_coordinator.dart';
import 'package:growup/state/game_battle_remote.dart';

class _RetryBattleRemote implements GameBattleRemote {
  final requests = <String>[];
  bool failOnce = true;

  @override
  Future<ServerBattleResult> battle(String stageId, String requestId) async {
    requests.add('$stageId|$requestId');
    if (failOnce) {
      failOnce = false;
      throw StateError('response lost');
    }
    return ServerBattleResult(
      requestId: requestId,
      stageId: stageId,
      won: true,
      stars: 2,
      turns: 4,
      experienceAwarded: 1,
      firstClearShards: 1,
      alreadyResolved: true,
    );
  }
}

class _ExpiredBattleRemote implements GameBattleRemote {
  @override
  Future<ServerBattleResult> battle(String stageId, String requestId) =>
      throw const FunctionsHttpException(
        status: 409,
        details: {'error': 'battle_attempt_expired'},
      );
}

class _RejectedBattleRemote implements GameBattleRemote {
  @override
  Future<ServerBattleResult> battle(String stageId, String requestId) =>
      throw const FunctionsHttpException(
        status: 409,
        details: {
          'error': 'battle_start_failed',
          'reason': 'previous stage required',
        },
      );
}

class _TransientStartErrorRemote implements GameBattleRemote {
  @override
  Future<ServerBattleResult> battle(String stageId, String requestId) =>
      throw const FunctionsHttpException(
        status: 503,
        details: {'error': 'battle_start_failed'},
      );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
  });

  test('lost battle response retries the same server attempt', () async {
    final remote = _RetryBattleRemote();
    final prefs = SharedPreferencesAsync();
    final first = GameBattleCoordinator(
      prefs: prefs,
      remote: remote,
      newRequestId: () => 'request-1',
    );
    await expectLater(
      first.battle('user-1', 'forest_moss_gate'),
      throwsStateError,
    );
    expect((await first.pending('user-1'))?.requestId, 'request-1');
    expect(await first.pending('user-2'), isNull);

    final restarted = GameBattleCoordinator(
      prefs: SharedPreferencesAsync(),
      remote: remote,
      newRequestId: () => 'should-not-be-used',
    );
    final result = await restarted.battle('user-1', 'forest_dawn_lookout');
    expect(result.stageId, 'forest_moss_gate');
    expect(result.firstClearShards, 1);
    expect(remote.requests, [
      'forest_moss_gate|request-1',
      'forest_moss_gate|request-1',
    ]);
    expect(await restarted.pending('user-1'), isNull);
  });

  test('rejects malformed server result without discarding retry ID', () async {
    final result = <String, dynamic>{
      'requestId': 'request-1',
      'stageId': 'forest_moss_gate',
      'won': true,
      'stars': 4,
      'turns': 2,
      'experienceAwarded': 1,
      'firstClearShards': 1,
      'alreadyResolved': false,
    };
    expect(() => ServerBattleResult.fromJson(result), throwsFormatException);
  });

  test(
    'river battle result accepts earned companion and rejects unknown species',
    () {
      final result = <String, dynamic>{
        'requestId': 'request-river',
        'stageId': 'river_shallow_crossing',
        'won': true,
        'stars': 2,
        'turns': 7,
        'experienceAwarded': 3,
        'firstClearShards': 0,
        'alreadyResolved': false,
        'companionSpeciesId': 'pebble_newt',
      };
      expect(
        ServerBattleResult.fromJson(result).companionSpeciesId,
        'pebble_newt',
      );
      result['alreadyResolved'] = true;
      expect(
        ServerBattleResult.fromJson(result).companionSpeciesId,
        'pebble_newt',
      );
      result['companionSpeciesId'] = 'unknown_species';
      expect(() => ServerBattleResult.fromJson(result), throwsFormatException);
    },
  );

  test('river result passes through the Supabase function client', () async {
    final client = SupabaseClient(
      'http://localhost:54321',
      'test-publishable-key',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
      httpClient: MockClient((request) async {
        expect(request.url.path, '/functions/v1/verify-forest-battle');
        expect(request.method, 'POST');
        final args = jsonDecode(request.body) as Map<String, dynamic>;
        expect(args['stageId'], 'river_shallow_crossing');
        expect(args['requestId'], 'river-request');
        return http.Response(
          jsonEncode({
            'requestId': 'river-request',
            'stageId': 'river_shallow_crossing',
            'won': true,
            'stars': 2,
            'turns': 7,
            'experienceAwarded': 3,
            'firstClearShards': 0,
            'alreadyResolved': false,
            'companionSpeciesId': 'pebble_newt',
          }),
          200,
          headers: {'content-type': 'application/json'},
          request: request,
        );
      }),
    );
    final result = await SupabaseGameBattleRemote(client)
        .battle('river_shallow_crossing', 'river-request');
    expect(result.companionSpeciesId, 'pebble_newt');
    expect(result.firstClearShards, 0);
    client.dispose();
  });

  test('expired server attempt clears the retry ID', () async {
    final coordinator = GameBattleCoordinator(
      prefs: SharedPreferencesAsync(),
      remote: _ExpiredBattleRemote(),
      newRequestId: () => 'request-2',
    );
    await expectLater(
      coordinator.battle('user-1', 'forest_moss_gate'),
      throwsA(isA<FunctionsHttpException>()),
    );
    expect(await coordinator.pending('user-1'), isNull);
  });

  test('rejected stage does not block choosing another stage', () async {
    final coordinator = GameBattleCoordinator(
      prefs: SharedPreferencesAsync(),
      remote: _RejectedBattleRemote(),
      newRequestId: () => 'request-3',
    );
    await expectLater(
      coordinator.battle('user-1', 'forest_firefly_path'),
      throwsA(isA<FunctionsHttpException>()),
    );
    expect(await coordinator.pending('user-1'), isNull);
  });

  test('transient start error keeps the request ID for recovery', () async {
    final coordinator = GameBattleCoordinator(
      prefs: SharedPreferencesAsync(),
      remote: _TransientStartErrorRemote(),
      newRequestId: () => 'request-4',
    );
    await expectLater(
      coordinator.battle('user-1', 'forest_moss_gate'),
      throwsA(isA<FunctionsHttpException>()),
    );
    expect((await coordinator.pending('user-1'))?.requestId, 'request-4');
  });
}
