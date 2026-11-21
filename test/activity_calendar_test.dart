import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:growup/activity_calendar.dart';
import 'package:growup/main.dart';
import 'package:growup/state/growth_store.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

void main() {
  testWidgets('calendar records a missed practice on the selected date', (
    tester,
  ) async {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    final store = GrowthStore(SharedPreferencesAsync());
    await store.load();
    final yesterday = DateTime.now().subtract(const Duration(days: 1));
    await store.addGoal(
      title: '독서',
      mini: '2쪽',
      more: '15분',
      max: '40분',
      path: '균형 있게',
      startDate: dayKey(yesterday),
      milestones: [],
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(child: ActivityCalendar(store: store)),
        ),
      ),
    );
    if (yesterday.month != DateTime.now().month) {
      await tester.tap(find.byTooltip('이전 달'));
      await tester.pumpAndSettle();
    }
    await tester.tap(find.text('${yesterday.day}').first);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('이날 목표 실천 수정'));
    await tester.tap(find.text('이날 목표 실천 수정'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ListTile, '독서'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ListTile, 'MINI'));
    await tester.pumpAndSettle();
    expect(store.goals.single.completions[dayKey(yesterday)], 'MINI');
    expect(store.experience, 10);
    expect(tester.takeException(), isNull);
  });

  testWidgets('selected date filters month records and can return to all', (
    tester,
  ) async {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    final store = GrowthStore(SharedPreferencesAsync());
    await store.load();
    final today = DateTime.now();
    final yesterday = today.subtract(const Duration(days: 1));
    if (today.month != yesterday.month) return;
    await store.addNote(dayKey(today), '오늘 메모');
    await store.addNote(dayKey(yesterday), '어제 메모');
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(child: ActivityCalendar(store: store)),
        ),
      ),
    );
    expect(find.textContaining('어제 메모'), findsOneWidget);
    await tester.tap(find.text('${today.day}').first);
    await tester.pumpAndSettle();
    expect(find.textContaining('오늘 메모'), findsOneWidget);
    expect(find.textContaining('어제 메모'), findsNothing);
    await tester.tap(find.text('이번 달 전체'));
    await tester.pumpAndSettle();
    expect(find.textContaining('어제 메모'), findsOneWidget);
  });

  testWidgets('past month shows completed goal and its intensity', (
    tester,
  ) async {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    final store = GrowthStore(SharedPreferencesAsync());
    await store.load();
    await store.addGoal(
      title: '독서',
      mini: '2쪽',
      more: '15분',
      max: '40분',
      path: '균형 있게',
      milestones: [],
    );
    final lastMonth = DateTime(DateTime.now().year, DateTime.now().month, 0);
    store.goals.single.completions[dayKey(lastMonth)] = 'MORE';
    store.goals.single.completionActions[dayKey(lastMonth)] = '15분';

    tester.view.physicalSize = const Size(411, 915);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(child: ActivityCalendar(store: store)),
        ),
      ),
    );
    await tester.tap(find.byTooltip('이전 달'));
    await tester.pump();
    expect(find.text('${lastMonth.year}년 ${lastMonth.month}월'), findsOneWidget);
    expect(
      find.byKey(ValueKey('calendar-level-${dayKey(lastMonth)}-MORE')),
      findsOneWidget,
    );
    await tester.tap(find.text('${lastMonth.day}'));
    await tester.pump();
    expect(find.text('독서 · 15분'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'calendar distinguishes MINI MORE and MAX without opening a day',
    (tester) async {
      SharedPreferencesAsyncPlatform.instance =
          InMemorySharedPreferencesAsync.empty();
      final store = GrowthStore(SharedPreferencesAsync());
      await store.load();
      for (final level in ['MINI', 'MORE', 'MAX']) {
        await store.addGoal(
          title: '$level 목표',
          mini: '2분',
          more: '15분',
          max: '40분',
          path: '균형 있게',
          milestones: [],
        );
        store.goals.last.completions[store.today] = level;
      }
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(child: ActivityCalendar(store: store)),
          ),
        ),
      );
      for (final level in ['MINI', 'MORE', 'MAX']) {
        expect(
          find.byKey(ValueKey('calendar-level-${store.today}-$level')),
          findsOneWidget,
        );
        expect(find.text('$level 목표'), findsOneWidget);
      }
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('calendar fits narrow screens with larger text', (tester) async {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    final store = GrowthStore(SharedPreferencesAsync());
    await store.load();
    tester.view.physicalSize = const Size(320, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(1.3)),
          child: Scaffold(
            body: SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: ActivityCalendar(store: store),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byTooltip('이전 달'));
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('calendar keeps two digit days together at 200 percent text', (
    tester,
  ) async {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    final store = GrowthStore(SharedPreferencesAsync());
    await store.load();
    tester.view.physicalSize = const Size(300, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(2)),
          child: Scaffold(
            body: SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: ActivityCalendar(store: store),
              ),
            ),
          ),
        ),
      ),
    );
    final today = DateTime.now();
    expect(
      find.text('${today.year}.${today.month.toString().padLeft(2, '0')}'),
      findsOneWidget,
    );
    final day = tester.widget<Text>(find.text('10'));
    expect(day.textScaler!.scale(16), closeTo(19.2, .01));
    expect(tester.takeException(), isNull);
  });

  testWidgets('calendar separates planned and completed tasks with actions', (
    tester,
  ) async {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    final store = GrowthStore(SharedPreferencesAsync());
    await store.load();
    await store.addTask(
      '오늘 약속',
      scheduledDay: store.today,
      scheduledTime: '09:00',
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
          body: SingleChildScrollView(child: ActivityCalendar(store: store)),
        ),
      ),
    );
    final today = DateTime.now();
    expect(find.bySemanticsLabel(RegExp('예정된 할 일 1개')), findsOneWidget);
    await tester.tap(find.text('${today.day}').first);
    await tester.pumpAndSettle();
    expect(find.text('이날 예정한 할 일'), findsOneWidget);
    expect(find.text('오늘 약속'), findsOneWidget);
    await tester.ensureVisible(find.text('오늘 완료'));
    await tester.tap(find.text('오늘 완료'));
    await tester.pumpAndSettle();
    expect(store.tasks.single.completedDay, store.today);
    expect(find.textContaining('이날 완료'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('future month opens a planned task', (tester) async {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    final store = GrowthStore(SharedPreferencesAsync());
    await store.load();
    final future = DateTime(DateTime.now().year, DateTime.now().month + 1, 1);
    await store.addTask('다음 달 준비', scheduledDay: dayKey(future));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(child: ActivityCalendar(store: store)),
        ),
      ),
    );
    await tester.tap(find.byTooltip('다음 달'));
    await tester.pumpAndSettle();
    expect(find.text('${future.year}년 ${future.month}월'), findsOneWidget);
    await tester.tap(find.text('1').first);
    await tester.pumpAndSettle();
    expect(find.text('다음 달 준비'), findsOneWidget);
    expect(find.text('미루기'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('calendar postpones one task and one repeat occurrence', (
    tester,
  ) async {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    final store = GrowthStore(SharedPreferencesAsync());
    await store.load();
    await store.addTask('일회 약속', scheduledDay: store.today);
    await store.addTask('매일 약속', repeatPattern: 'daily');
    final tomorrow = dayKey(DateTime.now().add(const Duration(days: 1)));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(child: ActivityCalendar(store: store)),
        ),
      ),
    );
    await tester.tap(find.text('${DateTime.now().day}').first);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('미루기').first);
    await tester.tap(find.text('미루기').first);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('날짜 선택'));
    await tester.tap(find.text('날짜 선택'));
    await tester.pumpAndSettle();
    expect(store.tasks.first.scheduledDay, tomorrow);
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('미루기').first);
    await tester.tap(find.text('미루기').first);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('날짜 선택'));
    await tester.tap(find.text('날짜 선택'));
    await tester.pumpAndSettle();
    expect(store.tasks.last.movedOccurrences[store.today], tomorrow);
    expect(store.tasks.last.occursOn(store.today), isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('weekly pulse fits a narrow home screen', (tester) async {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    final store = GrowthStore(SharedPreferencesAsync());
    await store.load();
    await store.addGoal(
      title: '독서',
      mini: '2쪽',
      more: '15분',
      max: '40분',
      path: '균형 있게',
      milestones: [],
    );
    tester.view.physicalSize = const Size(320, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(1.3)),
          child: Scaffold(
            body: Center(child: WeeklyPulse(store: store)),
          ),
        ),
      ),
    );
    expect(find.text('이번 주의 걸음'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
