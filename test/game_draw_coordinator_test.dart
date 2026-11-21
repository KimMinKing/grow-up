import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

import 'package:growup/state/game_draw_coordinator.dart';
import 'package:growup/state/game_expedition_remote.dart';

class _RetryRemote implements GameExpeditionRemote {
  final requests = <String>[];
  bool failOnce = true;

  @override
  Future<GameDrawResult> draw(String requestId) async {
    requests.add(requestId);
    if (failOnce) {
      failOnce = false;
      throw StateError('response lost');
    }
    return const GameDrawResult(
      creatureId: 'creature-1',
      speciesId: 'wave_otter',
      remainingShards: 0,
      guaranteed: true,
      alreadyDrawn: true,
    );
  }

  @override
  Future<ServerGameState> load() => throw UnimplementedError();
  @override
  Future<void> claimStarter(String speciesId) => throw UnimplementedError();
  @override
  Future<void> start() => throw UnimplementedError();
  @override
  Future<int> claim(String expeditionId) => throw UnimplementedError();
  @override
  Future<void> setSquadSlot(String creatureId, int slot) =>
      throw UnimplementedError();
  @override
  Future<int> claimTaskBattlePasses() => throw UnimplementedError();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
  });

  test(
    'lost draw response retries the same request after app restart',
    () async {
      final remote = _RetryRemote();
      final prefs = SharedPreferencesAsync();
      final first = GameDrawCoordinator(
        prefs: prefs,
        remote: remote,
        newRequestId: () => 'request-1',
      );
      await expectLater(first.draw('user-1'), throwsStateError);
      expect(await prefs.getString('game_draw_pending_v1_user-1'), 'request-1');
      expect(await first.hasPendingRequest('user-1'), isTrue);
      expect(await first.hasPendingRequest('user-2'), isFalse);

      final restarted = GameDrawCoordinator(
        prefs: SharedPreferencesAsync(),
        remote: remote,
        newRequestId: () => 'should-not-be-used',
      );
      final result = await restarted.draw('user-1');
      expect(result.speciesId, 'wave_otter');
      expect(remote.requests, ['request-1', 'request-1']);
      expect(await prefs.getString('game_draw_pending_v1_user-1'), isNull);
      expect(await restarted.hasPendingRequest('user-1'), isFalse);
    },
  );
}
