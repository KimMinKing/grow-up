import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:growup/game_reward_ledger_page.dart';
import 'package:growup/state/game_reward_ledger.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

String _session() {
  final expiresAt =
      DateTime.now().add(const Duration(hours: 1)).millisecondsSinceEpoch ~/
      1000;
  final payload = base64Url
      .encode(
        utf8.encode(
          jsonEncode({
            'exp': expiresAt,
            'sub': '00000000-0000-0000-0000-000000000041',
          }),
        ),
      )
      .replaceAll('=', '');
  return jsonEncode({
    'access_token': 'header.$payload.signature',
    'expires_in': 3600,
    'expires_at': expiresAt,
    'refresh_token': 'test-refresh-token',
    'token_type': 'bearer',
    'user': {
      'id': '00000000-0000-0000-0000-000000000041',
      'aud': 'authenticated',
      'role': 'authenticated',
      'email': 'tester@example.invalid',
      'app_metadata': {
        'provider': 'email',
        'providers': ['email'],
      },
      'user_metadata': <String, dynamic>{},
      'created_at': '2026-01-01T00:00:00Z',
    },
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'server reward ledger combines payouts and spending in date order',
    () async {
      final requested = <String>[];
      final client = SupabaseClient(
        'http://localhost:54321',
        'test-publishable-key',
        authOptions: const AuthClientOptions(autoRefreshToken: false),
        httpClient: MockClient((request) async {
          final table = request.url.pathSegments.last;
          requested.add(table);
          final rows = switch (table) {
            'game_task_battle_grants' => [
              {
                'task_id': 'task-1',
                'completed_day': '2026-11-10',
                'passes': 2,
                'granted_at': '2026-11-10T01:00:00Z',
              },
            ],
            'game_battle_attempts' => [
              {
                'request_id': '40000000-0000-0000-0000-000000000001',
                'stage_id': 'forest_moss_gate',
                'status': 'resolved',
                'won': true,
                'stars': 3,
                'started_at': '2026-11-10T02:00:00Z',
              },
              {
                'request_id': '40000000-0000-0000-0000-000000000002',
                'stage_id': 'forest_moss_gate',
                'status': 'expired',
                'won': null,
                'stars': null,
                'started_at': '2026-11-10T00:30:00Z',
              },
            ],
            'game_stage_first_clears' => [
              {
                'stage_id': 'forest_moss_gate',
                'awarded_shards': 1,
                'awarded_at': '2026-11-10T02:05:00Z',
              },
            ],
            'game_expeditions' => [
              {
                'started_at': '2026-11-10T02:30:00Z',
                'claimed_at': '2026-11-10T03:00:00Z',
                'reward_shards': 1,
              },
            ],
            'game_draw_requests' => [
              {
                'request_id': '50000000-0000-0000-0000-000000000001',
                'guaranteed': false,
                'shards_spent': 3,
                'created_at': '2026-11-10T04:00:00Z',
              },
            ],
            _ => throw StateError('Unexpected table: $table'),
          };
          return http.Response(
            jsonEncode(rows),
            200,
            request: request,
            headers: {'content-type': 'application/json'},
          );
        }),
      );
      await client.auth.recoverSession(_session());

      final entries = await loadGameRewardLedger(
        client,
        taskTitles: {'task-1': '책 읽기'},
      );

      expect(entries.length, 6);
      expect(entries.first.title, '무료 신수 뽑기');
      expect(entries.first.shardChange, -3);
      expect(entries[1].title, '정식 파견 귀환 수령');
      expect(entries[2].shardChange, 1);
      expect(entries[3].battlePassChange, -1);
      expect(entries[3].detail, contains('요청 40000000'));
      expect(entries[4].detail, contains('책 읽기'));
      expect(entries.last.battlePassChange, isNull);
      expect(
        filterGameRewardLedger(entries, kind: GameLedgerKind.battle),
        hasLength(2),
      );
      expect(filterGameRewardLedger(entries, query: '  책 읽기  '), hasLength(1));
      expect(
        filterGameRewardLedger(entries, since: DateTime.utc(2026, 11, 10, 3)),
        hasLength(2),
      );
      expect(
        filterGameRewardLedger(
          entries,
          kind: GameLedgerKind.draw,
          query: '책 읽기',
        ),
        isEmpty,
      );
      expect(
        requested,
        containsAll([
          'game_task_battle_grants',
          'game_battle_attempts',
          'game_stage_first_clears',
          'game_expeditions',
          'game_draw_requests',
        ]),
      );
      client.dispose();
    },
  );

  testWidgets('account ledger fits a narrow screen with large text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(300, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var delayRequests = false;
    final client = SupabaseClient(
      'http://localhost:54321',
      'test-publishable-key',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
      httpClient: MockClient((request) async {
        if (delayRequests) {
          await Future<void>.delayed(const Duration(milliseconds: 50));
        }
        final rows = request.url.pathSegments.last == 'game_task_battle_grants'
            ? [
                {
                  'task_id': 'task-1',
                  'completed_day': '2026-11-10',
                  'passes': 2,
                  'granted_at': '2026-11-10T01:00:00Z',
                },
              ]
            : <Object>[];
        return http.Response(
          jsonEncode(rows),
          200,
          request: request,
          headers: {'content-type': 'application/json'},
        );
      }),
    );
    await client.auth.recoverSession(_session());
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(2)),
          child: GameRewardLedgerPage(
            client: client,
            taskTitles: const {'task-1': '책 읽기'},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byType(TextField));
    await tester.enterText(find.byType(TextField), '없는 할 일');
    await tester.pumpAndSettle();
    expect(find.textContaining('조건에 맞는 기록이 없어요'), findsOneWidget);
    delayRequests = true;
    await tester.tap(find.byTooltip('원장 새로고침'));
    await tester.pump();
    await tester.pumpAndSettle();
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      '없는 할 일',
    );
    expect(find.textContaining('조건에 맞는 기록이 없어요'), findsOneWidget);
    await tester.enterText(find.byType(TextField), '책 읽기');
    await tester.pumpAndSettle();
    await tester.drag(find.byType(ListView), const Offset(0, -300));
    await tester.pumpAndSettle();
    expect(find.text('할 일 전투권 지급'), findsOneWidget);
    expect(find.text('책 읽기 · 2026-11-10 완료'), findsOneWidget);
    expect(tester.takeException(), isNull);
    client.dispose();
  });
}
