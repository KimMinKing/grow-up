import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:growup/daily_content_widgets.dart';
import 'package:growup/models/daily_content.dart';
import 'package:growup/state/growth_backup.dart';
import 'package:growup/state/growth_store.dart';
import 'package:growup/state/task_reminders.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('one-off reminders use the planned day and ignore completed tasks', () {
    final task = ChecklistItem(
      id: 'once',
      title: '책 읽기',
      createdDay: '2026-11-03',
      scheduledDay: '2026-11-04',
      scheduledTime: '09:30',
      reminderEnabled: true,
    );
    List<TaskReminderPlan> plan() => TaskReminderPlanner.plan(
      tasks: [task],
      now: DateTime(2026, 11, 3, 12),
      quietEnabled: false,
      quietStart: '22:00',
      quietEnd: '08:00',
    );

    expect(plan().single.when, DateTime(2026, 11, 4, 9, 30));
    task.completedDay = '2026-11-03';
    expect(plan(), isEmpty);
    task.completedDay = null;
    task.archived = true;
    expect(plan(), isEmpty);
  });

  test('repeat reminders skip completed and moved occurrences', () {
    final task = ChecklistItem(
      id: 'repeat',
      title: '스트레칭',
      createdDay: '2026-11-03',
      scheduledTime: '10:00',
      repeatPattern: 'daily',
      completedOccurrences: ['2026-11-04'],
      movedOccurrences: {'2026-11-05': '2026-11-06'},
      reminderEnabled: true,
    );
    final plans = TaskReminderPlanner.plan(
      tasks: [task],
      now: DateTime(2026, 11, 3, 11),
      quietEnabled: false,
      quietStart: '22:00',
      quietEnd: '08:00',
      horizonDays: 5,
    );

    expect(plans.map((item) => item.day), ['2026-11-06', '2026-11-07']);
    expect(plans.map((item) => item.when), [
      DateTime(2026, 11, 6, 10),
      DateTime(2026, 11, 7, 10),
    ]);
  });

  test('quiet hours shift a night reminder to the following morning', () {
    final task = ChecklistItem(
      id: 'night',
      title: '내일 준비',
      createdDay: '2026-11-03',
      scheduledDay: '2026-11-03',
      scheduledTime: '22:30',
      reminderEnabled: true,
    );
    final plans = TaskReminderPlanner.plan(
      tasks: [task],
      now: DateTime(2026, 11, 3, 20),
      quietEnabled: true,
      quietStart: '22:00',
      quietEnd: '08:00',
    );

    expect(plans.single.day, '2026-11-03');
    expect(plans.single.when, DateTime(2026, 11, 4, 8));
  });

  test('daytime quiet hours move only reminders inside the interval', () {
    final tasks = [
      ChecklistItem(
        id: 'before',
        title: '점심 준비',
        createdDay: '2026-11-03',
        scheduledDay: '2026-11-03',
        scheduledTime: '11:30',
        reminderEnabled: true,
      ),
      ChecklistItem(
        id: 'inside',
        title: '점심 후 걷기',
        createdDay: '2026-11-03',
        scheduledDay: '2026-11-03',
        scheduledTime: '12:30',
        reminderEnabled: true,
      ),
    ];
    final plans = TaskReminderPlanner.plan(
      tasks: tasks,
      now: DateTime(2026, 11, 3, 10),
      quietEnabled: true,
      quietStart: '12:00',
      quietEnd: '13:00',
    );

    expect(plans.map((item) => item.when), [
      DateTime(2026, 11, 3, 11, 30),
      DateTime(2026, 11, 3, 13),
    ]);
  });

  test(
    'multiple quiet-hour occurrences become one alert per task and time',
    () {
      final task = ChecklistItem(
        id: 'early',
        title: '물 마시기',
        createdDay: '2026-11-03',
        repeatPattern: 'daily',
        scheduledTime: '07:00',
        reminderEnabled: true,
      );
      final plans = TaskReminderPlanner.plan(
        tasks: [task],
        now: DateTime(2026, 11, 3, 6),
        quietEnabled: true,
        quietStart: '22:00',
        quietEnd: '08:00',
        horizonDays: 3,
        limit: 2,
      );

      expect(plans.length, 2);
      expect(plans.first.when, DateTime(2026, 11, 3, 8));
      expect(plans.last.when, DateTime(2026, 11, 4, 8));
    },
  );

  test(
    'reminder settings survive reload and legacy task data defaults off',
    () async {
      SharedPreferencesAsyncPlatform.instance =
          InMemorySharedPreferencesAsync.empty();
      final prefs = SharedPreferencesAsync();
      final store = GrowthStore(prefs);
      await store.load();
      expect(
        await store.addTask(
          '내일 읽기',
          scheduledDay: '2026-11-04',
          scheduledTime: '09:30',
          reminderEnabled: true,
        ),
        isTrue,
      );
      expect(
        await store.setQuietHours(enabled: true, start: '23:00', end: '07:00'),
        isTrue,
      );

      final restored = GrowthStore(prefs);
      await restored.load();
      expect(restored.tasks.single.reminderEnabled, isTrue);
      expect(restored.quietEnabled, isTrue);
      expect(restored.quietStart, '23:00');
      expect(restored.quietEnd, '07:00');

      final oldJson = Map<String, dynamic>.from(restored.tasks.single.toJson())
        ..remove('reminderEnabled');
      expect(ChecklistItem.fromJson(oldJson).reminderEnabled, isFalse);
      expect(await restored.addTask('시간 없음', reminderEnabled: true), isFalse);
    },
  );
  testWidgets('quiet hours can be changed on a narrow large-text screen', (
    tester,
  ) async {
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
          body: SingleChildScrollView(child: TaskQuietHoursPanel(store: store)),
        ),
      ),
    );

    await tester.tap(find.text('알림과 조용한 시간'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('조용한 시간 변경'));
    await tester.pumpAndSettle();
    expect(find.text('조용한 시간'), findsOneWidget);
    await tester.enterText(find.byType(TextField).first, '23:00');
    await tester.enterText(find.byType(TextField).last, '07:00');
    await tester.tap(find.text('저장'));
    await tester.pumpAndSettle();
    expect(store.quietStart, '23:00');
    expect(store.quietEnd, '07:00');
    expect(tester.takeException(), isNull);
  });

  test(
    'backup preserves reminder choice and rejects invalid reminder data',
    () {
      final task = ChecklistItem(
        id: 'backup-task',
        title: '예약된 일',
        createdDay: '2026-11-03',
        scheduledDay: '2026-11-04',
        scheduledTime: '11:00',
        reminderEnabled: true,
      );
      final backup = GrowthBackup(
        goals: const [],
        guardianName: '루온',
        darkTheme: false,
        tasks: [task],
      );
      expect(
        GrowthBackup.decode(backup.encode()).tasks.single.reminderEnabled,
        isTrue,
      );
      expect(
        () => ChecklistItem.fromJson(
          Map<String, dynamic>.from(task.toJson())..['scheduledTime'] = null,
        ),
        throwsFormatException,
      );
    },
  );
}
