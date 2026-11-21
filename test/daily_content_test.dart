import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:growup/daily_content_widgets.dart';
import 'package:growup/activity_calendar.dart';
import 'package:growup/main.dart';
import 'package:growup/models/daily_content.dart';
import 'package:growup/state/growth_backup.dart';
import 'package:growup/state/growth_store.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('next recurrence survives more than a month of exceptions', () {
    final start = DateTime.utc(2026, 1, 1);
    final task = ChecklistItem(
      id: 'long-break',
      title: '다시 시작',
      createdDay: '2026-01-01',
      repeatPattern: 'daily',
      skippedOccurrences: [
        for (var i = 1; i <= 45; i++) dayKey(start.add(Duration(days: i))),
      ],
    );
    expect(task.nextOccurrenceAfter('2026-01-01'), '2026-02-16');
    task.movedOccurrences['2026-02-17'] = '2026-02-10';
    // A moved target that is explicitly skipped stays skipped.
    expect(task.nextOccurrenceAfter('2026-01-01'), '2026-02-16');
    task.skippedOccurrences.remove('2026-02-10');
    expect(task.nextOccurrenceAfter('2026-01-01'), '2026-02-10');
    final weekly = ChecklistItem(
      id: 'weekly-break',
      title: '매주 월요일',
      createdDay: '2026-01-01',
      repeatPattern: 'weekly',
      repeatWeekdays: [1],
      skippedOccurrences: [
        '2026-01-05',
        '2026-01-12',
        '2026-01-19',
        '2026-01-26',
        '2026-02-02',
      ],
    );
    expect(weekly.nextOccurrenceAfter('2026-01-01'), '2026-02-09');
    final interval = ChecklistItem(
      id: 'interval-break',
      title: '30일마다',
      createdDay: '2026-01-01',
      repeatPattern: 'interval',
      repeatIntervalDays: 30,
      skippedOccurrences: ['2026-01-31'],
    );
    expect(interval.nextOccurrenceAfter('2026-01-01'), '2026-03-02');
  });

  void resetPrefs() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
  }

  test('copy creates fresh unchecked steps and never copies reward history or reminders', () async {
    resetPrefs();
    final prefs = SharedPreferencesAsync();
    final store = GrowthStore(prefs);
    await store.load();
    await store.addTask(
      '주간 정리',
      scheduledDay: store.today,
      scheduledTime: '09:00',
      repeatPattern: 'daily',
      priority: 'high',
      tags: ['정리'],
      reminderEnabled: true,
    );
    final source = store.tasks.single;
    await store.addTaskStep(source, '책상');
    await store.toggleTaskStep(source, source.steps.single);
    await store.toggleTask(source);
    source.skippedOccurrences.add('2026-01-01');
    source.movedOccurrences['2026-01-02'] = '2026-01-03';
    await store.setTaskArchived(source, true);
    expect(await store.copyTask(source), isTrue);
    final copy = store.tasks.last;
    expect(copy.id, isNot(source.id));
    expect(copy.title, source.title);
    expect(copy.tags, ['정리']);
    expect(copy.priority, 'high');
    expect(copy.reminderEnabled, isFalse);
    expect(copy.archived, isFalse);
    expect(copy.completedOccurrences, isEmpty);
    expect(copy.skippedOccurrences, isEmpty);
    expect(copy.movedOccurrences, isEmpty);
    expect(copy.steps.single.id, isNot(source.steps.single.id));
    expect(
      copy.steps.single.isCompletedOn(store.today, repeated: true),
      isFalse,
    );
    copy.tags.add('복사본');
    expect(source.tags, ['정리']);
    final restored = GrowthStore(prefs);
    await restored.load();
    expect(restored.tasks.last.steps.single.title, '책상');
    expect(restored.tasks.last.reminderEnabled, isFalse);
  });

  test(
    'unfinished task carries into today; completion and note survive reload',
    () async {
      resetPrefs();
      final prefs = SharedPreferencesAsync();
      final store = GrowthStore(prefs);
      await store.load();
      final yesterday = dayKey(
        DateTime.now().subtract(const Duration(days: 1)),
      );
      await store.importBackup(
        GrowthBackup(
          goals: const [],
          guardianName: '루온',
          darkTheme: false,
          tasks: [
            ChecklistItem(
              id: 'old-task',
              title: '어제의 일',
              createdDay: yesterday,
            ),
          ],
        ),
      );
      expect(store.pendingTasks.single.title, '어제의 일');
      final task = store.pendingTasks.single;
      await store.toggleTask(task);
      expect(task.completedDay, store.today);
      expect(store.pendingTasks, isEmpty);
      await store.addNote(store.today, '오늘 한 줄');
      final restored = GrowthStore(prefs);
      await restored.load();
      expect(restored.completedTasks.single.title, '어제의 일');
      expect(restored.notes.single.text, '오늘 한 줄');
      await restored.toggleTask(restored.tasks.single);
      expect(restored.pendingTasks.single.title, '어제의 일');
    },
  );

  test('tasks and notes can be edited and deleted', () async {
    resetPrefs();
    final store = GrowthStore(SharedPreferencesAsync());
    await store.load();
    expect(await store.addTask('  우유 사기  '), isTrue);
    final task = store.tasks.single;
    expect(await store.updateTask(task, '물 사기'), isTrue);
    expect(task.title, '물 사기');
    expect(await store.addNote(store.today, ' 첫 메모 '), isTrue);
    final note = store.notes.single;
    expect(await store.updateNote(note, store.today, '고친 메모'), isTrue);
    expect(note.text, '고친 메모');
    await store.deleteTask(task);
    await store.deleteNote(note);
    expect(store.tasks, isEmpty);
    expect(store.notes, isEmpty);
  });

  test(
    'scheduled tasks separate overdue, today, upcoming, and undated',
    () async {
      resetPrefs();
      final prefs = SharedPreferencesAsync();
      final store = GrowthStore(prefs);
      await store.load();
      final yesterday = dayKey(
        DateTime.now().subtract(const Duration(days: 1)),
      );
      final tomorrow = dayKey(DateTime.now().add(const Duration(days: 1)));
      expect(
        await store.addTask('잘못된 날짜', scheduledDay: '2026-02-30'),
        isFalse,
      );
      await store.addTask('날짜 미정');
      await store.addTask(
        '오늘',
        scheduledDay: store.today,
        scheduledTime: '08:00',
      );
      await store.addTask('내일', scheduledDay: tomorrow, scheduledTime: '09:00');
      await store.addTask('지난 일', scheduledDay: yesterday);
      expect(store.overdueTasks.map((task) => task.title), ['지난 일']);
      expect(store.dueTodayTasks.map((task) => task.title), ['오늘']);
      expect(store.undatedTasks.map((task) => task.title), ['날짜 미정']);
      expect(store.upcomingTasks.map((task) => task.title), ['내일']);
      expect(store.pendingTasks.any((task) => task.title == '내일'), isFalse);

      final upcoming = store.upcomingTasks.single;
      expect(
        await store.updateTask(
          upcoming,
          upcoming.title,
          scheduledDay: store.today,
        ),
        isTrue,
      );
      expect(store.dueTodayTasks.map((task) => task.title), ['오늘', '내일']);
      expect(store.upcomingTasks, isEmpty);

      final backup = GrowthBackup.decode(store.createBackup().encode());
      expect(
        backup.tasks.firstWhere((task) => task.title == '지난 일').scheduledDay,
        yesterday,
      );
      final restored = GrowthStore(prefs);
      await restored.load();
      expect(restored.dueTodayTasks.length, 2);
      final invalid =
          jsonDecode(store.createBackup().encode()) as Map<String, dynamic>;
      (invalid['tasks'] as List).first['scheduledDay'] = 'bad-day';
      expect(
        () => GrowthBackup.decode(jsonEncode(invalid)),
        throwsFormatException,
      );
    },
  );

  test(
    'task steps and archive survive reload without extra task rewards',
    () async {
      resetPrefs();
      final prefs = SharedPreferencesAsync();
      final store = GrowthStore(prefs);
      await store.load();
      await store.addTask('방 정리');
      final task = store.tasks.single;
      expect(await store.addTaskStep(task, '책상 치우기'), isTrue);
      expect(await store.addTaskStep(task, '바닥 쓸기'), isTrue);
      expect(store.tasks, hasLength(1));
      await store.toggleTaskStep(task, task.steps.first);
      expect(task.steps.first.completed, isTrue);
      expect(task.completedDay, isNull);
      await store.setTaskArchived(task, true);
      expect(store.pendingTasks, isEmpty);
      expect(store.archivedTasks, hasLength(1));

      final backup = GrowthBackup.decode(store.createBackup().encode());
      expect(backup.tasks.single.steps, hasLength(2));
      expect(backup.tasks.single.archived, isTrue);
      final restored = GrowthStore(prefs);
      await restored.load();
      expect(restored.archivedTasks.single.steps.first.completed, isTrue);
      await restored.setTaskArchived(restored.tasks.single, false);
      expect(restored.pendingTasks, hasLength(1));
      await restored.toggleTask(restored.tasks.single);
      expect(restored.completedTasks, hasLength(1));

      final invalid = jsonDecode(backup.encode()) as Map<String, dynamic>;
      (invalid['tasks'] as List).first['steps'] = [
        {'id': 'same', 'title': 'A', 'completed': false},
        {'id': 'same', 'title': 'B', 'completed': false},
      ];
      expect(
        () => GrowthBackup.decode(jsonEncode(invalid)),
        throwsFormatException,
      );
    },
  );

  test('repeat schedules keep separate dated completion records', () async {
    resetPrefs();
    final prefs = SharedPreferencesAsync();
    final store = GrowthStore(prefs);
    await store.load();
    final yesterday = dayKey(DateTime.now().subtract(const Duration(days: 1)));
    final tomorrow = dayKey(DateTime.now().add(const Duration(days: 1)));
    await store.addTask(
      '매일 산책',
      scheduledDay: yesterday,
      repeatPattern: 'daily',
    );
    final daily = store.tasks.single;
    expect(daily.occursOn(yesterday), isTrue);
    expect(daily.occursOn(store.today), isTrue);
    expect(store.dueTodayTasks, contains(daily));
    await store.addTaskStep(daily, '운동화 신기');
    await store.toggleTaskStep(daily, daily.steps.single);
    expect(
      daily.steps.single.isCompletedOn(store.today, repeated: true),
      isTrue,
    );
    expect(daily.steps.single.isCompletedOn(tomorrow, repeated: true), isFalse);
    await store.toggleTask(daily);
    expect(daily.completedOccurrences, [store.today]);
    expect(store.dueTodayTasks, isEmpty);
    expect(daily.wasCompletedOn(yesterday), isFalse);
    expect(daily.occursOn(tomorrow), isTrue);
    final reloaded = GrowthStore(prefs);
    await reloaded.load();
    expect(reloaded.tasks.single.completedOccurrences, [store.today]);
    expect(reloaded.tasks.single.steps.single.completedDays, [store.today]);
    expect(reloaded.dueTodayTasks, isEmpty);
    await reloaded.toggleTask(reloaded.tasks.single);
    expect(reloaded.dueTodayTasks, hasLength(1));

    final todayWeekday = DateTime.now().weekday;
    await store.addTask(
      '매주 이 요일',
      repeatPattern: 'weekly',
      repeatWeekdays: [todayWeekday],
    );
    final weekly = store.tasks.last;
    expect(weekly.occursOn(store.today), isTrue);
    expect(weekly.occursOn(tomorrow), isFalse);
    await store.addTask(
      '사흘마다',
      scheduledDay: yesterday,
      repeatPattern: 'interval',
      repeatIntervalDays: 3,
    );
    final interval = store.tasks.last;
    expect(interval.occursOn(yesterday), isTrue);
    expect(interval.occursOn(store.today), isFalse);
    expect(
      interval.occursOn(dayKey(DateTime.now().add(const Duration(days: 2)))),
      isTrue,
    );

    await store.updateTask(daily, daily.title, repeatPattern: 'none');
    expect(daily.completedDay, store.today);
    expect(daily.completedOccurrences, [store.today]);
    expect(store.pendingTasks, isNot(contains(daily)));

    final backup = GrowthBackup.decode(store.createBackup().encode());
    expect(backup.tasks.first.repeatPattern, 'none');
    final invalid = jsonDecode(backup.encode()) as Map<String, dynamic>;
    (invalid['tasks'] as List).first['completedOccurrences'] = ['bad'];
    expect(
      () => GrowthBackup.decode(jsonEncode(invalid)),
      throwsFormatException,
    );
  });

  test('one repeat occurrence can be skipped, moved, and restored', () async {
    resetPrefs();
    final prefs = SharedPreferencesAsync();
    final store = GrowthStore(prefs);
    await store.load();
    await store.addTask('매일 읽기', repeatPattern: 'daily');
    final task = store.tasks.single;
    final tomorrow = dayKey(DateTime.now().add(const Duration(days: 1)));
    final nextDay = dayKey(DateTime.now().add(const Duration(days: 2)));

    expect(await store.skipTaskOccurrence(task, store.today), isTrue);
    expect(task.occursOn(store.today), isFalse);
    expect(task.wasSkippedOn(store.today), isTrue);
    expect(task.occursOn(tomorrow), isTrue);
    expect(store.dueTodayTasks, isEmpty);
    await store.restoreTaskOccurrence(task, store.today);
    expect(task.occursOn(store.today), isTrue);

    expect(await store.moveTaskOccurrence(task, store.today, tomorrow), isTrue);
    expect(task.occursOn(store.today), isFalse);
    expect(task.occursOn(tomorrow), isTrue);
    expect(task.occursOn(nextDay), isTrue);
    expect(task.movedOccurrences[store.today], tomorrow);
    expect(await store.skipTaskOccurrence(task, store.today), isFalse);
    final futureRoutine = ChecklistItem(
      id: 'future',
      title: '미래 시작',
      createdDay: store.today,
      scheduledDay: nextDay,
      repeatPattern: 'weekly',
      repeatWeekdays: [DateTime.parse(nextDay).weekday],
      movedOccurrences: {nextDay: store.today},
    );
    expect(futureRoutine.occursOn(store.today), isTrue);
    final farStart = dayKey(DateTime.now().add(const Duration(days: 90)));
    final farRoutine = ChecklistItem(
      id: 'far-future',
      title: '먼 훗날',
      createdDay: store.today,
      scheduledDay: farStart,
      repeatPattern: 'daily',
    );
    expect(farRoutine.nextOccurrenceAfter(store.today), farStart);
    final reloaded = GrowthStore(prefs);
    await reloaded.load();
    expect(reloaded.tasks.single.movedOccurrences[store.today], tomorrow);
    final backup = GrowthBackup.decode(store.createBackup().encode());
    expect(backup.tasks.single.movedOccurrences[store.today], tomorrow);
    final invalid = jsonDecode(backup.encode()) as Map<String, dynamic>;
    (invalid['tasks'] as List).first['movedOccurrences'] = {
      store.today: 'not-a-date',
    };
    expect(
      () => GrowthBackup.decode(jsonEncode(invalid)),
      throwsFormatException,
    );
    await store.restoreTaskOccurrence(task, store.today);
    expect(task.occursOn(store.today), isTrue);
    expect(task.movedOccurrences, isEmpty);
  });

  test('task priority, tags, and goal link survive edits and backup', () async {
    resetPrefs();
    final prefs = SharedPreferencesAsync();
    final store = GrowthStore(prefs);
    await store.load();
    await store.addGoal(
      title: '독서',
      mini: '한 쪽',
      more: '10분',
      max: '30분',
      path: '균형 있게',
      milestones: ['첫 책 끝내기'],
    );
    final goalId = store.goals.single.id;
    expect(
      await store.addTask(
        '책 읽기',
        priority: 'high',
        tags: ['공부', '저녁'],
        goalId: goalId,
      ),
      isTrue,
    );
    final task = store.tasks.single;
    expect(task.goalId, goalId);
    expect(task.tags, ['공부', '저녁']);
    expect(
      await store.updateTask(
        task,
        '책 읽기',
        priority: 'low',
        tags: ['취미'],
        goalId: null,
      ),
      isTrue,
    );
    expect(task.goalId, isNull);
    expect(task.priority, 'low');
    expect(
      await store.updateTask(
        task,
        '책 읽기',
        priority: 'high',
        tags: ['공부'],
        goalId: goalId,
      ),
      isTrue,
    );
    await store.updateTask(task, task.title, scheduledDay: store.today);
    expect(task.goalId, goalId);
    expect(await store.addTask('잘못된 태그', tags: ['중복', '중복']), isFalse);
    final restored = GrowthStore(prefs);
    await restored.load();
    expect(restored.tasks.single.goalId, goalId);
    expect(restored.tasks.single.tags, ['공부']);
    final backup = GrowthBackup.decode(store.createBackup().encode());
    expect(backup.tasks.single.priority, 'high');
    final old = task.toJson()
      ..remove('priority')
      ..remove('tags')
      ..remove('goalId');
    expect(ChecklistItem.fromJson(old).priority, 'normal');
    expect(ChecklistItem.fromJson(old).tags, isEmpty);
    final invalid = task.toJson()..['tags'] = ['a', 'A'];
    expect(() => ChecklistItem.fromJson(invalid), throwsFormatException);
  });

  test(
    'week view orders scheduled times and separates repeat states',
    () async {
      resetPrefs();
      final store = GrowthStore(SharedPreferencesAsync());
      await store.load();
      await store.addTask(
        '저녁 일',
        scheduledDay: store.today,
        scheduledTime: '18:00',
      );
      await store.addTask(
        '오전 일',
        scheduledDay: store.today,
        scheduledTime: '09:00',
      );
      await store.addTask('매일 일', repeatPattern: 'daily');
      await store.addTask('날짜 없는 일');
      final todayEntries = store
          .weekTaskEntries(DateTime.now())
          .where((entry) => entry.day == store.today)
          .toList();
      expect(todayEntries.map((entry) => entry.task.title), [
        '오전 일',
        '저녁 일',
        '매일 일',
      ]);
      final repeat = store.tasks.firstWhere((task) => task.title == '매일 일');
      await store.toggleTask(repeat);
      expect(
        store
            .weekTaskEntries(DateTime.now())
            .firstWhere(
              (entry) => entry.task == repeat && entry.day == store.today,
            )
            .status,
        'done',
      );
      await store.toggleTask(repeat);
      await store.skipTaskOccurrence(repeat, store.today);
      expect(
        store
            .weekTaskEntries(DateTime.now())
            .firstWhere(
              (entry) => entry.task == repeat && entry.day == store.today,
            )
            .status,
        'skipped',
      );
    },
  );

  test('backup includes daily content and accepts old version', () async {
    resetPrefs();
    final store = GrowthStore(SharedPreferencesAsync());
    await store.load();
    await store.addTask('약속 확인');
    await store.addNote(store.today, '기록');
    final encoded = store.createBackup().encode();
    final backup = GrowthBackup.decode(encoded);
    expect(backup.tasks.single.title, '약속 확인');
    expect(backup.notes.single.text, '기록');
    resetPrefs();
    final target = GrowthStore(SharedPreferencesAsync());
    await target.load();
    final first = await target.importBackup(backup);
    expect(first.tasksAdded, 1);
    expect(first.notesAdded, 1);
    final again = await target.importBackup(backup);
    expect(again.tasksAdded, 0);
    expect(again.notesAdded, 0);
    final conflict = await target.importBackup(
      GrowthBackup(
        goals: const [],
        guardianName: '루온',
        darkTheme: false,
        tasks: [
          ChecklistItem(
            id: backup.tasks.single.id,
            title: '다른 할 일',
            createdDay: store.today,
          ),
        ],
        notes: [
          DailyNote(
            id: backup.notes.single.id,
            day: store.today,
            text: '다른 메모',
          ),
        ],
      ),
    );
    expect(conflict.tasksAdded, 1);
    expect(conflict.notesAdded, 1);
    expect(target.tasks.map((task) => task.title).toSet(), {'약속 확인', '다른 할 일'});
    expect(target.notes.map((note) => note.text).toSet(), {'기록', '다른 메모'});
    final old = Map<String, dynamic>.from(jsonDecode(encoded) as Map)
      ..['version'] = 1
      ..remove('tasks')
      ..remove('notes');
    final legacy = GrowthBackup.decode(jsonEncode(old));
    expect(legacy.tasks, isEmpty);
    expect(legacy.notes, isEmpty);
    old['version'] = 2;
    expect(() => GrowthBackup.decode(jsonEncode(old)), throwsFormatException);
  });

  testWidgets('today checklist adds and completes a task', (tester) async {
    resetPrefs();
    final store = GrowthStore(SharedPreferencesAsync());
    await store.load();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: TodayChecklist(store: store)),
      ),
    );
    await tester.tap(find.text('할 일 추가'));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, '저장'))
          .onPressed,
      isNull,
    );
    await tester.enterText(find.byType(TextField), '산책하기');
    await tester.pump();
    await tester.tap(find.text('저장'));
    await tester.pumpAndSettle();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: TodayChecklist(store: store)),
      ),
    );
    expect(find.text('산책하기'), findsOneWidget);
    await tester.tap(find.byType(Checkbox));
    await tester.pumpAndSettle();
    expect(store.completedTasks.single.title, '산책하기');
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: TodayChecklist(store: store)),
      ),
    );
    expect(find.text('오늘 완료 1개'), findsOneWidget);
    expect(find.text('산책하기'), findsNothing);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: DailyNotesPanel(store: store)),
      ),
    );
    await tester.tap(find.byTooltip('완료한 할 일 메뉴'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('완료 취소'));
    await tester.pumpAndSettle();
    expect(store.pendingTasks.single.title, '산책하기');
    expect(tester.takeException(), isNull);
  });

  testWidgets('task date picker saves a day on a narrow large-text screen', (
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
    await tester.enterText(find.byType(TextField).first, '날짜 있는 일');
    await tester.tap(find.text('날짜 설정'));
    await tester.pumpAndSettle();
    expect(find.text('할 일 예정 날짜'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.ensureVisible(find.text('날짜 선택'));
    await tester.tap(find.text('날짜 선택'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '저장'));
    await tester.pumpAndSettle();
    expect(store.tasks.single.scheduledDay, store.today);
    expect(tester.takeException(), isNull);
  });

  testWidgets('task save stays reachable above an open keyboard', (
    tester,
  ) async {
    resetPrefs();
    final store = GrowthStore(SharedPreferencesAsync());
    await store.load();
    tester.view.physicalSize = const Size(320, 700);
    tester.view.devicePixelRatio = 1;
    tester.view.viewInsets = const FakeViewPadding(bottom: 260);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetViewInsets);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(child: TodayChecklist(store: store)),
        ),
      ),
    );
    await tester.tap(find.text('할 일 추가'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, '책 2쪽 읽기');
    await tester.pumpAndSettle();
    final save = find.widgetWithText(FilledButton, '저장');
    expect(tester.getBottomLeft(save).dy, lessThan(440));
    await tester.tap(save);
    await tester.pumpAndSettle();
    expect(store.tasks.single.title, '책 2쪽 읽기');
    expect(tester.takeException(), isNull);
  });

  testWidgets('task menu splits a task and restores it from archive', (
    tester,
  ) async {
    resetPrefs();
    final store = GrowthStore(SharedPreferencesAsync());
    await store.load();
    await store.addTask('방 정리');
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: AnimatedBuilder(
              animation: store,
              builder: (context, _) => TodayChecklist(store: store),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byTooltip('할 일 메뉴'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('작게 나누기'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '책상 치우기');
    await tester.pump();
    await tester.tap(find.text('저장'));
    await tester.pumpAndSettle();
    expect(store.tasks.single.steps.single.title, '책상 치우기');
    expect(store.tasks.single.completedDay, isNull);
    await tester.tap(find.byTooltip('할 일 메뉴'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('보관'));
    await tester.pumpAndSettle();
    expect(store.archivedTasks, hasLength(1));
    await tester.tap(find.text('보관한 일 · 1개'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('할 일 메뉴'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('다시 꺼내기'));
    await tester.pumpAndSettle();
    expect(store.pendingTasks, hasLength(1));
    expect(tester.takeException(), isNull);
  });

  testWidgets('daily repeat is selectable with large text', (tester) async {
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
    await tester.enterText(find.byType(TextField).first, '매일 물 마시기');
    await tester.pump();
    await tester.ensureVisible(find.text('반복 안 함'));
    await tester.tap(find.text('반복 안 함'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('매일').last);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '저장'));
    await tester.pumpAndSettle();
    expect(store.tasks.single.repeatPattern, 'daily');
    expect(store.dueTodayTasks, hasLength(1));
    expect(tester.takeException(), isNull);
  });

  testWidgets('weekly repeat day chips fit a narrow large-text dialog', (
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
    await tester.enterText(find.byType(TextField).first, '요일 독서');
    await tester.ensureVisible(find.text('반복 안 함'));
    await tester.tap(find.text('반복 안 함'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('선택 요일·매주').last);
    await tester.pumpAndSettle();
    final otherDay = DateTime.now().weekday % 7 + 1;
    final label = const ['월', '화', '수', '목', '금', '토', '일'][otherDay - 1];
    await tester.ensureVisible(find.widgetWithText(FilterChip, label));
    await tester.tap(find.widgetWithText(FilterChip, label));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.widgetWithText(FilledButton, '저장'));
    await tester.tap(find.widgetWithText(FilledButton, '저장'));
    await tester.pumpAndSettle();
    expect(store.tasks.single.repeatPattern, 'weekly');
    expect(store.tasks.single.repeatWeekdays, contains(otherDay));
    expect(tester.takeException(), isNull);
  });

  testWidgets('task categories link a goal on a narrow screen', (tester) async {
    resetPrefs();
    final store = GrowthStore(SharedPreferencesAsync());
    await store.load();
    await store.addGoal(
      title: '독서 목표',
      mini: '한 쪽',
      more: '10분',
      max: '30분',
      path: '균형 있게',
      milestones: ['첫 책'],
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
          body: SingleChildScrollView(child: TodayChecklist(store: store)),
        ),
      ),
    );
    await tester.tap(find.text('할 일 추가'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, '오늘 책 읽기');
    await tester.ensureVisible(find.text('중요도·태그·목표'));
    await tester.tap(find.text('중요도·태그·목표'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const ValueKey('task-priority')));
    await tester.tap(find.byKey(const ValueKey('task-priority')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('높음').last);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, '공부, 저녁');
    await tester.ensureVisible(find.byKey(const ValueKey('task-goal')));
    await tester.tap(find.byKey(const ValueKey('task-goal')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('독서 목표').last);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.widgetWithText(FilledButton, '저장'));
    await tester.tap(find.widgetWithText(FilledButton, '저장'));
    await tester.pumpAndSettle();
    expect(store.tasks.single.priority, 'high');
    expect(store.tasks.single.tags, ['공부', '저녁']);
    expect(store.tasks.single.goalId, store.goals.single.id);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: GoalLinkedTasks(store: store, goalId: store.goals.single.id),
        ),
      ),
    );
    expect(find.text('오늘 책 읽기'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('linked tasks appear in roadmap and goal history', (
    tester,
  ) async {
    resetPrefs();
    final store = GrowthStore(SharedPreferencesAsync());
    await store.load();
    await store.addGoal(
      title: '독서 목표',
      mini: '한 쪽',
      more: '10분',
      max: '30분',
      path: '균형 있게',
      milestones: ['첫 책'],
    );
    final goal = store.goals.single;
    await store.addTask('독서 준비', goalId: goal.id, tags: ['공부']);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: QuestCard(goal: goal, store: store, showPlan: true),
          ),
        ),
      ),
    );
    await tester.tap(find.textContaining('로드맵 0/1'));
    await tester.pumpAndSettle();
    expect(find.text('연결된 할 일 · 1개'), findsOneWidget);
    expect(find.text('독서 준비'), findsOneWidget);
    await tester.pumpWidget(
      MaterialApp(
        home: GoalHistoryPage(goal: goal, store: store),
      ),
    );
    await tester.scrollUntilVisible(
      find.text('연결된 할 일 · 1개'),
      500,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('독서 준비'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('week plan fits a narrow screen with large text', (tester) async {
    resetPrefs();
    final store = GrowthStore(SharedPreferencesAsync());
    await store.load();
    await store.addTask(
      '아침 준비',
      scheduledDay: store.today,
      scheduledTime: '08:00',
    );
    await store.addTask('반복 스트레칭', repeatPattern: 'daily');
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
          body: SingleChildScrollView(child: WeekTaskPanel(store: store)),
        ),
      ),
    );
    expect(find.textContaining('이번 주 계획'), findsOneWidget);
    await tester.tap(find.textContaining('이번 주 계획'));
    await tester.pumpAndSettle();
    expect(find.text('아침 준비'), findsOneWidget);
    expect(find.text('반복 스트레칭'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('task finder searches tags and filters completed tasks', (
    tester,
  ) async {
    resetPrefs();
    final store = GrowthStore(SharedPreferencesAsync());
    await store.load();
    await store.addGoal(
      title: '독서 목표',
      mini: '한 쪽',
      more: '10분',
      max: '30분',
      path: '균형 있게',
      milestones: [],
    );
    await store.addTask(
      '책 읽기',
      tags: ['공부'],
      priority: 'high',
      goalId: store.goals.single.id,
    );
    await store.addTask('청소', tags: ['집안일'], priority: 'low');
    await store.toggleTask(store.tasks.last);
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
          body: SingleChildScrollView(child: TaskFinder(store: store)),
        ),
      ),
    );
    await tester.tap(find.text('할 일 찾기'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '공부');
    await tester.pumpAndSettle();
    expect(find.text('책 읽기'), findsOneWidget);
    expect(find.text('청소'), findsNothing);
    await tester.enterText(find.byType(TextField), '');
    await tester.ensureVisible(
      find.byKey(const ValueKey('task-filter-status')),
    );
    await tester.tap(find.byKey(const ValueKey('task-filter-status')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('완료').last);
    await tester.pumpAndSettle();
    expect(find.text('청소'), findsOneWidget);
    expect(find.text('책 읽기'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('repeat menu skips and restores a single occurrence', (
    tester,
  ) async {
    resetPrefs();
    final store = GrowthStore(SharedPreferencesAsync());
    await store.load();
    await store.addTask('매일 산책', repeatPattern: 'daily');
    tester.view.physicalSize = const Size(320, 700);
    tester.view.devicePixelRatio = 1;
    tester.binding.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(
      tester.binding.platformDispatcher.clearTextScaleFactorTestValue,
    );
    Widget page() => MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(child: TodayChecklist(store: store)),
      ),
    );
    await tester.pumpWidget(page());
    await tester.ensureVisible(find.byTooltip('할 일 메뉴'));
    await tester.tap(find.byTooltip('할 일 메뉴'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('${store.today} 회차 쉬기'));
    await tester.pumpAndSettle();
    expect(store.tasks.single.wasSkippedOn(store.today), isTrue);
    await tester.pumpWidget(page());
    await tester.tap(find.text('다음 반복 · 1개'));
    await tester.pumpAndSettle();
    expect(find.textContaining('오늘 회차 쉬는 날'), findsOneWidget);
    await tester.ensureVisible(find.byTooltip('할 일 메뉴'));
    await tester.tap(find.byTooltip('할 일 메뉴'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('${store.today} 예외 되돌리기'));
    await tester.pumpAndSettle();
    expect(store.tasks.single.occursOn(store.today), isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('calendar shows each completed repeat occurrence', (
    tester,
  ) async {
    resetPrefs();
    final store = GrowthStore(SharedPreferencesAsync());
    await store.load();
    await store.addTask('산책 루틴', repeatPattern: 'daily');
    final task = store.tasks.single;
    final yesterday = dayKey(DateTime.now().subtract(const Duration(days: 1)));
    task.completedOccurrences.add(yesterday);
    await store.toggleTask(task);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(child: ActivityCalendar(store: store)),
        ),
      ),
    );
    expect(
      find.text('✓ 산책 루틴'),
      DateTime.now().day == 1 ? findsOneWidget : findsNWidgets(2),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('calendar shows a paused repeat occurrence', (tester) async {
    resetPrefs();
    final store = GrowthStore(SharedPreferencesAsync());
    await store.load();
    await store.addTask('쉬는 독서', repeatPattern: 'daily');
    await store.skipTaskOccurrence(store.tasks.single, store.today);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(child: ActivityCalendar(store: store)),
        ),
      ),
    );
    expect(find.text('⏸ 쉬는 독서 · 이번 회차 쉬기'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('records page can write a dated note', (tester) async {
    resetPrefs();
    final store = GrowthStore(SharedPreferencesAsync());
    await store.load();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(child: DailyNotesPanel(store: store)),
        ),
      ),
    );
    await tester.tap(find.text('오늘 메모 쓰기'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '오늘은 산책했다');
    await tester.pump();
    await tester.tap(find.text('저장'));
    await tester.pumpAndSettle();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(child: DailyNotesPanel(store: store)),
        ),
      ),
    );
    expect(find.text('오늘은 산책했다'), findsOneWidget);
    expect(store.notes.single.day, store.today);
    await tester.tap(find.byTooltip('메모 메뉴'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('수정'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '오늘은 쉬었다');
    await tester.pump();
    await tester.tap(find.text('저장'));
    await tester.pumpAndSettle();
    expect(store.notes.single.text, '오늘은 쉬었다');
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(child: DailyNotesPanel(store: store)),
        ),
      ),
    );
    await tester.tap(find.byTooltip('메모 메뉴'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('삭제'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('삭제').last);
    await tester.pumpAndSettle();
    expect(store.notes, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('today and records fit a narrow screen with large text', (
    tester,
  ) async {
    resetPrefs();
    final store = GrowthStore(SharedPreferencesAsync());
    await store.load();
    await store.addTask('오늘 꼭 처리할 일');
    await store.addNote(store.today, '오늘의 짧은 기록');
    tester.view.physicalSize = const Size(320, 700);
    tester.view.devicePixelRatio = 1;
    tester.binding.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(
      tester.binding.platformDispatcher.clearTextScaleFactorTestValue,
    );
    await tester.pumpWidget(GrowUpApp(store: store));
    await tester.scrollUntilVisible(find.text('오늘 꼭 처리할 일'), 250);
    await tester.pump();
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('기록').last);
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('오늘의 짧은 기록'), 250);
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
}
