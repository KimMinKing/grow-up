import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:growup/daily_content_widgets.dart';
import 'package:growup/main.dart';
import 'package:growup/models/game_snapshot.dart';
import 'package:growup/models/reward_grant.dart';
import 'package:growup/state/game_store.dart';
import 'package:growup/state/growth_store.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
  });

  test(
    'task and goal rewards are credited once across undo and reload',
    () async {
      final prefs = SharedPreferencesAsync();
      final growth = GrowthStore(prefs);
      await growth.load();
      await growth.addGoal(
        title: '읽기',
        mini: '한 쪽',
        more: '십 분',
        max: '한 장',
        path: '균형 있게',
        milestones: ['첫 책'],
      );
      final goal = growth.goals.single;
      await growth.addTask('책상 정리');
      final task = growth.tasks.single;
      await growth.toggleTask(task);
      await growth.complete(goal, 'MINI');

      final game = GameStore(prefs);
      await game.chooseStarter('pine_fox');
      expect(await game.creditRewards(growth.rewardCandidates), 3);
      expect(game.trainingPasses, 3);
      expect(
        game.rewardGrants.map((grant) => grant.kind),
        containsAll(['task', 'mini']),
      );
      expect(
        game.rewardGrants
            .singleWhere((grant) => grant.kind == 'mini')
            .experience,
        10,
      );
      expect(await game.creditRewards(growth.rewardCandidates), 0);
      expect(await game.startTraining(now: DateTime.utc(2026, 11, 3)), isTrue);
      expect(game.trainingPasses, 2);

      await growth.undo(goal);
      await growth.complete(goal, 'MAX');
      await growth.toggleTask(task);
      await growth.toggleTask(task);
      expect(await game.creditRewards(growth.rewardCandidates), 0);
      expect(game.trainingPasses, 2);
      expect(growth.experience, 30);

      final restored = GameStore(prefs);
      await restored.load();
      expect(restored.rewardGrants, hasLength(2));
      expect(await restored.creditRewards(growth.rewardCandidates), 0);
      expect(restored.trainingPasses, 2);
      expect(
        GameSnapshot.fromJson(restored.exportSnapshot()!.toJson()).rewardGrants,
        hasLength(2),
      );
    },
  );

  test(
    'dated practice corrections recalculate XP without repeat rewards',
    () async {
      final prefs = SharedPreferencesAsync();
      final growth = GrowthStore(prefs);
      await growth.load();
      final day = dayKey(DateTime.now().subtract(const Duration(days: 2)));
      await growth.addGoal(
        title: '읽기',
        mini: '한 쪽',
        more: '십 분',
        max: '한 장',
        path: '균형 있게',
        startDate: day,
        milestones: [],
      );
      final goal = growth.goals.single;
      final game = GameStore(prefs);
      await game.chooseStarter('pine_fox');
      expect(await growth.setPracticeOn(goal, day, 'MINI'), isTrue);
      expect(growth.experience, 10);
      expect(await game.creditRewards(growth.rewardCandidates), 1);
      expect(await growth.setPracticeOn(goal, day, 'MAX'), isTrue);
      expect(growth.experience, 30);
      expect(goal.completionActions[day], '한 장');
      expect(await game.creditRewards(growth.rewardCandidates), 0);
      expect(await growth.setPracticeOn(goal, day, null), isTrue);
      expect(growth.experience, 0);
      expect(goal.completionActions.containsKey(day), isFalse);
      expect(await growth.setPracticeOn(goal, day, 'MORE'), isTrue);
      expect(await game.creditRewards(growth.rewardCandidates), 0);
      expect(game.rewardGrants.single.sourceId, 'goal:${goal.id}:$day');
      expect(game.rewardGrants.single.trainingPasses, 1);
      expect(growth.experience, 20);
      expect(
        await growth.setPracticeOn(
          goal,
          dayKey(DateTime.now().add(const Duration(days: 1))),
          'MINI',
        ),
        isFalse,
      );
      final restored = GrowthStore(prefs);
      await restored.load();
      expect(restored.goals.single.completions[day], 'MORE');
      expect(restored.goals.single.completionActions[day], '십 분');
    },
  );

  testWidgets('goal history edits an earlier practice day', (tester) async {
    final store = GrowthStore(SharedPreferencesAsync());
    await store.load();
    final day = dayKey(DateTime.now().subtract(const Duration(days: 2)));
    await store.addGoal(
      title: '읽기',
      mini: '한 쪽',
      more: '십 분',
      max: '한 장',
      path: '균형 있게',
      startDate: day,
      milestones: [],
    );
    final goal = store.goals.single;
    await store.setPracticeOn(goal, day, 'MINI');
    await tester.pumpWidget(MaterialApp(
      home: GoalHistoryPage(goal: goal, store: store),
    ));
    final edit = find.byTooltip('이날 기록 수정');
    await tester.scrollUntilVisible(edit, 300);
    await tester.tap(edit);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ListTile, 'MAX'));
    await tester.pumpAndSettle();
    expect(goal.completions[day], 'MAX');
    expect(store.experience, 30);
    expect(tester.takeException(), isNull);
  });

  test('repeat occurrences and goal levels keep distinct source IDs', () async {
    final firstDay = dayKey(DateTime.now().subtract(const Duration(days: 2)));
    final secondDay = dayKey(DateTime.now().subtract(const Duration(days: 1)));
    final prefs = SharedPreferencesAsync();
    final growth = GrowthStore(prefs);
    await growth.load();
    await growth.addTask('걷기', repeatPattern: 'daily');
    final task = growth.tasks.single;
    task.completedOccurrences.add(firstDay);
    task.completedOccurrences.add(secondDay);
    await growth.addGoal(
      title: '운동',
      mini: '1분',
      more: '10분',
      max: '30분',
      path: '균형 있게',
      milestones: [],
    );
    final goal = growth.goals.single;
    goal.completions[firstDay] = 'MORE';
    goal.completions[secondDay] = 'MAX';
    final game = GameStore(prefs);
    await game.chooseStarter('pine_fox');
    expect(await game.creditRewards(growth.rewardCandidates), 9);
    expect(
      game.rewardGrants.map((grant) => grant.kind),
      containsAll(['routine', 'more', 'max']),
    );
    expect(
      game.rewardGrants.map((grant) => grant.sourceId).toSet(),
      hasLength(4),
    );
    expect(await game.creditRewards(growth.rewardCandidates), 0);
  });

  test(
    'legacy task credits migrate to dated receipts without extra tickets',
    () async {
      final prefs = SharedPreferencesAsync();
      final game = GameStore(prefs);
      await game.chooseStarter('pine_fox');
      final old = game.exportSnapshot()!.toJson()
        ..remove('rewardGrants')
        ..['creditedTaskIds'] = ['task-old'];
      await prefs.setString('game_collection_v1', jsonEncode(old));
      final restored = GameStore(prefs);
      await restored.load();
      expect(restored.rewardGrants.single.sourceId, 'task-old');
      expect(restored.rewardGrants.single.grantedAt, DateTime.utc(1970));
      expect(restored.trainingPasses, 0);
      expect(await restored.creditCompletedTasks(['task-old']), 0);
      expect(GameSnapshot.fromJson(old).rewardGrants, hasLength(1));
    },
  );

  test('malformed or duplicate receipts are rejected', () async {
    final game = GameStore(SharedPreferencesAsync());
    await game.chooseStarter('pine_fox');
    final old = game.exportSnapshot()!.toJson();
    final receipt = RewardGrant(
      sourceId: 'task-a',
      kind: 'task',
      trainingPasses: 2,
      experience: 0,
      grantedAt: DateTime.utc(2026, 11, 3),
    ).toJson();
    old['rewardGrants'] = [receipt, receipt];
    expect(() => GameSnapshot.fromJson(old), throwsFormatException);
    old['rewardGrants'] = [
      {...receipt, 'trainingPasses': -1},
    ];
    expect(() => GameSnapshot.fromJson(old), throwsFormatException);
  });

  test(
    'five checklist completions per day earn tickets; extras stay recorded',
    () async {
      final prefs = SharedPreferencesAsync();
      final growth = GrowthStore(prefs);
      await growth.load();
      for (var index = 0; index < 7; index++) {
        await growth.addTask('작은 일 $index');
        await growth.toggleTask(growth.tasks.last);
      }
      final game = GameStore(prefs);
      await game.chooseStarter('pine_fox');
      expect(await game.creditRewards(growth.rewardCandidates), 10);
      expect(game.rewardGrants.where((grant) => grant.capped), hasLength(2));
      expect(game.rewardGrants, hasLength(7));

      final restored = GameStore(prefs);
      await restored.load();
      expect(await restored.creditRewards(growth.rewardCandidates), 0);
      expect(restored.trainingPasses, 10);
      await growth.addTask('여덟 번째');
      await growth.toggleTask(growth.tasks.last);
      expect(await restored.creditRewards(growth.rewardCandidates), 0);
      expect(
        restored.rewardGrants.where((grant) => grant.capped),
        hasLength(3),
      );
      expect(
        GameSnapshot.fromJson(restored.exportSnapshot()!.toJson()).rewardGrants,
        hasLength(8),
      );
    },
  );

  test('old completions cannot create a backlog of training tickets', () async {
    final game = GameStore(SharedPreferencesAsync());
    await game.chooseStarter('pine_fox');
    final oldDay = dayKey(DateTime.now().subtract(const Duration(days: 30)));
    final futureDay = dayKey(DateTime.now().add(const Duration(days: 1)));
    expect(
      await game.creditRewards([
        (
          sourceId: 'old-routine:$oldDay',
          kind: 'routine',
          trainingPasses: 2,
          experience: 0,
          activityDay: oldDay,
        ),
        (
          sourceId: 'old-goal:$oldDay',
          kind: 'more',
          trainingPasses: 2,
          experience: 20,
          activityDay: oldDay,
        ),
        (
          sourceId: 'future:$futureDay',
          kind: 'mini',
          trainingPasses: 1,
          experience: 10,
          activityDay: futureDay,
        ),
      ]),
      0,
    );
    expect(game.trainingPasses, 0);
    expect(game.rewardGrants, hasLength(2));
    expect(game.rewardGrants.every((grant) => grant.capped), isTrue);
    expect(game.rewardGrants.last.experience, 20);
  });

  testWidgets('today checklist shows only the training just paid', (
    tester,
  ) async {
    var openedGame = false;
    final prefs = SharedPreferencesAsync();
    final growth = GrowthStore(prefs);
    await growth.load();
    await growth.addTask('정리하기');
    final game = GameStore(prefs);
    await game.chooseStarter('pine_fox');
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: TodayChecklist(
              store: growth,
              onOpenGame: () => openedGame = true,
              onAwardTraining: (sourceId) => game.creditRewards(
                growth.rewardCandidates.where(
                  (candidate) => candidate.sourceId == sourceId,
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.ensureVisible(find.byType(Checkbox).first);
    await tester.pumpAndSettle();
    await tester.tap(find.byType(Checkbox).first);
    await tester.pumpAndSettle();
    expect(find.text('할 일 완료 · 훈련 +2'), findsOneWidget);
    expect(game.trainingPasses, 2);
    await tester.tap(find.text('게임으로'));
    await tester.pumpAndSettle();
    expect(openedGame, isTrue);
    expect(growth.guardianReaction, '오늘의 할 일을 해냈어요!');
    expect(tester.takeException(), isNull);
  });

  testWidgets('goal practice reports XP and paid training separately', (
    tester,
  ) async {
    var openedGame = false;
    final prefs = SharedPreferencesAsync();
    final growth = GrowthStore(prefs);
    await growth.load();
    await growth.addGoal(
      title: '읽기',
      mini: '한 쪽',
      more: '십 분',
      max: '한 장',
      path: '균형 있게',
      milestones: [],
    );
    final game = GameStore(prefs);
    await game.chooseStarter('pine_fox');
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: QuestCard(
              goal: growth.goals.single,
              store: growth,
              onOpenGame: () => openedGame = true,
              onAwardTraining: (sourceId) => game.creditRewards(
                growth.rewardCandidates.where(
                  (candidate) => candidate.sourceId == sourceId,
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('완료하기'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('MINI').first);
    await tester.pumpAndSettle();
    expect(find.text('실천 기록 · XP +10 · 훈련 +1'), findsOneWidget);
    expect(game.trainingPasses, 1);
    await tester.tap(find.text('게임으로'));
    await tester.pumpAndSettle();
    expect(openedGame, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('game shortcut fits after a task at large text size', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final prefs = SharedPreferencesAsync();
    final growth = GrowthStore(prefs);
    await growth.load();
    await growth.addTask('물 마시기');
    final game = GameStore(prefs);
    await game.chooseStarter('pine_fox');
    var openedGame = false;
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(2)),
          child: Scaffold(
            body: SingleChildScrollView(
              child: TodayChecklist(
                store: growth,
                onOpenGame: () => openedGame = true,
                onAwardTraining: (sourceId) => game.creditRewards(
                  growth.rewardCandidates.where(
                    (candidate) => candidate.sourceId == sourceId,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.ensureVisible(find.byType(Checkbox).first);
    await tester.pumpAndSettle();
    await tester.tap(find.byType(Checkbox).first);
    await tester.pumpAndSettle();
    expect(find.text('게임으로'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('게임으로'));
    expect(openedGame, isTrue);
  });

  testWidgets('goal reward shortcut fits at large text size', (tester) async {
    tester.view.physicalSize = const Size(320, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final prefs = SharedPreferencesAsync();
    final growth = GrowthStore(prefs);
    await growth.load();
    await growth.addGoal(
      title: '읽기',
      mini: '한 쪽',
      more: '십 분',
      max: '한 장',
      path: '균형 있게',
      milestones: [],
    );
    final game = GameStore(prefs);
    await game.chooseStarter('pine_fox');
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(2)),
          child: Scaffold(
            body: SingleChildScrollView(
              child: QuestCard(
                goal: growth.goals.single,
                store: growth,
                onOpenGame: () {},
                onAwardTraining: (sourceId) => game.creditRewards(
                  growth.rewardCandidates.where(
                    (candidate) => candidate.sourceId == sourceId,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.ensureVisible(find.text('완료하기'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('완료하기'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('MINI').first);
    await tester.tap(find.text('MINI').first);
    await tester.pumpAndSettle();
    expect(find.text('게임으로'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('hidden game feedback still credits training', (tester) async {
    final prefs = SharedPreferencesAsync();
    final growth = GrowthStore(prefs);
    await growth.load();
    await growth.setShowGameRewards(false);
    await growth.addTask('물 마시기');
    final game = GameStore(prefs);
    await game.chooseStarter('pine_fox');
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TodayChecklist(
            store: growth,
            onAwardTraining: (sourceId) => game.creditRewards(
              growth.rewardCandidates.where(
                (candidate) => candidate.sourceId == sourceId,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byType(Checkbox).first);
    await tester.pumpAndSettle();
    expect(game.trainingPasses, 2);
    expect(find.textContaining('훈련 +2'), findsNothing);
    final restored = GrowthStore(prefs);
    await restored.load();
    expect(restored.showGameRewards, isFalse);
  });
}
