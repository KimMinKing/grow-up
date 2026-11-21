import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:growup/server_expedition_panel.dart';
import 'package:growup/game_page.dart';
import 'package:growup/models/game_creature.dart';
import 'package:growup/state/game_store.dart';
import 'package:growup/state/game_expedition_remote.dart';
import 'package:growup/state/game_battle_remote.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const _userId = '00000000-0000-0000-0000-000000000041';
const _requestId = '40000000-0000-0000-0000-000000000001';

class _RiverBattleRemote implements GameBattleRemote {
  _RiverBattleRemote(this.onBattle);

  final void Function() onBattle;

  @override
  Future<ServerBattleResult> battle(String stageId, String requestId) async {
    expectSync(stageId, 'river_shallow_crossing');
    onBattle();
    return ServerBattleResult(
      requestId: requestId,
      stageId: stageId,
      won: true,
      stars: 2,
      turns: 7,
      experienceAwarded: 3,
      firstClearShards: 0,
      alreadyResolved: false,
      companionSpeciesId: 'pebble_newt',
    );
  }
}

String _sessionJson() {
  final expiresAt =
      DateTime.now().add(const Duration(hours: 1)).millisecondsSinceEpoch ~/
      1000;
  final payload = base64Url
      .encode(utf8.encode(jsonEncode({'exp': expiresAt, 'sub': _userId})))
      .replaceAll('=', '');
  return jsonEncode({
    'access_token': 'header.$payload.signature',
    'expires_in': 3600,
    'expires_at': expiresAt,
    'refresh_token': 'test-refresh-token',
    'token_type': 'bearer',
    'user': {
      'id': _userId,
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

  testWidgets('river account battle follows server first-clear order', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(300, 700);
    tester.view.devicePixelRatio = 1;
    tester.binding.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(
      tester.binding.platformDispatcher.clearTextScaleFactorTestValue,
    );
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    var riverCrossed = false;
    var newtAssigned = false;
    var battleCalls = 0;
    final client = SupabaseClient(
      'http://localhost:54321',
      'test-publishable-key',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
      httpClient: MockClient((request) async {
        final path = request.url.pathSegments.last;
        Object? body;
        if (path == 'game_creature_instances') {
          body = [
            {
              'id': 'starter',
              'species_id': 'pine_fox',
              'source': 'starter',
              'level': 4,
              'battle_experience': 0,
            },
            if (riverCrossed)
              {
                'id': 'newt',
                'species_id': 'pebble_newt',
                'source': 'battle',
                'level': 3,
                'battle_experience': 0,
              },
          ];
        } else if (path == 'game_squad_slots') {
          body = [
            {'slot': 1, 'creature_id': 'starter'},
            if (newtAssigned) {'slot': 2, 'creature_id': 'newt'},
          ];
        } else if (path == 'set_game_squad_slot') {
          final params = jsonDecode(request.body) as Map<String, dynamic>;
          expect(params['p_creature_id'], 'newt');
          expect(params['p_slot'], 2);
          newtAssigned = true;
          body = null;
        } else if (path == 'game_wallets') {
          body = {'draw_shards': 4, 'battle_passes': riverCrossed ? 1 : 2};
        } else if (path == 'game_expeditions' ||
            path == 'game_battle_attempts') {
          body = <Object>[];
        } else if (path == 'get_game_status') {
          body = {
            'serverNow': DateTime.now().toUtc().toIso8601String(),
            'todayStarts': 0,
          };
        } else if (path == 'get_game_stage_reward_status') {
          body = {
            'draw_shards': 4,
            'first_clears': [
              for (final (stage, badge, shards) in [
                ('forest_moss_gate', 'first_footprint', 1),
                ('forest_firefly_path', 'forest_lantern', 1),
                ('forest_dawn_lookout', 'forest_dawn', 2),
                ('river_mist_entry', 'river_entry', 0),
                if (riverCrossed)
                  ('river_shallow_crossing', 'river_crossing', 0),
              ])
                {
                  'stage_id': stage,
                  'badge_id': badge,
                  'awarded_shards': shards,
                },
            ],
          };
        } else {
          throw StateError('Unexpected request: ${request.url}');
        }
        return http.Response(
          jsonEncode(body),
          200,
          headers: {'content-type': 'application/json'},
          request: request,
        );
      }),
    );
    await client.auth.recoverSession(_sessionJson());
    final gameStore = GameStore(SharedPreferencesAsync());
    await gameStore.chooseStarter('pine_fox');
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: ServerExpeditionPanel(
              client: client,
              gameStore: gameStore,
              initialStageId: 'river_shallow_crossing',
              stageRewardsEnabled: true,
              battleRemote: _RiverBattleRemote(() {
                riverCrossed = true;
                battleCalls++;
              }),
            ),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('지도에서 선택 · 물안개 여울'), findsOneWidget);
    expect(find.text('안개 강가 첫 승리 · 1/3'), findsOneWidget);
    expect(find.text('✓ 강가의 첫 발 · 첫 승리 기록'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(
            find.ancestor(
              of: find.text('선택한 장소 정식 전투 시작'),
              matching: find.byType(FilledButton),
            ),
          )
          .onPressed,
      isNotNull,
    );
    for (final (place, enabled) in [
      ('강가 입구', true),
      ('물안개 여울', true),
      ('달빛 나루', false),
    ]) {
      final button = tester.widget<OutlinedButton>(
        find.ancestor(
          of: find.text(place),
          matching: find.byType(OutlinedButton),
        ),
      );
      expect(button.onPressed != null, enabled);
      expect(
        button.style?.foregroundColor?.resolve(
          enabled ? <WidgetState>{} : <WidgetState>{WidgetState.disabled},
        ),
        enabled ? Colors.white : const Color(0xFF9CAAB6),
      );
    }
    tester
        .widget<FilledButton>(
          find.ancestor(
            of: find.text('선택한 장소 정식 전투 시작'),
            matching: find.byType(FilledButton),
          ),
        )
        .onPressed!();
    for (var i = 0; i < 30 && battleCalls == 0; i++) {
      await tester.pump(const Duration(milliseconds: 500));
    }
    expect(battleCalls, 1);
    expect(find.text('자갈도롱뇽 합류!'), findsOneWidget);
    expect(find.text('안개 강가 첫 승리 · 2/3'), findsOneWidget);
    expect(find.text('✓ 여울의 길 · 첫 승리 기록'), findsOneWidget);
    expect(find.text('서버 보유 신수 2/20'), findsOneWidget);
    await tester.ensureVisible(find.text('새 동료 편성하기'));
    await tester.tap(find.text('새 동료 편성하기'));
    await tester.pumpAndSettle();
    expect(find.text('정식 파견 스쿼드 동료 선택'), findsOneWidget);
    expect(find.text('자갈도롱뇽'), findsOneWidget);
    await tester.tap(find.text('자갈도롱뇽'));
    await tester.pumpAndSettle();
    expect(newtAssigned, isTrue);
    expect(find.textContaining('2 자갈도롱뇽 Lv3'), findsOneWidget);
    expect(find.text('새 동료 편성하기'), findsNothing);
    expect(
      tester
          .widget<OutlinedButton>(
            find.ancestor(
              of: find.text('달빛 나루'),
              matching: find.byType(OutlinedButton),
            ),
          )
          .onPressed,
      isNotNull,
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: ServerExpeditionPanel(
              client: client,
              gameStore: gameStore,
              initialStageId: 'river_moon_ferry',
              stageRewardsEnabled: true,
            ),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('안개 강가 첫 승리 · 2/3'), findsOneWidget);
    expect(find.text('✓ 여울의 길 · 첫 승리 기록'), findsOneWidget);
    expect(find.text('서버 보유 신수 2/20'), findsOneWidget);
    expect(find.textContaining('2 자갈도롱뇽 Lv3'), findsOneWidget);
    expect(find.text('지도에서 선택 · 달빛 나루'), findsOneWidget);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: GamePage(
            gameStore: gameStore,
            gameRemoteClient: client,
            gameStageRewardsEnabled: true,
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.tap(
      find.descendant(
        of: find.byType(BottomNavigationBar),
        matching: find.text('신수'),
      ),
    );
    await tester.pump(const Duration(milliseconds: 500));
    await tester.scrollUntilVisible(find.textContaining('도감 ·'), 300);
    await tester.scrollUntilVisible(find.text('자갈도롱뇽'), 300);
    await tester.tap(find.text('자갈도롱뇽').last);
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('계정 보유 외형 · 각성 (Lv 3)'), findsOneWidget);
    expect(find.text('1번 · 각성 · Lv 3 · 편성 2번'), findsOneWidget);
    expect(find.textContaining('체력 76 · 공격 18'), findsOneWidget);
    final detailSprite = find.descendant(
      of: find.byType(BottomSheet).last,
      matching: find.byType(GameStaticSprite),
    );
    expect(
      tester.widget<GameStaticSprite>(detailSprite).evolutionStage,
      CreatureEvolutionStage.awakened,
    );
  });

  test(
    'account stage records keep best stars and fastest win separately',
    () async {
      var requests = 0;
      final client = SupabaseClient(
        'http://localhost:54321',
        'test-publishable-key',
        authOptions: const AuthClientOptions(autoRefreshToken: false),
        httpClient: MockClient((request) async {
          expect(request.url.pathSegments.last, 'game_battle_attempts');
          requests++;
          final stage = request.url.queryParameters['stage_id'];
          final select = request.url.queryParameters['select'];
          final body = stage == 'eq.forest_moss_gate'
              ? select == 'turns'
                    ? [
                        {'turns': 3},
                      ]
                    : [
                        {'stars': 3, 'turns': 8},
                      ]
              : <Object>[];
          return http.Response(
            jsonEncode(body),
            200,
            headers: {'content-type': 'application/json'},
            request: request,
          );
        }),
      );
      final records = await loadServerStageRecords(client);
      expect(requests, 7);
      expect(records.keys, ['forest_moss_gate']);
      expect(records['forest_moss_gate']!.stars, 3);
      expect(records['forest_moss_gate']!.bestTurns, 3);
    },
  );

  testWidgets('signed-out expedition opens account from the game', (
    tester,
  ) async {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    var accountOpened = false;
    final client = SupabaseClient(
      'http://localhost:54321',
      'test-publishable-key',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
      httpClient: MockClient((request) async {
        throw StateError('Unexpected request: ${request.url}');
      }),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ServerExpeditionPanel(
            client: client,
            gameStore: GameStore(SharedPreferencesAsync()),
            onOpenAccount: () => accountOpened = true,
          ),
        ),
      ),
    );
    await tester.tap(find.text('계정에서 로그인'));
    expect(accountOpened, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('starter registration leads to expedition return and shards', (
    tester,
  ) async {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    var registered = false;
    var active = false;
    var starts = 0;
    var shards = 0;
    var drawn = false;
    String? drawRequestId;
    final client = SupabaseClient(
      'http://localhost:54321',
      'test-publishable-key',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
      httpClient: MockClient((request) async {
        final path = request.url.pathSegments.last;
        Object? body;
        switch (path) {
          case 'game_creature_instances':
            body = registered
                ? [
                    {
                      'id': 'server-starter',
                      'species_id': 'pine_fox',
                      'source': 'starter',
                      'level': 1,
                    },
                    if (drawn)
                      {
                        'id': 'server-draw-1',
                        'species_id': 'wave_otter',
                        'source': 'draw',
                        'level': 1,
                      },
                  ]
                : <Object>[];
          case 'game_squad_slots':
            body = registered
                ? [
                    {'slot': 1, 'creature_id': 'server-starter'},
                  ]
                : <Object>[];
          case 'game_wallets':
            body = registered ? {'draw_shards': shards} : null;
          case 'game_expeditions':
            body = active
                ? {
                    'id': 'expedition-1',
                    'ready_at': DateTime.now()
                        .toUtc()
                        .subtract(const Duration(seconds: 1))
                        .toIso8601String(),
                  }
                : null;
          case 'get_game_status':
            body = {
              'serverNow': DateTime.now().toUtc().toIso8601String(),
              'todayStarts': starts,
            };
          case 'game_draw_requests':
            body = drawn
                ? [
                    {'request_id': drawRequestId},
                  ]
                : <Object>[];
          case 'claim_game_starter':
            expect(jsonDecode(request.body)['p_species_id'], 'pine_fox');
            registered = true;
            body = {'creatureId': 'server-starter'};
          case 'start_game_expedition':
            expect(jsonDecode(request.body)['p_region_id'], 'pine_forest');
            active = true;
            starts++;
            body = {'expeditionId': 'expedition-1'};
          case 'claim_game_expedition':
            expect(jsonDecode(request.body)['p_expedition_id'], 'expedition-1');
            active = false;
            shards++;
            body = {'awardedShards': 1};
          case 'draw_game_creature':
            drawRequestId = jsonDecode(request.body)['p_request_id'] as String;
            expect(shards, 3);
            drawn = true;
            shards -= 3;
            body = {
              'creatureId': 'server-draw-1',
              'speciesId': 'wave_otter',
              'remainingShards': shards,
              'guaranteed': true,
              'alreadyDrawn': false,
            };
          case 'logout':
            body = <String, dynamic>{};
          default:
            throw StateError('Unexpected request: ${request.url}');
        }
        return http.Response(
          jsonEncode(body),
          200,
          headers: {'content-type': 'application/json'},
          request: request,
        );
      }),
    );
    await client.auth.recoverSession(_sessionJson());
    final gameStore = GameStore(SharedPreferencesAsync());
    await gameStore.chooseStarter('pine_fox');
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: ServerExpeditionPanel(
              client: client,
              gameStore: gameStore,
              drawEnabled: true,
            ),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.tap(find.text('솔여우 등록'));
    await tester.pump();
    await tester.tap(find.text('등록'));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 500));
    expect(registered, isTrue);
    for (var expedition = 1; expedition <= 3; expedition++) {
      await tester.tap(find.text('정식 파견 출발'));
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump(const Duration(milliseconds: 500));
      expect(active, isTrue);
      await tester.tap(find.text('귀환 보상 받기'));
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump(const Duration(milliseconds: 500));
      expect(active, isFalse);
      expect(shards, expedition);
      expect(find.text('뽑기 조각 $expedition개'), findsOneWidget);
      expect(find.text('오늘 파견 $expedition/3회'), findsOneWidget);
    }
    await tester.tap(find.text('무료 뽑기 · 조각 3개'));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 500));
    expect(drawn, isTrue);
    expect(shards, 0);
    expect(find.textContaining('새 동료: 파도수달'), findsOneWidget);
    expect(find.text('서버 보유 신수 2/20'), findsOneWidget);
    expect(tester.takeException(), isNull);
    tester.view.physicalSize = const Size(320, 700);
    tester.view.devicePixelRatio = 1;
    tester.binding.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(
      tester.binding.platformDispatcher.clearTextScaleFactorTestValue,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: GamePage(
            gameStore: gameStore,
            gameRemoteClient: client,
            gameDrawEnabled: true,
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.tap(
      find.descendant(
        of: find.byType(BottomNavigationBar),
        matching: find.text('신수'),
      ),
    );
    await tester.pump(const Duration(milliseconds: 500));
    await tester.scrollUntilVisible(
      find.textContaining('도감 ·'),
      400,
      scrollable: find
          .descendant(
            of: find.byType(GamePage),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('도감 · 2/4'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.scrollUntilVisible(find.text('파도수달'), 200);
    await tester.drag(find.byType(ListView).first, const Offset(0, -180));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.tap(find.text('파도수달').last);
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.textContaining('계정 보유 1마리'), findsOneWidget);
    await client.auth.signOut(scope: SignOutScope.local);
    await tester.pump();
    expect(find.text('미발견 신수'), findsOneWidget);
    expect(find.text('파도수달'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'saved draw request remains actionable after server spent shards',
    (tester) async {
      tester.view.physicalSize = const Size(320, 700);
      tester.view.devicePixelRatio = 1;
      tester.binding.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(
        tester.binding.platformDispatcher.clearTextScaleFactorTestValue,
      );
      SharedPreferencesAsyncPlatform.instance =
          InMemorySharedPreferencesAsync.empty();
      final prefs = SharedPreferencesAsync();
      await prefs.setString('game_draw_pending_v1_$_userId', _requestId);
      final requests = <String>[];
      var statusLoads = 0;
      var battlePasses = 0;
      var passClaims = 0;
      final client = SupabaseClient(
        'http://localhost:54321',
        'test-publishable-key',
        authOptions: const AuthClientOptions(autoRefreshToken: false),
        httpClient: MockClient((request) async {
          final path = request.url.pathSegments.last;
          Object? body;
          if (path == 'draw_game_creature') {
            requests.add(jsonDecode(request.body)['p_request_id'] as String);
            body = {
              'creatureId': '50000000-0000-0000-0000-000000000001',
              'speciesId': 'wave_otter',
              'remainingShards': 0,
              'guaranteed': true,
              'alreadyDrawn': true,
            };
          } else if (path == 'get_game_status') {
            statusLoads++;
            body = {
              'serverNow': DateTime.now()
                  .toUtc()
                  .add(const Duration(minutes: 30))
                  .toIso8601String(),
              'todayStarts': 1,
            };
          } else if (path == 'game_creature_instances') {
            body = [
              {
                'id': 'starter',
                'species_id': 'pine_fox',
                'source': 'starter',
                'level': 1,
              },
              for (var index = 1; index < 20; index++)
                {
                  'id': 'creature-$index',
                  'species_id': 'wave_otter',
                  'source': 'draw',
                  'level': 1,
                },
            ];
          } else if (path == 'game_squad_slots') {
            body = [
              {'slot': 1, 'creature_id': 'starter'},
            ];
          } else if (path == 'game_wallets') {
            body = {'draw_shards': 0, 'battle_passes': battlePasses};
          } else if (path == 'claim_game_task_battle_passes') {
            passClaims++;
            battlePasses += 2;
            body = {'addedPasses': 2, 'battlePasses': battlePasses};
          } else if (path == 'game_expeditions') {
            body = request.url.queryParameters.containsKey('claimed_at')
                ? {
                    'id': 'expedition-1',
                    'ready_at': DateTime.now()
                        .toUtc()
                        .add(const Duration(minutes: 10))
                        .toIso8601String(),
                  }
                : <Object>[];
          } else if (path == 'game_draw_requests') {
            body = <Object>[];
          } else if (path == 'game_battle_attempts') {
            if (request.url.queryParameters['select'] !=
                'stage_id,status,experience_awarded') {
              final stage = request.url.queryParameters['stage_id'];
              body = stage == 'eq.forest_moss_gate'
                  ? [
                      {'stars': 3, 'turns': 4},
                    ]
                  : stage == 'eq.forest_firefly_path'
                  ? [
                      {'stars': 2, 'turns': 7},
                    ]
                  : <Object>[];
            } else {
              body = [
                {
                  'stage_id': 'forest_moss_gate',
                  'status': 'resolved',
                  'experience_awarded': 1,
                },
                {
                  'stage_id': 'forest_firefly_path',
                  'status': 'resolved',
                  'experience_awarded': 2,
                },
                {
                  'stage_id': 'forest_firefly_path',
                  'status': 'resolved',
                  'experience_awarded': 0,
                },
              ];
            }
          } else if (path == 'get_game_stage_reward_status') {
            body = {
              'draw_shards': 0,
              'first_clears': [
                {
                  'stage_id': 'forest_moss_gate',
                  'badge_id': 'first_footprint',
                  'awarded_shards': 1,
                },
              ],
            };
          } else if (path == 'logout') {
            body = <String, dynamic>{};
          } else {
            throw StateError('Unexpected request: ${request.url}');
          }
          return http.Response(
            jsonEncode(body),
            200,
            headers: {'content-type': 'application/json'},
            request: request,
          );
        }),
      );
      await client.auth.recoverSession(_sessionJson());
      expect(client.auth.currentUser?.id, _userId);
      final gameStore = GameStore(prefs);
      await gameStore.chooseStarter('pine_fox');
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: ServerExpeditionPanel(
                client: client,
                gameStore: gameStore,
                initialStageId: 'forest_firefly_path',
                drawEnabled: true,
                stageRewardsEnabled: true,
              ),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('귀환 보상 받기'), findsOneWidget);
      expect(find.text('서버 첫 승리 보상 · 1/3'), findsOneWidget);
      expect(
        find.text('✓ 첫 발자국 · 조각 1개 지급 · 최고 별 3/3 · 최저 4턴'),
        findsOneWidget,
      );
      expect(find.text('○ 숲의 등불 · 서버 미지급 · 최고 별 2/3 · 최저 7턴'), findsOneWidget);
      expect(find.text('정식 숲길·강가 전투'), findsOneWidget);
      expect(find.text('정식 전투권 0/30 · 오늘 도전 3/15'), findsOneWidget);
      expect(find.text('지도에서 선택 · 반딧불이 오솔길'), findsOneWidget);
      expect(
        tester
            .widget<FilledButton>(
              find.ancestor(
                of: find.text('선택한 장소 정식 전투 시작'),
                matching: find.byType(FilledButton),
              ),
            )
            .onPressed,
        isNull,
      );
      expect(find.text('이끼 문턱 1/5'), findsOneWidget);
      expect(find.text('반딧불이 오솔길 1/5'), findsOneWidget);
      expect(find.text('1. 이끼 문턱'), findsOneWidget);
      expect(find.text('2. 반딧불이 오솔길'), findsOneWidget);
      final stageButton = tester.widget<OutlinedButton>(
        find.ancestor(
          of: find.text('1. 이끼 문턱'),
          matching: find.byType(OutlinedButton),
        ),
      );
      expect(stageButton.onPressed, isNull);
      await tester.ensureVisible(find.text('동기화한 할 일에서 전투권 받기'));
      await tester.tap(find.text('동기화한 할 일에서 전투권 받기'));
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump(const Duration(milliseconds: 500));
      expect(passClaims, 1);
      expect(find.text('정식 전투권 2/30 · 오늘 도전 3/15'), findsOneWidget);
      expect(find.text('전투권 2장을 받았어요.'), findsOneWidget);
      expect(
        tester
            .widget<FilledButton>(
              find.ancestor(
                of: find.text('선택한 장소 정식 전투 시작'),
                matching: find.byType(FilledButton),
              ),
            )
            .onPressed,
        isNotNull,
      );
      expect(
        tester
            .widget<OutlinedButton>(
              find.ancestor(
                of: find.text('1. 이끼 문턱'),
                matching: find.byType(OutlinedButton),
              ),
            )
            .onPressed,
        isNotNull,
      );
      final retry = find.text('이전 뽑기 결과 확인');
      expect(retry, findsOneWidget);
      final button = tester.widget<FilledButton>(
        find.ancestor(of: retry, matching: find.byType(FilledButton)),
      );
      expect(button.onPressed, isNotNull);
      await tester.ensureVisible(retry);
      await tester.tap(retry);
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump(const Duration(milliseconds: 500));
      expect(requests, [_requestId]);
      expect(await prefs.getString('game_draw_pending_v1_$_userId'), isNull);
      expect(find.text('새 동료: 파도수달 · 미발견 보장'), findsOneWidget);
      final loadsBeforeManualRefresh = statusLoads;
      await tester.ensureVisible(find.byTooltip('서버 게임 새로고침'));
      await tester.tap(find.byTooltip('서버 게임 새로고침'));
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump(const Duration(milliseconds: 500));
      expect(statusLoads, greaterThan(loadsBeforeManualRefresh));
      final loadsBeforeResume = statusLoads;
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump(const Duration(milliseconds: 500));
      expect(statusLoads, greaterThan(loadsBeforeResume));
      expect(tester.takeException(), isNull);

      battlePasses = 29;
      await tester.tap(find.byTooltip('서버 게임 새로고침'));
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('정식 전투권 29/30 · 오늘 도전 3/15'), findsOneWidget);
      expect(
        find.text('전투권을 더 받으려면 잔액이 28장 이하여야 해요. 전투권을 사용한 뒤 다시 받으세요.'),
        findsOneWidget,
      );
      expect(
        tester
            .widget<OutlinedButton>(
              find.ancestor(
                of: find.text('동기화한 할 일에서 전투권 받기'),
                matching: find.byType(OutlinedButton),
              ),
            )
            .onPressed,
        isNull,
      );

      battlePasses = 30;
      await tester.tap(find.byTooltip('서버 게임 새로고침'));
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('정식 전투권 30/30 · 오늘 도전 3/15'), findsOneWidget);
      expect(
        find.text('전투권을 더 받으려면 잔액이 28장 이하여야 해요. 전투권을 사용한 뒤 다시 받으세요.'),
        findsOneWidget,
      );
      expect(
        tester
            .widget<OutlinedButton>(
              find.ancestor(
                of: find.text('동기화한 할 일에서 전투권 받기'),
                matching: find.byType(OutlinedButton),
              ),
            )
            .onPressed,
        isNull,
      );
      expect(passClaims, 1);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: GamePage(
              gameStore: gameStore,
              gameRemoteClient: client,
              gameDrawEnabled: true,
              gameStageRewardsEnabled: true,
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump(const Duration(milliseconds: 500));
      await tester.tap(
        find.descendant(
          of: find.byType(BottomNavigationBar),
          matching: find.text('모험'),
        ),
      );
      await tester.pump(const Duration(milliseconds: 500));
      await tester.scrollUntilVisible(find.text('숲길 지도 · 해금 0/3'), 400);
      expect(find.textContaining('계정 정식 첫 승리 1/3'), findsOneWidget);
      expect(find.text('계정 정식 첫 승리 ✓ · 조각 1개 지급'), findsOneWidget);
      final mossMarker = find.byKey(
        const ValueKey('forest-map-stage-forest_moss_gate'),
      );
      tester.widget<InkWell>(mossMarker).onTap!();
      await tester.pumpAndSettle();
      expect(find.text('계정 정식 전투 준비'), findsOneWidget);
      await tester.tap(find.text('계정 정식 전투 준비'));
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('지도에서 선택 · 이끼 문턱'), findsOneWidget);
      final focusedBattle = tester.widget<FilledButton>(
        find.ancestor(
          of: find.text('선택한 장소 정식 전투 시작'),
          matching: find.byType(FilledButton),
        ),
      );
      expect(focusedBattle.onPressed, isNotNull);
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: find.byType(BottomNavigationBar),
          matching: find.text('보상'),
        ),
      );
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump(const Duration(milliseconds: 500));
      await tester.scrollUntilVisible(find.text('정식 첫 승리 보상 1/3'), 300);
      expect(find.text('정식 첫 승리 보상 1/3'), findsOneWidget);
      expect(find.text('이끼 문턱 · 지급 완료'), findsOneWidget);
      expect(find.textContaining('반딧불이 오솔길 · 첫 승리 전'), findsOneWidget);
      await tester.tap(
        find.descendant(
          of: find.byType(BottomNavigationBar),
          matching: find.text('모험'),
        ),
      );
      await tester.pump(const Duration(milliseconds: 500));
      await client.auth.signOut(scope: SignOutScope.local);
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.textContaining('계정 정식 첫 승리 1/3'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}
