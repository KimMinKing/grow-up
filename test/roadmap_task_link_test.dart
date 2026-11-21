import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:growup/daily_content_widgets.dart';
import 'package:growup/main.dart';
import 'package:growup/models/daily_content.dart';
import 'package:growup/models/growth_goal.dart';
import 'package:growup/state/growth_backup.dart';
import 'package:growup/state/growth_store.dart';
import 'package:growup/state/game_store.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<(GrowthStore, GrowthGoal)> makeStore() async {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    final store = GrowthStore(SharedPreferencesAsync());
    await store.load();
    await store.addGoal(
      title: '독서',
      mini: '책 펼치기',
      more: '10분 읽기',
      max: '30분 읽기',
      path: '꾸준히',
      milestones: ['첫 장 시작', '첫 권 마치기'],
      milestoneDetails: const [
        MilestoneDetail(method: '책상에 책 펼치기\n첫 문장 읽기'),
        MilestoneDetail(method: '마지막 장 읽기'),
      ],
    );
    return (store, store.goals.single);
  }

  test('one next action per goal/day shares its goal completion', () async {
    final (store, goal) = await makeStore();
    expect(await store.addRoadmapAction(goal, 1), isFalse);
    expect(await store.addRoadmapAction(goal, 0), isTrue);
    expect(await store.addRoadmapAction(goal, 0), isFalse);
    final task = store.tasks.single;
    expect(task.title, '책상에 책 펼치기');
    expect(task.goalId, goal.id);
    expect(task.roadmapLinked, isTrue);
    expect(task.scheduledDay, store.today);
    expect(store.rewardableTaskCompletionIds, isEmpty);

    await store.toggleTask(task);
    expect(task.completedDay, isNull);
    await store.complete(goal, 'MINI');
    expect(task.completedDay, store.today);
    expect(store.rewardableTaskCompletionIds, isEmpty);
    expect(store.experience, 10);
    final game = GameStore(SharedPreferencesAsync());
    await game.load();
    expect(
      await game.creditCompletedTasks(store.rewardableTaskCompletionIds),
      0,
    );
    expect(game.trainingPasses, 0);
    await store.undo(goal);
    expect(task.completedDay, isNull);

    await store.addTask('별도 할 일');
    await store.toggleTask(store.tasks.last);
    expect(store.rewardableTaskCompletionIds, [store.tasks.last.id]);
    expect(
      await game.creditCompletedTasks(store.rewardableTaskCompletionIds),
      2,
    );
    expect(game.trainingPasses, 2);
  });

  test('linked action survives backup and reconciles after reload', () async {
    final (store, goal) = await makeStore();
    await store.addRoadmapAction(goal, 0);
    await store.complete(goal, 'MORE');
    final backup = GrowthBackup.decode(store.createBackup().encode());
    expect(backup.tasks.single.roadmapLinked, isTrue);
    expect(backup.tasks.single.completedDay, store.today);
    final legacyTask = Map<String, dynamic>.from(backup.tasks.single.toJson())
      ..remove('roadmapLinked');
    expect(ChecklistItem.fromJson(legacyTask).roadmapLinked, isFalse);
    expect(
      () => ChecklistItem.fromJson(
        Map<String, dynamic>.from(backup.tasks.single.toJson())
          ..['goalId'] = null,
      ),
      throwsFormatException,
    );

    final restored = GrowthStore(SharedPreferencesAsync());
    await restored.load();
    expect(restored.tasks.single.roadmapLinked, isTrue);
    expect(restored.tasks.single.completedDay, restored.today);
    expect(restored.rewardableTaskCompletionIds, isEmpty);
    await restored.undo(restored.goals.single);
    expect(restored.tasks.single.completedDay, isNull);

    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    final imported = GrowthStore(SharedPreferencesAsync());
    await imported.load();
    await imported.importBackup(backup);
    expect(imported.tasks.single.roadmapLinked, isTrue);
    expect(imported.tasks.single.completedDay, imported.today);
    expect(imported.rewardableTaskCompletionIds, isEmpty);
  });

  test(
    'conflicting goal import keeps its linked action with archived copy',
    () async {
      final (store, goal) = await makeStore();
      final incoming = GrowthGoal.fromJson(goal.toJson())
        ..completions[store.today] = 'MINI';
      final linked = ChecklistItem(
        id: 'incoming-action',
        title: '책 펼치기',
        createdDay: store.today,
        scheduledDay: store.today,
        goalId: goal.id,
        roadmapLinked: true,
      );
      await store.importBackup(
        GrowthBackup(
          goals: [incoming],
          guardianName: '루온',
          darkTheme: false,
          tasks: [linked],
        ),
      );
      expect(store.archivedGoals, hasLength(1));
      expect(store.tasks.single.goalId, store.archivedGoals.single.id);
      expect(store.tasks.single.goalId, isNot(goal.id));
      expect(store.tasks.single.archived, isTrue);
      expect(store.tasks.single.completedDay, store.today);
    },
  );

  test('backup keeps only one linked action active per goal and day', () async {
    final (store, goal) = await makeStore();
    await store.addRoadmapAction(goal, 0);
    await store.importBackup(
      GrowthBackup(
        goals: const [],
        guardianName: '루온',
        darkTheme: false,
        tasks: [
          ChecklistItem(
            id: 'another-linked-action',
            title: '다른 기기에서 쓴 행동',
            createdDay: store.today,
            scheduledDay: store.today,
            goalId: goal.id,
            roadmapLinked: true,
          ),
        ],
      ),
    );
    expect(store.tasks.where((task) => !task.archived), hasLength(1));
    expect(store.tasks.where((task) => task.archived), hasLength(1));
    final original = store.tasks.firstWhere((task) => !task.archived);
    await store.importBackup(
      GrowthBackup(
        goals: const [],
        guardianName: '루온',
        darkTheme: false,
        tasks: [
          ChecklistItem(
            id: original.id,
            title: '같은 ID로 다른 내용',
            createdDay: store.today,
            scheduledDay: store.today,
            goalId: goal.id,
            roadmapLinked: true,
          ),
        ],
      ),
    );
    expect(store.tasks.where((task) => !task.archived), hasLength(1));
    expect(store.tasks.where((task) => task.archived), hasLength(2));
  });

  testWidgets(
    'roadmap action is recorded through the goal on a narrow screen',
    (tester) async {
      final (store, goal) = await makeStore();
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
            body: SingleChildScrollView(
              child: QuestCard(goal: goal, store: store, showPlan: true),
            ),
          ),
        ),
      );
      await tester.ensureVisible(find.textContaining('로드맵 0/2'));
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining('로드맵 0/2'));
      await tester.pumpAndSettle();
      final importButton = find.text('다음 단계 행동을 오늘 할 일로');
      await tester.scrollUntilVisible(importButton, 250);
      await tester.pumpAndSettle();
      await tester.tap(importButton);
      await tester.pumpAndSettle();
      expect(store.tasks.single.roadmapLinked, isTrue);
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
      await tester.pageBack();
      await tester.pumpAndSettle();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(child: TodayChecklist(store: store)),
          ),
        ),
      );
      final recordButton = find.text('목표 MINI로 실천 기록');
      await tester.ensureVisible(recordButton);
      await tester.pumpAndSettle();
      await tester.tap(recordButton);
      await tester.pumpAndSettle();
      expect(goal.completions[store.today], 'MINI');
      expect(store.tasks.single.completedDay, store.today);
      expect(tester.takeException(), isNull);
    },
  );
}
