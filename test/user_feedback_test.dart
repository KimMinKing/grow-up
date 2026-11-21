import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:growup/activity_calendar.dart';
import 'package:growup/daily_content_widgets.dart';
import 'package:growup/game_guide_page.dart';
import 'package:growup/main.dart';
import 'package:growup/models/daily_content.dart';
import 'package:growup/models/growth_goal.dart';
import 'package:growup/state/growth_backup.dart';
import 'package:growup/state/growth_store.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

void main() {
  void resetPrefs() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
  }

  test('practice intensity changes guardian XP and survives reload', () async {
    resetPrefs();
    final prefs = SharedPreferencesAsync();
    final store = GrowthStore(prefs);
    await store.load();
    await store.addGoal(
      title: 'Reading',
      mini: 'One page',
      more: 'Ten pages',
      max: 'A chapter',
      path: '균형 있게',
      milestones: [],
    );
    final goal = store.goals.single;
    goal.completions['2026-10-29'] = 'MINI';
    goal.completions['2026-10-30'] = 'MORE';
    goal.completions['2026-10-31'] = 'MAX';
    expect(store.experience, 60);
    expect(store.level, 2);
    expect(store.experienceInLevel, 0);
    goal.completions['2026-10-29'] = 'MAX';
    expect(store.experience, 80);
    expect(store.experienceInLevel, 20);
    await store.archiveGoal(goal);
    expect(store.experience, 80);
    final restored = GrowthStore(prefs);
    await restored.load();
    expect(restored.experience, 80);
    expect(restored.level, 2);
  });

  test('optional task time is validated and preserved by backup', () async {
    resetPrefs();
    final store = GrowthStore(SharedPreferencesAsync());
    await store.load();
    expect(await store.addTask('Meeting', scheduledTime: '24:00'), isFalse);
    expect(await store.addTask('Meeting', scheduledTime: '09:30'), isTrue);
    final task = store.tasks.single;
    expect(task.scheduledTime, '09:30');
    expect(
      await store.updateTask(task, 'Meeting later', scheduledTime: '17:05'),
      isTrue,
    );
    final backup = GrowthBackup.decode(store.createBackup().encode());
    expect(backup.tasks.single.scheduledTime, '17:05');
    resetPrefs();
    final target = GrowthStore(SharedPreferencesAsync());
    await target.load();
    await target.importBackup(backup);
    expect(target.tasks.single.scheduledTime, '17:05');
    expect(
      ChecklistItem.fromJson({
        'id': 'legacy',
        'title': 'Old task',
        'createdDay': store.today,
      }).scheduledTime,
      isNull,
    );
  });

  test(
    'pending tasks follow scheduled time while untimed tasks stay stable',
    () async {
      resetPrefs();
      final prefs = SharedPreferencesAsync();
      final store = GrowthStore(prefs);
      await store.load();
      await store.addTask('Untimed first');
      await store.addTask('Afternoon', scheduledTime: '15:30');
      await store.addTask('Morning', scheduledTime: '08:00');
      await store.addTask('Untimed second');
      await store.addTask('Same time', scheduledTime: '08:00');
      expect(store.pendingTasks.map((task) => task.title), [
        'Morning',
        'Same time',
        'Afternoon',
        'Untimed first',
        'Untimed second',
      ]);
      final restored = GrowthStore(prefs);
      await restored.load();
      expect(restored.pendingTasks.map((task) => task.title), [
        'Morning',
        'Same time',
        'Afternoon',
        'Untimed first',
        'Untimed second',
      ]);
    },
  );

  test('roadmap details follow edits, deletion, reload and backup', () async {
    resetPrefs();
    final prefs = SharedPreferencesAsync();
    final store = GrowthStore(prefs);
    await store.load();
    expect(
      await store.addGoal(
        title: 'Invalid',
        mini: 'One page',
        more: 'Ten pages',
        max: 'A chapter',
        path: '균형 있게',
        milestones: ['First book'],
        milestoneDetails: const [],
      ),
      isFalse,
    );
    await store.addGoal(
      title: 'Reading',
      mini: 'One page',
      more: 'Ten pages',
      max: 'A chapter',
      path: '균형 있게',
      milestones: ['First book', 'Second book'],
    );
    final goal = store.goals.single;
    expect(goal.milestoneDetails.length, 2);
    expect(
      await store.updateMilestone(
        goal,
        0,
        'First book',
        detail: const MilestoneDetail(
          targetDate: '2026-12-31',
          criteria: 'Write one sentence',
          method: 'Read at lunch',
          rewardIdea: 'Listen to an album',
        ),
      ),
      isTrue,
    );
    await store.addMilestone(
      goal,
      'Third book',
      detail: const MilestoneDetail(method: 'Read on weekends'),
    );
    await store.removeMilestone(goal, 1);
    expect(goal.milestones, ['First book', 'Third book']);
    expect(goal.milestoneDetails[1].method, 'Read on weekends');
    final restored = GrowthStore(prefs);
    await restored.load();
    expect(
      restored.goals.single.milestoneDetails.first.criteria,
      'Write one sentence',
    );
    final backup = GrowthBackup.decode(store.createBackup().encode());
    expect(backup.goals.single.milestoneDetails.first.targetDate, '2026-12-31');
    expect(
      backup.goals.single.milestoneDetails.first.rewardIdea,
      'Listen to an album',
    );
    final legacyJson = Map<String, dynamic>.from(goal.toJson())
      ..remove('milestoneDetails');
    final legacy = GrowthGoal.fromJson(legacyJson);
    expect(legacy.milestoneDetails.length, 2);
    expect(legacy.milestoneDetails.first.criteria, isEmpty);
    final mismatched = Map<String, dynamic>.from(goal.toJson())
      ..['milestoneDetails'] = <Object>[];
    expect(() => GrowthGoal.fromJson(mismatched), throwsFormatException);
    expect(
      () => MilestoneDetail.fromJson({'targetDate': '2026-99-01'}),
      throwsFormatException,
    );
    expect(
      () => MilestoneDetail.fromJson({
        'rewardIdea': List.filled(121, 'x').join(),
      }),
      throwsFormatException,
    );
  });

  testWidgets('roadmap editor saves completion criteria and method', (
    tester,
  ) async {
    resetPrefs();
    final store = GrowthStore(SharedPreferencesAsync());
    await store.load();
    await store.addGoal(
      title: 'Reading',
      mini: 'One page',
      more: 'Ten pages',
      max: 'A chapter',
      path: '균형 있게',
      milestones: [],
    );
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
          body: MilestoneEditor(goal: store.goals.single, store: store),
        ),
      ),
    );
    await tester.enterText(find.widgetWithText(TextField, '이정표'), 'First book');
    await tester.enterText(
      find.widgetWithText(TextField, '완료 기준 (선택)'),
      'Write a summary',
    );
    await tester.enterText(
      find.widgetWithText(TextField, '실천 방법 (선택)'),
      'Read after breakfast',
    );
    await tester.enterText(
      find.widgetWithText(TextField, '달성 후 나에게 줄 보상 (선택)'),
      'Listen to an album',
    );
    await tester.ensureVisible(find.text('저장'));
    await tester.tap(find.text('저장'));
    await tester.pumpAndSettle();
    expect(
      store.goals.single.milestoneDetails.single.criteria,
      'Write a summary',
    );
    expect(
      store.goals.single.milestoneDetails.single.method,
      'Read after breakfast',
    );
    expect(
      store.goals.single.milestoneDetails.single.rewardIdea,
      'Listen to an album',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('chosen self reward stays visible after milestone completion', (
    tester,
  ) async {
    resetPrefs();
    final store = GrowthStore(SharedPreferencesAsync());
    await store.load();
    await store.addGoal(
      title: 'Reading',
      mini: 'One page',
      more: 'Ten pages',
      max: 'A chapter',
      path: '균형 있게',
      milestones: ['First book'],
      milestoneDetails: const [
        MilestoneDetail(rewardIdea: 'Listen to an album'),
      ],
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: AnimatedBuilder(
              animation: store,
              builder: (context, _) => QuestCard(
                goal: store.goals.single,
                store: store,
                showPlan: true,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.scrollUntilVisible(find.textContaining('로드맵 0/1'), 300);
    await tester.tap(find.textContaining('로드맵 0/1'));
    await tester.pumpAndSettle();
    expect(find.text('달성하면 즐길 보상 · Listen to an album'), findsOneWidget);
    await tester.tap(
      find.byKey(ValueKey('milestone-${store.goals.single.id}-0')),
    );
    await tester.pumpAndSettle();
    expect(find.text('달성한 나에게 주는 보상 · Listen to an album'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'calendar lists completed tasks and notes without day selection',
    (tester) async {
      resetPrefs();
      final store = GrowthStore(SharedPreferencesAsync());
      await store.load();
      await store.addTask('Buy tea', scheduledTime: '16:00');
      await store.toggleTask(store.tasks.single);
      await store.addNote(store.today, 'Tea was good');
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(child: ActivityCalendar(store: store)),
          ),
        ),
      );
      expect(find.text('✓ Buy tea'), findsOneWidget);
      expect(find.text('✎ Tea was good'), findsOneWidget);
      expect(find.text('✓1 ✎'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('task time chooser fits a narrow screen with large text', (
    tester,
  ) async {
    resetPrefs();
    final store = GrowthStore(SharedPreferencesAsync());
    await store.load();
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
          body: SingleChildScrollView(child: TodayChecklist(store: store)),
        ),
      ),
    );
    await tester.tap(find.text('할 일 추가'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('시간 설정'));
    await tester.pumpAndSettle();
    expect(find.byType(DropdownButton<int>), findsNWidgets(2));
    expect(tester.takeException(), isNull);
    await tester.tap(find.widgetWithText(FilledButton, '설정'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '책 읽기');
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, '저장'));
    await tester.pumpAndSettle();
    expect(store.tasks.single.scheduledTime, matches(RegExp(r'^\d{2}:\d{2}$')));
    expect(tester.takeException(), isNull);
  });

  testWidgets('task reminder label stays readable in a narrow dialog', (
    tester,
  ) async {
    resetPrefs();
    final store = GrowthStore(SharedPreferencesAsync());
    await store.load();
    tester.view.physicalSize = const Size(300, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: TodayChecklist(store: store)),
      ),
    );
    await tester.tap(find.text('할 일 추가'));
    await tester.pumpAndSettle();
    final label = tester.renderObject<RenderParagraph>(find.text('할 일 알림'));
    expect(
      label.size.width,
      greaterThanOrEqualTo(label.getMaxIntrinsicWidth(double.infinity)),
    );
    expect(find.textContaining('날짜와 시간, 또는 반복과 시간'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('game guide scrolls on a narrow screen with large text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 700);
    tester.view.devicePixelRatio = 1;
    tester.binding.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(
      tester.binding.platformDispatcher.clearTextScaleFactorTestValue,
    );
    await tester.pumpWidget(const MaterialApp(home: GameGuidePage()));
    expect(tester.takeException(), isNull);
    await tester.scrollUntilVisible(find.text('7  발견과 뽑기'), 250);
    expect(tester.takeException(), isNull);
  });
}
