import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

import 'package:growup/game_page.dart';
import 'package:growup/battle_page.dart';
import 'package:growup/models/adventure_stage.dart';
import 'package:growup/models/game_snapshot.dart';
import 'package:growup/models/reward_grant.dart';
import 'package:growup/state/game_store.dart';
import 'package:growup/state/game_expedition_remote.dart';
import 'package:growup/state/growth_store.dart';

Future<void> openGameTab(WidgetTester tester, String label) async {
  await tester.pump(const Duration(seconds: 5));
  await tester.pump(const Duration(milliseconds: 500));
  final tab = find.descendant(
    of: find.byType(BottomNavigationBar),
    matching: find.text(label),
  );
  await tester.tap(tab);
  await tester.pump(const Duration(milliseconds: 500));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
  });

  testWidgets('adventure map reveals stories after clearing places', (
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
    Widget journal(int count, int cleared) => MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: TrainingJournal(
            key: ValueKey('$count-$cleared'),
            completed: count,
            cleared: cleared,
            onExplore: (_) {},
          ),
        ),
      ),
    );
    await tester.pumpWidget(journal(0, 0));
    expect(find.text('숲길 지도 · 해금 0/3'), findsOneWidget);
    expect(find.text('진행 중 · 훈련 1회에 탐험 가능해요.'), findsOneWidget);
    expect(find.text(TrainingJournal.entries.first.story), findsNothing);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(journal(1, 0));
    expect(find.text('숲길 지도 · 해금 0/3'), findsOneWidget);
    expect(find.text('탐험하기'), findsOneWidget);
    expect(find.text(TrainingJournal.entries.first.story), findsNothing);

    await tester.pumpWidget(journal(1, 1));
    expect(find.text('숲길 지도 · 해금 1/3'), findsOneWidget);
    expect(find.text('첫 발자국'), findsOneWidget);
    expect(find.text(TrainingJournal.entries.first.story), findsOneWidget);
    expect(find.text('진행 중 · 훈련 3회에 탐험 가능해요.'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(journal(7, 3));
    expect(find.text('숲길 지도 · 해금 3/3'), findsOneWidget);
    expect(find.text('숲의 새벽'), findsOneWidget);
    expect(find.text('기기 전투 클리어 0/3'), findsOneWidget);
    expect(find.textContaining('기기 전투 칭호 ·'), findsNothing);
    expect(find.text('첫 숲길 완주'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('forest ending appears after three battle victories', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: TrainingJournal(
              completed: 7,
              cleared: 3,
              stageProgress: {
                for (final stage in firstForestStages)
                  stage.id: const StageProgress(clearCount: 1, stars: 1),
              },
            ),
          ),
        ),
      ),
    );
    expect(find.text('기기 전투 클리어 3/3'), findsOneWidget);
    for (final stage in firstForestStages) {
      expect(
        find.text('기기 전투 칭호 · ${stage.firstClearReward.badge}'),
        findsOneWidget,
      );
    }
    expect(find.text('첫 숲길 완주'), findsOneWidget);
    expect(find.textContaining('안개 강가의 강가 입구가 열렸어요'), findsOneWidget);
    expect(find.textContaining('첫 숲길 보스 전투 승리'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('map separates device victories from account first clears', (
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
    var openedServerBattle = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: TrainingJournal(
              completed: 1,
              cleared: 1,
              stageProgress: {
                firstForestStages.first.id: const StageProgress(
                  clearCount: 1,
                  stars: 2,
                ),
              },
              serverProgressLoaded: true,
              serverFirstClears: [
                ServerStageFirstClear(
                  stageId: firstForestStages[1].id,
                  badgeId: 'forest_lantern',
                  awardedShards: 1,
                ),
              ],
              onServerBattle: () => openedServerBattle = true,
            ),
          ),
        ),
      ),
    );
    expect(find.text('기기 전투 클리어 1/3'), findsOneWidget);
    expect(find.textContaining('계정 정식 첫 승리 1/3'), findsOneWidget);
    expect(find.text('계정 정식 첫 승리 ✓ · 조각 1개 지급'), findsOneWidget);
    expect(find.text('계정 정식 첫 승리 · 아직 없음'), findsNWidgets(2));
    expect(find.text('기기 별 2/3'), findsOneWidget);
    await tester.ensureVisible(find.text('정식 서버 전투 보기'));
    await tester.tap(find.text('정식 서버 전투 보기'));
    expect(openedServerBattle, isTrue);
    expect(tester.takeException(), isNull);
  });

  test(
    'adventure places require training and clear in order after reload',
    () async {
      final prefs = SharedPreferencesAsync();
      final game = GameStore(prefs);
      await game.chooseStarter('pine_fox');
      expect(await game.clearAdventureStage(0), isFalse);
      await game.creditCompletedTasks(['task-a']);
      await game.startTraining(now: DateTime.utc(2026, 11, 2));
      await game.finishTraining(now: DateTime.utc(2026, 11, 2, 0, 1));
      expect(await game.clearAdventureStage(1), isFalse);
      expect(await game.clearAdventureStage(0), isTrue);
      expect(await game.clearAdventureStage(0), isFalse);
      expect(game.adventureClears, 1);
      expect(game.stageProgress[firstForestStages.first.id]?.clearCount, 1);

      final restored = GameStore(prefs);
      await restored.load();
      expect(restored.adventureClears, 1);
      expect(restored.stageProgress[firstForestStages.first.id]?.clearCount, 1);
      expect(await restored.clearAdventureStage(1), isFalse);
    },
  );

  test('old local game keeps map stories unlocked by past returns', () async {
    final prefs = SharedPreferencesAsync();
    final game = GameStore(prefs);
    await game.chooseStarter('pine_fox');
    final old = game.exportSnapshot()!.toJson()
      ..remove('adventureClears')
      ..remove('stageProgress')
      ..['trainingCompletions'] = 3;
    await prefs.setString('game_collection_v1', jsonEncode(old));
    final restored = GameStore(prefs);
    await restored.load();
    expect(restored.trainingCompletions, 3);
    expect(restored.adventureClears, 2);
    expect(
      restored.stageProgress.keys,
      containsAll(firstForestStages.take(2).map((stage) => stage.id)),
    );
  });

  test('first battle spends one pass and saves stars with the clear', () async {
    final prefs = SharedPreferencesAsync();
    final game = GameStore(prefs);
    await game.chooseStarter('star_crow');
    expect(await game.runFirstBattle(), isNull);
    await game.creditCompletedTasks(['task-a']);
    await game.startTraining(now: DateTime.utc(2026, 11, 3));
    await game.finishTraining(now: DateTime.utc(2026, 11, 3, 0, 1));
    final result = await game.runFirstBattle();
    expect(result?.won, isTrue);
    expect(result?.firstBattleClear, isTrue);
    expect(result?.rewardSpeciesId, 'pine_fox');
    expect(
      game.owned.map((creature) => creature.speciesId),
      containsAll(['star_crow', 'pine_fox']),
    );
    expect(game.squad.whereType<String>(), hasLength(1));
    expect(game.trainingPasses, 0);
    expect(game.adventureClears, 1);
    expect(
      game.stageProgress[firstForestStages.first.id]?.stars,
      inInclusiveRange(1, 3),
    );
    expect(await game.runFirstBattle(), isNull);
    final restored = GameStore(prefs);
    await restored.load();
    expect(restored.trainingPasses, 0);
    expect(restored.adventureClears, 1);
    expect(restored.owned, hasLength(2));
    await restored.creditCompletedTasks(['task-b']);
    final repeat = await restored.runFirstBattle();
    expect(repeat?.won, isTrue);
    expect(repeat?.firstBattleClear, isFalse);
    expect(repeat?.rewardSpeciesId, isNull);
    expect(restored.owned, hasLength(2));
    expect(
      restored.stageProgress[firstForestStages.first.id]?.bestTurns,
      result?.turns,
    );
  });

  test(
    'battle milestone records awakening and keeps it after reload',
    () async {
      final seed = GameStore(SharedPreferencesAsync());
      await seed.chooseStarter('pine_fox');
      final data = seed.exportSnapshot()!.toJson();
      final starter = Map<String, dynamic>.from((data['owned'] as List).single);
      starter['level'] = 2;
      starter['battleExperience'] = 2;
      data['owned'] = [starter];
      data['trainingCompletions'] = 1;
      data['trainingPasses'] = 1;
      SharedPreferencesAsyncPlatform.instance =
          InMemorySharedPreferencesAsync.empty();
      final prefs = SharedPreferencesAsync();
      final game = GameStore(prefs);
      expect(await game.importIfEmpty(GameSnapshot.fromJson(data)), isTrue);
      final result = await game.runFirstBattle();
      expect(result?.won, isTrue);
      expect(result?.evolvedCreatureIds, ['starter-1']);
      expect(game.owned.first.level, 3);
      expect(game.owned.first.evolutionStage.label, '각성');
      final restored = GameStore(prefs);
      await restored.load();
      expect(restored.owned.first.evolutionStage.label, '각성');
    },
  );

  test('past first battle win receives the companion once on load', () async {
    final prefs = SharedPreferencesAsync();
    final game = GameStore(prefs);
    await game.chooseStarter('pine_fox');
    final old = game.exportSnapshot()!.toJson()
      ..['trainingCompletions'] = 1
      ..['adventureClears'] = 1
      ..['stageProgress'] = {
        firstForestStages.first.id: {
          'clearCount': 1,
          'stars': 3,
          'bestTurns': 5,
        },
      };
    await prefs.setString('game_collection_v1', jsonEncode(old));
    final restored = GameStore(prefs);
    await restored.load();
    expect(restored.owned, hasLength(2));
    expect(restored.owned.last.id, GameStore.firstForestCompanionId);
    expect(restored.owned.last.speciesId, 'wave_otter');
    expect(restored.owned.last.battleExperience, 0);
    expect(restored.discoveredSpeciesIds, contains('wave_otter'));
    final reloaded = GameStore(prefs);
    await reloaded.load();
    expect(reloaded.owned, hasLength(2));

    final backup = GameSnapshot.fromJson(Map<String, dynamic>.from(old));
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    final imported = GameStore(SharedPreferencesAsync());
    expect(await imported.importIfEmpty(backup), isTrue);
    expect(imported.owned, hasLength(2));
    expect(imported.discoveredSpeciesIds, contains('wave_otter'));
  });

  test('server starter lookup ignores backup collection order', () async {
    final game = GameStore(SharedPreferencesAsync());
    await game.chooseStarter('pine_fox');
    final data = game.exportSnapshot()!.toJson();
    final starter = (data['owned'] as List).single;
    data['owned'] = [
      {'id': 'companion-1', 'speciesId': 'wave_otter', 'level': 1},
      starter,
    ];
    data['discoveredSpeciesIds'] = ['pine_fox', 'wave_otter'];
    final backup = GameSnapshot.fromJson(data);
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    final imported = GameStore(SharedPreferencesAsync());
    expect(await imported.importIfEmpty(backup), isTrue);
    expect(imported.owned.first.speciesId, 'wave_otter');
    expect(imported.starterSpeciesId, 'pine_fox');
  });

  test(
    'second battle needs the first clear and a second squad member',
    () async {
      final prefs = SharedPreferencesAsync();
      final game = GameStore(prefs);
      await game.chooseStarter('pine_fox');
      final secondId = firstForestStages[1].id;
      expect(await game.runForestBattle(secondId), isNull);
      await game.creditCompletedTasks(['task-a', 'task-b', 'task-c', 'task-d']);
      for (var index = 0; index < 3; index++) {
        final departed = DateTime.utc(2026, 11, 3, index * 2);
        expect(await game.startTraining(now: departed), isTrue);
        expect(
          await game.finishTraining(
            now: departed.add(const Duration(minutes: 1)),
          ),
          isTrue,
        );
      }
      expect(await game.runForestBattle(secondId), isNull);
      final first = await game.runFirstBattle();
      expect(first?.won, isTrue);
      expect(game.owned.last.id, GameStore.firstForestCompanionId);
      final passesBeforeLoss = game.trainingPasses;
      final loss = await game.runForestBattle(secondId);
      expect(loss?.won, isFalse);
      expect(game.trainingPasses, passesBeforeLoss - 1);
      expect(game.adventureClears, 1);
      expect(game.stageProgress[secondId], isNull);

      expect(
        await game.moveCreatureToSlot(GameStore.firstForestCompanionId, 1),
        isTrue,
      );
      final win = await game.runForestBattle(secondId);
      expect(win?.won, isTrue);
      expect(win?.rewardSpeciesId, isNull);
      expect(game.adventureClears, 2);
      expect(game.stageProgress[secondId]?.clearCount, 1);
      expect(game.stageProgress[secondId]?.stars, inInclusiveRange(1, 3));
      expect(game.owned, hasLength(2));
      expect(game.owned.first.level, 2);
      expect(game.owned.last.battleExperience, 2);
      final repeat = await game.runForestBattle(secondId);
      expect(repeat?.won, isTrue);
      expect(
        repeat?.leveledUpCreatureIds,
        contains(GameStore.firstForestCompanionId),
      );
      expect(game.owned.last.level, 2);

      final restored = GameStore(prefs);
      await restored.load();
      expect(restored.adventureClears, 2);
      expect(restored.stageProgress[secondId]?.clearCount, 2);
      expect(restored.trainingPasses, game.trainingPasses);
      expect(restored.squad[1], GameStore.firstForestCompanionId);
      expect(restored.owned.last.level, 2);
      final backup = GameSnapshot.fromJson(game.exportSnapshot()!.toJson());
      expect(backup.owned.last.level, 2);
      expect(backup.owned.last.battleExperience, 1);
    },
  );

  test('second battle upgrades an already opened story place', () async {
    final prefs = SharedPreferencesAsync();
    final game = GameStore(prefs);
    await game.chooseStarter('star_crow');
    await game.creditCompletedTasks(['task-a', 'task-b', 'task-c']);
    for (var index = 0; index < 3; index++) {
      final departed = DateTime.utc(2026, 11, 3, index * 2);
      await game.startTraining(now: departed);
      await game.finishTraining(now: departed.add(const Duration(minutes: 1)));
    }
    expect(await game.clearAdventureStage(0), isTrue);
    expect(await game.clearAdventureStage(1), isTrue);
    expect(game.adventureClears, 2);
    expect(game.stageProgress[firstForestStages[1].id]?.stars, 0);
    expect(await game.runForestBattle(firstForestStages[1].id), isNull);
    expect((await game.runFirstBattle())?.won, isTrue);
    expect(
      await game.moveCreatureToSlot(GameStore.firstForestCompanionId, 1),
      isTrue,
    );
    final second = await game.runForestBattle(firstForestStages[1].id);
    expect(second?.won, isTrue);
    expect(game.adventureClears, 2);
    expect(game.stageProgress[firstForestStages[1].id]?.clearCount, 2);
    expect(game.stageProgress[firstForestStages[1].id]?.stars, greaterThan(0));
  });

  test(
    'river story exploration persists without spending a battle pass',
    () async {
      final prefs = SharedPreferencesAsync();
      await prefs.setString(
        'game_collection_v1',
        jsonEncode({
          'version': 1,
          'owned': [
            {'id': 'starter-1', 'speciesId': 'pine_fox', 'level': 4},
          ],
          'squad': ['starter-1', null, null, null, null],
          'trainingCompletions': 7,
          'adventureClears': 3,
          'trainingPasses': 4,
          'stageProgress': {
            for (final stage in firstForestStages)
              stage.id: const StageProgress(clearCount: 1, stars: 1).toJson(),
          },
        }),
      );
      final game = GameStore(prefs);
      await game.load();
      expect(game.loadFailed, isFalse);
      expect(await game.exploreRiverStage(riverStages[1].id), isFalse);
      expect(await game.exploreRiverStage(riverStages.first.id), isTrue);
      expect(await game.exploreRiverStage(riverStages.first.id), isFalse);
      expect(game.stageProgress[riverStages.first.id]?.clearCount, 1);
      expect(game.stageProgress[riverStages.first.id]?.stars, 0);
      expect(game.trainingPasses, 4);
      expect(await game.exploreRiverStage(riverStages[1].id), isFalse);

      final restored = GameStore(prefs);
      await restored.load();
      expect(restored.stageProgress[riverStages.first.id]?.clearCount, 1);
      expect(restored.stageProgress[riverStages.first.id]?.stars, 0);
      expect(restored.trainingPasses, 4);
    },
  );

  testWidgets('river exploration story opens on a narrow map', (tester) async {
    tester.view.physicalSize = const Size(300, 700);
    tester.view.devicePixelRatio = 1;
    tester.binding.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(
      tester.binding.platformDispatcher.clearTextScaleFactorTestValue,
    );
    final prefs = SharedPreferencesAsync();
    await prefs.setString(
      'game_collection_v1',
      jsonEncode({
        'version': 1,
        'owned': [
          {'id': 'starter-1', 'speciesId': 'pine_fox', 'level': 4},
        ],
        'squad': ['starter-1', null, null, null, null],
        'trainingCompletions': 7,
        'adventureClears': 3,
        'trainingPasses': 4,
        'stageProgress': {
          for (final stage in firstForestStages)
            stage.id: const StageProgress(clearCount: 1, stars: 1).toJson(),
        },
      }),
    );
    final game = GameStore(prefs);
    await game.load();
    await tester.pumpWidget(MaterialApp(home: GamePage(gameStore: game)));
    await openGameTab(tester, '모험');
    final mapScroll = find.descendant(
      of: find.byKey(const ValueKey('game-section-1')),
      matching: find.byType(Scrollable),
    );
    final beforeSummary = find.text('안개 강가 · 장소 기록 0/3 · 기기 전투 0/3');
    await tester.scrollUntilVisible(beforeSummary, 300, scrollable: mapScroll);
    expect(beforeSummary, findsOneWidget);
    final storyButton = find.text('강가 입구 탐색 이야기');
    await tester.scrollUntilVisible(storyButton, 300, scrollable: mapScroll);
    await tester.ensureVisible(storyButton);
    await tester.pumpAndSettle();
    final storyAction = tester.widget<TextButton>(
      find.ancestor(of: storyButton, matching: find.byType(TextButton)),
    );
    expect(
      storyAction.style?.foregroundColor?.resolve({}),
      const Color(0xFFAAD7F3),
    );
    await tester.tap(storyButton);
    await tester.pumpAndSettle();
    expect(find.textContaining('물안개가 강둑을 가렸어요'), findsOneWidget);
    expect(find.text('탐색 기록하기'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('탐색 기록하기'));
    await tester.pump(const Duration(milliseconds: 500));
    expect(game.stageProgress[riverStages.first.id]?.clearCount, 1);
    expect(game.trainingPasses, 4);
    final afterSummary = find.text('안개 강가 · 장소 기록 1/3 · 기기 전투 0/3');
    await tester.scrollUntilVisible(afterSummary, -300, scrollable: mapScroll);
    expect(afterSummary, findsOneWidget);
    expect(find.text('기기 장소 기록 있음'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  test(
    'dawn boss opens after seven returns and preserves its victory',
    () async {
      final prefs = SharedPreferencesAsync();
      final game = GameStore(prefs);
      await game.chooseStarter('star_crow');
      await game.creditCompletedTasks(
        List.generate(7, (index) => 'task-$index'),
      );
      final today = DateTime.now();
      final day =
          '${today.year.toString().padLeft(4, '0')}-'
          '${today.month.toString().padLeft(2, '0')}-'
          '${today.day.toString().padLeft(2, '0')}';
      expect(
        await game.creditRewards([
          for (var index = 0; index < 4; index++)
            (
              sourceId: 'mini-$index',
              kind: 'mini',
              trainingPasses: RewardRules.expectedForKind('mini').passes,
              experience: RewardRules.expectedForKind('mini').xp,
              activityDay: day,
            ),
        ]),
        4,
      );
      final dawnId = firstForestStages[2].id;
      final riverId = riverStages.first.id;
      expect(await game.runForestBattle(riverStages[1].id), isNull);
      expect(await game.runForestBattle(riverStages.last.id), isNull);
      expect(await game.runForestBattle(riverId), isNull);
      expect(await game.runForestBattle(dawnId), isNull);
      for (var index = 0; index < 7; index++) {
        final departed = DateTime.utc(2026, 11, 3, index * 2);
        expect(await game.startTraining(now: departed), isTrue);
        expect(
          await game.finishTraining(
            now: departed.add(const Duration(minutes: 1)),
          ),
          isTrue,
        );
      }
      expect(await game.runForestBattle(dawnId), isNull);
      expect((await game.runFirstBattle())?.won, isTrue);
      expect(
        await game.moveCreatureToSlot(GameStore.firstForestCompanionId, 1),
        isTrue,
      );
      expect(await game.runForestBattle(dawnId), isNull);
      for (var index = 0; index < 5; index++) {
        expect(
          (await game.runForestBattle(firstForestStages[1].id))?.won,
          isTrue,
        );
      }
      expect(game.owned.every((creature) => creature.level >= 4), isTrue);
      final result = await game.runForestBattle(dawnId);
      expect(result?.won, isTrue);
      expect(game.adventureClears, 3);
      expect(game.stageProgress[dawnId]?.stars, inInclusiveRange(1, 3));
      expect(
        await game.creditRewards([
          (
            sourceId: 'river-ticket',
            kind: 'mini',
            trainingPasses: 1,
            experience: 10,
            activityDay: day,
          ),
        ]),
        1,
      );
      final riverResult = await game.runForestBattle(riverId);
      expect(riverResult?.won, isTrue);
      expect(await game.runForestBattle(riverStages.last.id), isNull);
      expect(
        await game.creditRewards([
          for (var index = 0; index < 2; index++)
            (
              sourceId: 'river-next-$index',
              kind: 'mini',
              trainingPasses: 1,
              experience: 10,
              activityDay: day,
            ),
        ]),
        2,
      );
      expect((await game.runForestBattle(riverStages[1].id))?.won, isTrue);
      expect(
        game.owned
            .where((creature) => creature.id == GameStore.riverCompanionId)
            .single
            .speciesId,
        'pebble_newt',
      );
      expect(game.discoveredSpeciesIds, contains('pebble_newt'));
      expect((await game.runForestBattle(riverStages.last.id))?.won, isTrue);
      expect(game.adventureClears, 3);
      expect(game.stageProgress[riverId]?.stars, inInclusiveRange(1, 3));
      final restored = GameStore(prefs);
      await restored.load();
      expect(restored.stageProgress[dawnId]?.clearCount, 1);
      expect(restored.stageProgress[riverId]?.clearCount, 1);
      expect(restored.stageProgress[riverStages[1].id]?.clearCount, 1);
      expect(restored.stageProgress[riverStages.last.id]?.clearCount, 1);
      expect(
        GameSnapshot.fromJson(game.exportSnapshot()!.toJson())
            .discoveredSpeciesIds,
        contains('pebble_newt'),
      );
      expect(
        restored.owned.where(
          (creature) => creature.id == GameStore.riverCompanionId,
        ),
        hasLength(1),
      );
      expect(restored.trainingPasses, game.trainingPasses);
      expect(
        restored.owned.map((creature) => creature.level),
        game.owned.map((creature) => creature.level),
      );
    },
  );

  test(
    'repeat battle experience is limited per stage and Korean day',
    () async {
      final prefs = SharedPreferencesAsync();
      final game = GameStore(prefs);
      await game.chooseStarter('pine_fox');
      await game.creditCompletedTasks(
        List.generate(5, (index) => 'task-$index'),
      );
      await game.startTraining(now: DateTime.utc(2026, 11, 4));
      await game.finishTraining(now: DateTime.utc(2026, 11, 4, 0, 1));
      final stageId = firstForestStages.first.id;
      for (var index = 0; index < 5; index++) {
        final result = await game.runForestBattle(
          stageId,
          now: DateTime.utc(2026, 11, 4, 2),
        );
        expect(result?.won, isTrue);
        expect(result?.experiencePerCreature, 1);
      }
      expect(
        game.remainingStageExperienceWins(
          stageId,
          now: DateTime.utc(2026, 11, 4, 2),
        ),
        0,
      );
      final before = game.owned.first.battleExperience;
      final capped = await game.runForestBattle(
        stageId,
        now: DateTime.utc(2026, 11, 4, 2),
      );
      expect(capped?.won, isTrue);
      expect(capped?.experiencePerCreature, 0);
      expect(game.owned.first.battleExperience, before);
      expect(game.stageProgress[stageId]?.clearCount, 6);

      final restored = GameStore(prefs);
      await restored.load();
      expect(
        restored.remainingStageExperienceWins(
          stageId,
          now: DateTime.utc(2026, 11, 4, 2),
        ),
        0,
      );
      expect(
        restored.remainingStageExperienceWins(
          stageId,
          now: DateTime.utc(2026, 11, 5, 2),
        ),
        5,
      );
      final nextDay = await restored.runForestBattle(
        stageId,
        now: DateTime.utc(2026, 11, 5, 2),
      );
      expect(nextDay?.experiencePerCreature, 1);
      expect(
        restored.remainingStageExperienceWins(
          stageId,
          now: DateTime.utc(2026, 11, 5, 2),
        ),
        4,
      );
      final backup = restored.exportSnapshot()!;
      SharedPreferencesAsyncPlatform.instance =
          InMemorySharedPreferencesAsync.empty();
      final imported = GameStore(SharedPreferencesAsync());
      expect(await imported.importIfEmpty(backup), isTrue);
      expect(
        imported.remainingStageExperienceWins(
          stageId,
          now: DateTime.utc(2026, 11, 5, 2),
        ),
        4,
      );
    },
  );

  test(
    'one completed task grants two departures only once across reload',
    () async {
      final prefs = SharedPreferencesAsync();
      final growth = GrowthStore(prefs);
      await growth.load();
      await growth.addTask('산책');
      final task = growth.tasks.single;
      await growth.toggleTask(task);

      final game = GameStore(prefs);
      await game.chooseStarter('pine_fox');
      expect(await game.startTraining(), isFalse);
      expect(await game.creditCompletedTasks([task.id]), 2);
      expect(game.trainingPasses, 2);
      expect(await game.creditCompletedTasks([task.id]), 0);
      expect(await game.startTraining(now: DateTime.utc(2026, 11, 2)), isTrue);
      expect(game.trainingPasses, 1);

      final restored = GameStore(prefs);
      await restored.load();
      expect(restored.trainingPasses, 1);
      await growth.toggleTask(task);
      await growth.toggleTask(task);
      expect(await restored.creditCompletedTasks([task.id]), 0);
      expect(restored.trainingPasses, 1);
    },
  );

  testWidgets('opening game converts completed checklist items to training', (
    tester,
  ) async {
    final prefs = SharedPreferencesAsync();
    final growth = GrowthStore(prefs);
    await growth.load();
    await growth.addTask('정리하기');
    await growth.toggleTask(growth.tasks.single);
    final game = GameStore(prefs);
    await game.chooseStarter('pine_fox');
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: GamePage(gameStore: game, growthStore: growth),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));
    expect(game.trainingPasses, 2);
    await tester.scrollUntilVisible(find.text('남은 훈련 2회'), 300);
    expect(find.text('남은 훈련 2회'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('repeat completions earn training once per calendar day', (
    tester,
  ) async {
    final prefs = SharedPreferencesAsync();
    final growth = GrowthStore(prefs);
    await growth.load();
    final yesterday = DateTime.now().subtract(const Duration(days: 1));
    await growth.addTask(
      '산책 루틴',
      scheduledDay: dayKey(yesterday),
      repeatPattern: 'daily',
    );
    final task = growth.tasks.single;
    task.completedOccurrences.add(dayKey(yesterday));
    await growth.toggleTask(task);
    final game = GameStore(prefs);
    await game.chooseStarter('pine_fox');
    await tester.pumpWidget(
      MaterialApp(
        home: GamePage(gameStore: game, growthStore: growth),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));
    expect(game.trainingPasses, 4);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(
      MaterialApp(
        home: GamePage(gameStore: game, growthStore: growth),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));
    expect(game.trainingPasses, 4);
  });

  test(
    'starter and first squad slot survive reload without duplicates',
    () async {
      final store = GameStore(SharedPreferencesAsync());
      await store.load();
      expect(await store.chooseStarter('pine_fox'), isTrue);
      expect(await store.chooseStarter('wave_otter'), isFalse);
      expect(store.owned, hasLength(1));
      expect(store.squad, ['starter-1', null, null, null, null]);

      final restored = GameStore(SharedPreferencesAsync());
      await restored.load();
      expect(restored.owned.single.speciesId, 'pine_fox');
      expect(await restored.changeStarter('wave_otter'), isTrue);
      expect(restored.owned, hasLength(1));
      expect(restored.squad.first, 'starter-1');

      final changed = GameStore(SharedPreferencesAsync());
      await changed.load();
      expect(changed.owned.single.speciesId, 'wave_otter');
      expect(changed.discoveredSpeciesIds, {'pine_fox', 'wave_otter'});
      expect(await changed.moveCreatureToSlot('starter-1', 4), isTrue);
      expect(changed.squad, [null, null, null, null, 'starter-1']);
      final moved = GameStore(SharedPreferencesAsync());
      await moved.load();
      expect(moved.squad.last, 'starter-1');
      expect(await moved.creditCompletedTasks(['task-a']), 2);
      expect(await moved.startTraining(now: DateTime.utc(2026, 11, 1)), isTrue);
    },
  );

  test(
    'clearing a squad slot persists and training requires a member',
    () async {
      final prefs = SharedPreferencesAsync();
      final game = GameStore(prefs);
      await game.chooseStarter('pine_fox');
      expect(await game.clearSquadSlot(0), isTrue);
      expect(await game.clearSquadSlot(0), isFalse);
      expect(game.squad, everyElement(isNull));
      final restored = GameStore(prefs);
      await restored.load();
      expect(restored.squad, everyElement(isNull));
      await restored.creditCompletedTasks(['task-a']);
      expect(await restored.startTraining(), isFalse);
      expect(await restored.moveCreatureToSlot('starter-1', 2), isTrue);
      expect(restored.squad[2], 'starter-1');
    },
  );

  test(
    'twenty duplicate-species instances fit; a twenty-first is rejected',
    () async {
      final prefs = SharedPreferencesAsync();
      final owned = List.generate(
        20,
        (index) => {
          'id': 'creature-$index',
          'speciesId': 'pine_fox',
          'level': 1,
        },
      );
      Map<String, Object> snapshot(List<Map<String, Object>> creatures) => {
        'version': 1,
        'owned': creatures,
        'squad': [
          'creature-0',
          'creature-1',
          'creature-2',
          'creature-3',
          'creature-4',
        ],
      };
      await prefs.setString('game_collection_v1', jsonEncode(snapshot(owned)));
      final store = GameStore(prefs);
      await store.load();
      expect(store.loadFailed, isFalse);
      expect(store.owned, hasLength(20));
      expect(store.discoveredSpeciesIds, {'pine_fox'});
      expect(await store.moveCreatureToSlot('creature-2', 0), isTrue);
      expect(store.squad.take(3), ['creature-2', 'creature-1', 'creature-0']);
      expect(await store.moveCreatureToSlot('creature-19', 0), isTrue);
      expect(store.squad.first, 'creature-19');
      expect(store.squad.whereType<String>().toSet(), hasLength(5));

      final tooMany = jsonEncode(
        snapshot([
          ...owned,
          {'id': 'creature-20', 'speciesId': 'pine_fox', 'level': 1},
        ]),
      );
      await prefs.setString('game_collection_v1', tooMany);
      final rejected = GameStore(prefs);
      await rejected.load();
      expect(rejected.loadFailed, isTrue);
      expect(await prefs.getString('game_collection_v1'), tooMany);
    },
  );

  test('invalid saved game is not overwritten by a new starter', () async {
    final prefs = SharedPreferencesAsync();
    await prefs.setString('game_collection_v1', '{invalid');
    final store = GameStore(prefs);
    await store.load();
    expect(store.loadFailed, isTrue);
    expect(await store.chooseStarter('pine_fox'), isFalse);
    expect(await prefs.getString('game_collection_v1'), '{invalid');
  });

  test(
    'training departure and return survive reload without duplicate credit',
    () async {
      final start = DateTime.utc(2026, 11, 1, 12);
      final store = GameStore(SharedPreferencesAsync());
      expect(await store.startTraining(now: start), isFalse);
      expect(await store.chooseStarter('star_crow'), isTrue);
      expect(await store.creditCompletedTasks(['task-a']), 2);
      expect(
        await Future.wait([
          store.startTraining(now: start),
          store.startTraining(now: start),
        ]),
        [true, false],
      );
      expect(await store.changeStarter('pine_fox'), isFalse);
      expect(store.trainingRemaining(now: start), GameStore.trainingDuration);

      final restored = GameStore(SharedPreferencesAsync());
      await restored.load();
      expect(restored.trainingEndsAt, start.add(GameStore.trainingDuration));
      expect(
        await restored.finishTraining(
          now: start.add(const Duration(seconds: 29)),
        ),
        isFalse,
      );
      expect(
        await Future.wait([
          restored.finishTraining(now: start.add(const Duration(seconds: 30))),
          restored.finishTraining(now: start.add(const Duration(seconds: 30))),
        ]),
        [true, false],
      );
      expect(
        await restored.finishTraining(
          now: start.add(const Duration(minutes: 1)),
        ),
        isFalse,
      );
      expect(restored.trainingCompletions, 1);
      expect(restored.owned.single.speciesId, 'star_crow');

      final completed = GameStore(SharedPreferencesAsync());
      await completed.load();
      expect(completed.trainingEndsAt, isNull);
      expect(completed.trainingCompletions, 1);
      expect(await completed.changeStarter('pine_fox'), isTrue);
    },
  );

  testWidgets('first training return unlocks an explorable place', (
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
    final store = GameStore(SharedPreferencesAsync());
    await store.chooseStarter('pine_fox');
    await store.creditCompletedTasks(['task-a']);
    await store.startTraining(
      now: DateTime.now().subtract(const Duration(minutes: 1)),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: GamePage(gameStore: store)),
      ),
    );
    await store.finishTraining(now: DateTime.now());
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.textContaining('다음 전투 ·'), findsOneWidget);
    expect(store.trainingCompletions, 1);
    await openGameTab(tester, '모험');
    await tester.scrollUntilVisible(find.text('탐험하기'), 250);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('탐험하기'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('탐험하기'));
    await tester.pump();
    expect(find.text('발자국 찾기'), findsOneWidget);
    await tester.tap(find.text('발자국 찾기'));
    await tester.pump(const Duration(milliseconds: 500));
    expect(store.adventureClears, 1);
    expect(find.text('숲길 지도 · 해금 1/3'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('장소 정보').first, 250);
    await tester.ensureVisible(find.text('장소 정보').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('장소 정보').first);
    await tester.pumpAndSettle();
    expect(find.text('상태 · 이야기 해금 · 전투 미승리'), findsOneWidget);
    expect(find.text('1웨이브 · 이끼 포자 Lv.1'), findsOneWidget);
    expect(find.text('기록 · 별 0/3 · 최고 턴 —'), findsOneWidget);
    expect(find.text('서버 보상 계획'), findsOneWidget);
    expect(find.text('첫 승리 · 조각 1개'), findsOneWidget);
    expect(find.text('서버 조각·배지 · 준비 중'), findsOneWidget);
    await tester.tap(find.text('전투 준비'));
    await tester.pumpAndSettle();
    expect(find.byType(BattlePreparationPage), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('choosing a starter opens the squad view', (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final store = GameStore(SharedPreferencesAsync());
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: GamePage(gameStore: store)),
      ),
    );
    expect(find.text('첫 신수 선택'), findsOneWidget);
    await tester.tap(find.text('선택').first);
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('솔여우와 함께할까요?'), findsOneWidget);
    await tester.tap(find.text('선택하기'));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('스쿼드 · 1/5'), findsOneWidget);
    expect(find.text('빈 자리'), findsNWidgets(4));
    await tester.ensureVisible(find.text('빈 자리').first);
    await tester.tap(find.text('빈 자리').first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('스쿼드에 편성할 신수'), findsOneWidget);
    await tester.ensureVisible(find.text('Lv 1 · 태동 · 균형'));
    await tester.tap(find.text('Lv 1 · 태동 · 균형'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(store.squad[0], isNull);
    expect(store.squad[1], 'starter-1');
    await openGameTab(tester, '임무');
    await tester.scrollUntilVisible(find.text('훈련 파견 출발'), 300);
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('훈련 파견 출발'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('game home points from training to the first battle', (
    tester,
  ) async {
    final store = GameStore(SharedPreferencesAsync());
    await store.chooseStarter('pine_fox');
    await store.creditCompletedTasks(['task-a']);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: GamePage(gameStore: store)),
      ),
    );
    expect(find.textContaining('훈련 1회 남음'), findsOneWidget);
    await tester.tap(find.text('훈련 출발'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(store.trainingEndsAt, isNotNull);
    expect(find.textContaining('훈련 중이에요'), findsOneWidget);
    await store.finishTraining(
      now: DateTime.now().add(const Duration(minutes: 1)),
    );
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.textContaining('다음 전투 · 이끼 문턱'), findsOneWidget);
    expect(find.text('전투 정보'), findsOneWidget);
    expect((await store.runFirstBattle())?.won, isTrue);
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.textContaining('새 동료를 스쿼드에 편성해요'), findsOneWidget);
    await tester.tap(find.text('편성하기'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    final companionChoice = find.byKey(
      const ValueKey('squad-choice-${GameStore.firstForestCompanionId}'),
    );
    await tester.ensureVisible(companionChoice);
    await tester.pump();
    await tester.tap(companionChoice);
    await tester.pump(const Duration(milliseconds: 300));
    expect(store.squad, contains(GameStore.firstForestCompanionId));
    expect(find.textContaining('훈련 2회 남음'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('collection card assigns a companion to a chosen squad slot', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final store = GameStore(SharedPreferencesAsync());
    await store.chooseStarter('pine_fox');
    await store.creditCompletedTasks(['task-a']);
    await store.startTraining(now: DateTime.utc(2026, 11, 3));
    await store.finishTraining(now: DateTime.utc(2026, 11, 3, 0, 1));
    await store.runFirstBattle();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: GamePage(gameStore: store)),
      ),
    );
    final card = find.byKey(
      const ValueKey('owned-creature-${GameStore.firstForestCompanionId}'),
    );
    await openGameTab(tester, '신수');
    await tester.scrollUntilVisible(
      card,
      250,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.ensureVisible(card);
    await tester.pumpAndSettle();
    await tester.tap(card);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ListTile, '2번 · 전열'));
    await tester.pumpAndSettle();
    expect(store.squad[1], GameStore.firstForestCompanionId);
    expect(tester.takeException(), isNull);
  });

  testWidgets('game home keeps a route back to growth before the boss', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final store = GameStore(SharedPreferencesAsync());
    await store.chooseStarter('pine_fox');
    await store.creditCompletedTasks(List.generate(5, (i) => 'task-$i'));
    final today = DateTime.now();
    final day =
        '${today.year.toString().padLeft(4, '0')}-'
        '${today.month.toString().padLeft(2, '0')}-'
        '${today.day.toString().padLeft(2, '0')}';
    await store.creditRewards([
      for (var i = 0; i < 4; i++)
        (
          sourceId: 'mini-$i',
          kind: 'mini',
          trainingPasses: RewardRules.expectedForKind('mini').passes,
          experience: RewardRules.expectedForKind('mini').xp,
          activityDay: day,
        ),
    ]);
    for (var i = 0; i < 7; i++) {
      final departed = DateTime.utc(2026, 11, 3, i * 2);
      await store.startTraining(now: departed);
      await store.finishTraining(now: departed.add(const Duration(minutes: 1)));
    }
    expect((await store.runFirstBattle())?.won, isTrue);
    await store.moveCreatureToSlot(GameStore.firstForestCompanionId, 1);
    expect((await store.runForestBattle(firstForestStages[1].id))?.won, isTrue);
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(2)),
          child: Scaffold(body: GamePage(gameStore: store)),
        ),
      ),
    );
    expect(find.textContaining('오솔길에서 다시 이겨'), findsOneWidget);
    await tester.ensureVisible(find.text('오솔길 전투 정보'));
    await tester.pump();
    await tester.tap(find.text('오솔길 전투 정보'));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('반딧불이 오솔길'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('training scene shows the first assigned squad creature', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final prefs = SharedPreferencesAsync();
    await prefs.setString(
      'game_collection_v1',
      jsonEncode({
        'version': 1,
        'owned': [
          {'id': 'fox-1', 'speciesId': 'pine_fox', 'level': 1},
          {'id': 'crow-1', 'speciesId': 'star_crow', 'level': 1},
        ],
        'squad': ['crow-1', 'fox-1', null, null, null],
        'trainingEndsAt': DateTime.now()
            .toUtc()
            .add(const Duration(minutes: 1))
            .toIso8601String(),
      }),
    );
    final store = GameStore(prefs);
    await store.load();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: GamePage(gameStore: store)),
      ),
    );
    await tester.drag(find.byType(ListView).first, const Offset(0, -1000));
    await tester.pump(const Duration(milliseconds: 500));
    final traveler = tester
        .widgetList<GameStaticSprite>(find.byType(GameStaticSprite))
        .where((sprite) => sprite.size == 64)
        .single;
    expect(traveler.speciesId, 'star_crow');
  });

  testWidgets('game fits a narrow screen with larger system text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final store = GameStore(SharedPreferencesAsync());
    await store.chooseStarter('star_crow');
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(1.3)),
          child: Scaffold(body: GamePage(gameStore: store)),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 500));
    await openGameTab(tester, '신수');
    expect(find.text('스쿼드 · 1/5'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.scrollUntilVisible(find.text('도감 · 1/4'), 400);
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('도감 · 1/4'), findsOneWidget);
    expect(find.text('이끼 문턱 첫 전투 승리에서 확정 합류해요.'), findsOneWidget);
    expect(find.text('정식 파견·무료 뽑기 기능이 열리면 만날 수 있어요.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('game sections remain scrollable at 200 percent text size', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    tester.binding.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(
      tester.binding.platformDispatcher.clearTextScaleFactorTestValue,
    );
    final store = GameStore(SharedPreferencesAsync());
    await store.chooseStarter('wave_otter');
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: GamePage(gameStore: store)),
      ),
    );
    await tester.pump(const Duration(milliseconds: 500));
    await openGameTab(tester, '신수');
    await tester.drag(find.byType(ListView).first, const Offset(0, -800));
    await tester.pump(const Duration(milliseconds: 500));
    final slotName = find.text('파도수달').last;
    final slotCard = find
        .ancestor(of: slotName, matching: find.byType(InkWell))
        .first;
    expect(
      tester.getRect(slotCard).contains(tester.getRect(slotName).bottomCenter),
      isTrue,
    );
    final emptySlot = find.text('빈 자리').first;
    final slotCenter = tester.getRect(emptySlot).center.dy;
    await tester.drag(find.byType(ListView).first, Offset(0, 350 - slotCenter));
    await tester.pump();
    await tester.tap(emptySlot);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('편성할 신수'), findsOneWidget);
    expect(tester.takeException(), isNull);
    Navigator.of(tester.element(find.text('편성할 신수'))).pop();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.drag(find.byType(ListView).first, const Offset(0, -1600));
    await tester.pump(const Duration(milliseconds: 500));
  });

  testWidgets('discovered creature opens a detailed dex sheet', (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final store = GameStore(SharedPreferencesAsync());
    await store.chooseStarter('pine_fox');
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: GamePage(gameStore: store)),
      ),
    );
    await openGameTab(tester, '신수');
    await tester.scrollUntilVisible(find.text('도감 · 1/4'), 400);
    final entry = find.text('솔여우').last;
    await tester.ensureVisible(entry);
    await tester.pump(const Duration(milliseconds: 500));
    await tester.tap(entry);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('도감 기록'), findsOneWidget);
    expect(find.textContaining('보유 1마리'), findsOneWidget);
    await tester.tap(find.text('닫기'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('도감 기록'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('unseen creature shows its silhouette and acquisition clue', (
    tester,
  ) async {
    final store = GameStore(SharedPreferencesAsync());
    await store.chooseStarter('pine_fox');
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: GamePage(gameStore: store)),
      ),
    );
    await openGameTab(tester, '신수');
    await tester.scrollUntilVisible(find.text('도감 · 1/4'), 400);
    await tester.drag(find.byType(ListView).first, const Offset(0, -320));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.ensureVisible(find.text('미발견').first);
    await tester.tap(find.text('미발견').first);
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('미발견 신수'), findsOneWidget);
    expect(find.textContaining('첫 전투 승리에서 확정 합류'), findsWidgets);
    expect(find.byType(ColorFiltered), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('forest map markers open stage details on a small screen', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(300, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var selected = -1;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(2)),
            child: SingleChildScrollView(
              child: TrainingJournal(
                completed: 1,
                cleared: 1,
                onDetails: (index) => selected = index,
              ),
            ),
          ),
        ),
      ),
    );
    final marker = find.byKey(
      const ValueKey('forest-map-stage-forest_firefly_path'),
    );
    await tester.ensureVisible(marker);
    await tester.tap(marker);
    expect(selected, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('forest map distinguishes training from account expedition', (
    tester,
  ) async {
    var missionOpened = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: TrainingJournal(
              completed: 0,
              cleared: 0,
              hasAccountExpedition: true,
              onMission: () => missionOpened = true,
            ),
          ),
        ),
      ),
    );
    expect(find.textContaining('기기 훈련 · 30초'), findsOneWidget);
    expect(find.textContaining('계정 정식 파견 · 10분'), findsOneWidget);
    await tester.tap(find.text('임무에서 파견하기'));
    expect(missionOpened, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('battle result returns to the adventure map', (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final store = GameStore(SharedPreferencesAsync());
    await store.chooseStarter('pine_fox');
    await store.creditCompletedTasks(['task-a']);
    await store.startTraining(now: DateTime.utc(2026, 11, 3));
    await store.finishTraining(now: DateTime.utc(2026, 11, 3, 0, 1));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: GamePage(gameStore: store)),
      ),
    );
    await openGameTab(tester, '모험');
    await tester.tap(
      find.byKey(const ValueKey('forest-map-stage-forest_moss_gate')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('전투 준비'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('전투 시작'), 250);
    await tester.tap(find.text('전투 시작'));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byType(BattlePlaybackPage), findsOneWidget);
    await tester.tap(find.text('결과까지 보기'));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('지도로 돌아가기'), findsNothing);
    await tester.pageBack();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.textContaining('기기 전투 클리어 1/3'), findsOneWidget);
    expect(find.byType(GamePage), findsOneWidget);
    expect(
      tester
          .widget<BottomNavigationBar>(find.byType(BottomNavigationBar))
          .currentIndex,
      1,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('reward tab explains the balance and routes back to training', (
    tester,
  ) async {
    final growth = GrowthStore(SharedPreferencesAsync());
    await growth.addTask('독서 준비하기');
    final store = GameStore(SharedPreferencesAsync());
    await store.chooseStarter('pine_fox');
    await store.creditCompletedTasks([growth.tasks.single.id]);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: GamePage(gameStore: store, growthStore: growth),
        ),
      ),
    );
    await openGameTab(tester, '보상');
    expect(find.text('훈련 가능 2회'), findsOneWidget);
    expect(find.text('할 일 완료 · 훈련권 +2회'), findsOneWidget);
    expect(find.text('지급 기록 1건 · 훈련 귀환 0회'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('임무에서 훈련하기'), 200);
    await tester.tap(find.text('임무에서 훈련하기'));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('다음 걸음'), findsOneWidget);
    await openGameTab(tester, '보상');
    await tester.scrollUntilVisible(find.text('전체 보기'), 300);
    await tester.drag(find.byType(ListView).first, const Offset(0, -140));
    await tester.pumpAndSettle();
    await tester.tap(find.text('전체 보기'));
    await tester.pumpAndSettle();
    expect(find.text('훈련권 지급 내역'), findsOneWidget);
    expect(find.textContaining('기록 1건 · 지급된 훈련권 2회'), findsOneWidget);
    expect(find.text('독서 준비하기'), findsOneWidget);
    expect(find.text('훈련권 +2'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('reward balance and history fit 300dp with large text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(300, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final store = GameStore(SharedPreferencesAsync());
    await store.chooseStarter('pine_fox');
    await store.creditCompletedTasks(['task-a']);
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(2)),
          child: Scaffold(body: GamePage(gameStore: store)),
        ),
      ),
    );
    await openGameTab(tester, '보상');
    await tester.scrollUntilVisible(find.text('전체 보기'), 220);
    await tester.drag(find.byType(ListView).first, const Offset(0, -150));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('전체 보기'));
    await tester.pumpAndSettle();
    expect(find.text('훈련권 지급 내역'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('dex compares duplicate creatures and squad positions', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final seed = GameStore(SharedPreferencesAsync());
    await seed.chooseStarter('pine_fox');
    final data = seed.exportSnapshot()!.toJson();
    (data['owned'] as List).add({
      'id': 'fox-copy',
      'speciesId': 'pine_fox',
      'level': 3,
      'battleExperience': 1,
    });
    final slots = List<Object?>.from(data['squad'] as List);
    slots[1] = 'fox-copy';
    data['squad'] = slots;
    final backup = GameSnapshot.fromJson(data);
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    final game = GameStore(SharedPreferencesAsync());
    expect(await game.importIfEmpty(backup), isTrue);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: GamePage(gameStore: game)),
      ),
    );
    await openGameTab(tester, '신수');
    await tester.scrollUntilVisible(find.text('도감 · 1/4'), 400);
    final entry = find.text('솔여우').last;
    await tester.ensureVisible(entry);
    await tester.tap(entry);
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.textContaining('보유 2마리'), findsOneWidget);
    expect(find.textContaining('2번 · 각성 · Lv 3 · 편성 2번'), findsOneWidget);
    expect(find.text('체력 74 · 공격 20 · 전투 경험 1/3'), findsOneWidget);
    expect(find.textContaining('각성 · Lv 3부터'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('evolution comparison and close button fit large text', (
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
    final seed = GameStore(SharedPreferencesAsync());
    await seed.chooseStarter('pine_fox');
    final data = seed.exportSnapshot()!.toJson();
    final starter = Map<String, dynamic>.from((data['owned'] as List).single);
    starter['level'] = 3;
    starter['battleExperience'] = 1;
    data['owned'] = [starter];
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    final game = GameStore(SharedPreferencesAsync());
    expect(await game.importIfEmpty(GameSnapshot.fromJson(data)), isTrue);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: GamePage(gameStore: game)),
      ),
    );
    await openGameTab(tester, '신수');
    await tester.scrollUntilVisible(find.text('도감 · 1/4'), 400);
    await tester.drag(find.byType(ListView).first, const Offset(0, -400));
    await tester.pumpAndSettle();
    final entry = find
        .descendant(
          of: find.byType(GestureDetector),
          matching: find.text('솔여우'),
        )
        .last;
    await Scrollable.ensureVisible(tester.element(entry), alignment: 0.5);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(entry);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.textContaining('1번 · 각성 · Lv 3'), findsOneWidget);
    expect(find.textContaining('초월까지 전투 경험 5 더'), findsOneWidget);
    expect(find.text('성장 단계 비교'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('닫기'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('도감 기록'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('starter choices fit a narrow screen with larger text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final store = GameStore(SharedPreferencesAsync());
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(1.3)),
          child: Scaffold(body: GamePage(gameStore: store)),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('첫 신수 선택'), findsOneWidget);
    await tester.ensureVisible(find.text('솔여우'));
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('starter choices fit a narrow screen at 200 percent text size', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final store = GameStore(SharedPreferencesAsync());
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(2)),
          child: Scaffold(body: GamePage(gameStore: store)),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 500));
    expect(tester.takeException(), isNull);
    await tester.drag(find.byType(ListView).first, const Offset(0, -900));
    await tester.pump(const Duration(milliseconds: 500));
    expect(tester.takeException(), isNull);
  });

  testWidgets('squad and training fit 300dp at 200 percent text size', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(300, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final store = GameStore(SharedPreferencesAsync());
    await store.chooseStarter('star_crow');
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(2)),
          child: Scaffold(body: GamePage(gameStore: store)),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 500));
    await openGameTab(tester, '신수');
    await tester.drag(find.byType(ListView).first, const Offset(0, -350));
    await tester.pump();
    expect(tester.getSize(find.text('별까마귀').first).height, lessThan(90));
    expect(tester.takeException(), isNull);
    await tester.scrollUntilVisible(find.text('스쿼드 · 1/5'), 300);
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('스쿼드 · 1/5'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await openGameTab(tester, '임무');
    await tester.scrollUntilVisible(find.text('첫 지역 · 훈련 길'), 300);
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('첫 지역 · 훈련 길'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('training scene shows a traveling companion', (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final store = GameStore(SharedPreferencesAsync());
    await store.chooseStarter('star_crow');
    await store.creditCompletedTasks(['task-a']);
    await store.startTraining(now: DateTime.now());
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: GamePage(gameStore: store)),
      ),
    );
    await tester.drag(find.byType(ListView).first, const Offset(0, -650));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('첫 지역 · 훈련 길'), findsOneWidget);
    expect(find.textContaining('귀환까지'), findsWidgets);
    expect(tester.takeException(), isNull);
  });
}
