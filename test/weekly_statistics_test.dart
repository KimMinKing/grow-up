import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:growup/main.dart';
import 'package:growup/models/daily_content.dart';
import 'package:growup/models/growth_goal.dart';
import 'package:growup/state/growth_store.dart';
import 'package:growup/state/weekly_statistics.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('weekly totals use occurrence dates and omit linked actions', () {
    GrowthGoal goal(String id, Map<String, String> completions) => GrowthGoal(
      id: id,
      title: id,
      mini: '작게',
      more: '보통',
      max: '크게',
      path: '가볍게 시작',
      weeklyTarget: 2,
      milestones: [],
      createdAt: DateTime(2026, 10, 1),
      completions: completions,
    );
    final stats = WeeklyStatistics.calculate(
      week: DateTime(2026, 11, 5),
      goals: [
        goal('a', {
          '2026-10-30': 'MINI',
          '2026-11-03': 'MINI',
          '2026-11-05': 'MORE',
        }),
        goal('b', {'2026-11-04': 'MAX'}),
      ],
      tasks: [
        ChecklistItem(
          id: 'once',
          title: '일회성',
          createdDay: '2026-11-01',
          completedDay: '2026-11-02',
          movedOccurrences: {'2026-11-02': '2026-11-03'},
        ),
        ChecklistItem(
          id: 'repeat',
          title: '반복',
          createdDay: '2026-11-01',
          repeatPattern: 'daily',
          completedOccurrences: ['2026-11-03', '2026-11-04', '2026-11-09'],
          movedOccurrences: {'2026-11-07': '2026-11-08'},
        ),
        ChecklistItem(
          id: 'linked',
          title: '로드맵 행동',
          createdDay: '2026-11-03',
          scheduledDay: '2026-11-03',
          completedDay: '2026-11-03',
          goalId: 'a',
          roadmapLinked: true,
        ),
      ],
    );
    expect(stats.start, DateTime.utc(2026, 11, 2));
    expect(stats.oneOffDone, 1);
    expect(stats.repeatDone, 2);
    expect(stats.goalPractices, 3);
    expect(stats.postponed, 2);
    expect(stats.restartDays, ['2026-11-03']);
  });

  test('one-off postponement history persists after reload', () async {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    final prefs = SharedPreferencesAsync();
    final store = GrowthStore(prefs);
    await store.load();
    await store.addTask('일정 변경', scheduledDay: store.today);
    final task = store.tasks.single;
    final now = DateTime.now();
    final tomorrow = dayKey(DateTime(now.year, now.month, now.day + 1));
    expect(
      await store.updateTask(task, task.title, scheduledDay: tomorrow),
      isTrue,
    );
    expect(task.movedOccurrences[store.today], tomorrow);
    expect(
      store
          .weekTaskEntries(DateTime.now())
          .any((entry) => entry.day == store.today && entry.status == 'moved'),
      isTrue,
    );
    final restored = GrowthStore(prefs);
    await restored.load();
    expect(restored.tasks.single.movedOccurrences[store.today], tomorrow);
  });

  testWidgets('weekly panel fits a narrow large-text screen', (tester) async {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
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
          body: SingleChildScrollView(
            child: WeeklyStatisticsPanel(store: store),
          ),
        ),
      ),
    );
    expect(find.text('주간 기록'), findsOneWidget);
    await tester.tap(find.byTooltip('이전 주'));
    await tester.pumpAndSettle();
    expect(find.text('일회성 할 일'), findsOneWidget);
    expect(find.text('0개'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
