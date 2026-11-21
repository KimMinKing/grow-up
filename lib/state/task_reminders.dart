import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as timezone_data;
import 'package:timezone/timezone.dart' as tz;

import '../models/daily_content.dart';
import 'growth_store.dart';

typedef TaskReminderPlan = ({
  String taskId,
  String day,
  String title,
  DateTime when,
});

class TaskReminderPlanner {
  static List<TaskReminderPlan> plan({
    required List<ChecklistItem> tasks,
    required DateTime now,
    required bool quietEnabled,
    required String quietStart,
    required String quietEnd,
    int horizonDays = 60,
    int limit = 100,
  }) {
    final planned = <TaskReminderPlan>[];
    final start = DateTime(now.year, now.month, now.day);
    for (var offset = 0; offset < horizonDays; offset++) {
      final date = DateTime(start.year, start.month, start.day + offset);
      final day = dayKey(date);
      for (final task in tasks) {
        if (!task.reminderEnabled ||
            task.archived ||
            task.scheduledTime == null) {
          continue;
        }
        if (task.repeats) {
          if (!task.occursOn(day) || task.wasCompletedOn(day)) continue;
        } else if (task.scheduledDay != day || task.completedDay != null) {
          continue;
        }
        final parts = task.scheduledTime!.split(':');
        var when = DateTime(
          date.year,
          date.month,
          date.day,
          int.parse(parts[0]),
          int.parse(parts[1]),
        );
        if (quietEnabled) {
          when = _afterQuiet(when, quietStart, quietEnd);
        }
        if (!when.isAfter(now)) continue;
        planned.add((taskId: task.id, day: day, title: task.title, when: when));
      }
    }
    planned.sort((a, b) {
      final byTime = a.when.compareTo(b.when);
      return byTime != 0 ? byTime : a.taskId.compareTo(b.taskId);
    });
    final seen = <String>{};
    return List.unmodifiable(
      planned
          .where(
            (item) => seen.add('${item.taskId}:${item.when.toIso8601String()}'),
          )
          .take(limit),
    );
  }

  static DateTime _afterQuiet(DateTime value, String start, String end) {
    final startMinute = _minute(start);
    final endMinute = _minute(end);
    final minute = value.hour * 60 + value.minute;
    final overnight = startMinute > endMinute;
    final inside = overnight
        ? minute >= startMinute || minute < endMinute
        : minute >= startMinute && minute < endMinute;
    if (!inside) return value;
    final nextDay = overnight && minute >= startMinute ? 1 : 0;
    return DateTime(
      value.year,
      value.month,
      value.day + nextDay,
      endMinute ~/ 60,
      endMinute % 60,
    );
  }

  static int _minute(String value) {
    final parts = value.split(':');
    return int.parse(parts[0]) * 60 + int.parse(parts[1]);
  }
}

final taskReminderService = TaskReminderService();

class TaskReminderService with WidgetsBindingObserver {
  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  final ValueNotifier<String?> tappedTaskId = ValueNotifier(null);
  GrowthStore? _store;
  bool _ready = false;
  Future<void> _queue = Future.value();
  String? _lastFingerprint;

  Future<void> start(GrowthStore store) async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
    _store = store;
    timezone_data.initializeTimeZones();
    try {
      final info = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(info.identifier));
    } catch (_) {
      tz.setLocalLocation(tz.UTC);
    }
    await _plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('ic_notification'),
      ),
      onDidReceiveNotificationResponse: (response) =>
          _recordTap(response.payload),
    );
    final launch = await _plugin.getNotificationAppLaunchDetails();
    if (launch?.didNotificationLaunchApp == true) {
      _recordTap(launch?.notificationResponse?.payload);
    }
    _ready = true;
    WidgetsBinding.instance.addObserver(this);
    store.addListener(() => requestSync());
    requestSync();
  }

  void _recordTap(String? taskId) {
    if (taskId == null || taskId.isEmpty) return;
    tappedTaskId.value = taskId;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) requestSync(force: true);
  }

  Future<bool> requestPermission() async {
    if (!_ready) return false;
    final android = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    final granted = await android?.requestNotificationsPermission();
    final enabled =
        granted ?? await android?.areNotificationsEnabled() ?? false;
    if (enabled) requestSync(force: true);
    return enabled;
  }

  void requestSync({bool force = false}) {
    if (!_ready || _store == null) return;
    _queue = _queue.then((_) => _sync(force: force)).catchError((Object error) {
      debugPrint('Could not schedule task reminders: $error');
    });
  }

  Future<void> _sync({required bool force}) async {
    final store = _store!;
    final now = DateTime.now();
    final fingerprint = jsonEncode({
      'day': dayKey(now),
      'quietEnabled': store.quietEnabled,
      'quietStart': store.quietStart,
      'quietEnd': store.quietEnd,
      'tasks': [
        for (final task in store.tasks)
          if (task.reminderEnabled) task.toJson(),
      ],
    });
    if (!force && fingerprint == _lastFingerprint) return;
    await _plugin.cancelAllPendingNotifications();
    final android = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    final enabled = await android?.areNotificationsEnabled();
    if (enabled == false) {
      _lastFingerprint = fingerprint;
      return;
    }
    final plans = TaskReminderPlanner.plan(
      tasks: store.tasks,
      now: now,
      quietEnabled: store.quietEnabled,
      quietStart: store.quietStart,
      quietEnd: store.quietEnd,
    );
    const details = NotificationDetails(
      android: AndroidNotificationDetails(
        'task_reminders',
        '할 일 알림',
        channelDescription: '사용자가 선택한 할 일의 예정 시각 알림',
        importance: Importance.defaultImportance,
        priority: Priority.defaultPriority,
      ),
    );
    for (var index = 0; index < plans.length; index++) {
      final plan = plans[index];
      await _plugin.zonedSchedule(
        id: 100000 + index,
        title: '할 일 예정',
        body: plan.title,
        scheduledDate: tz.TZDateTime.from(plan.when, tz.local),
        notificationDetails: details,
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        payload: plan.taskId,
      );
    }
    _lastFingerprint = fingerprint;
  }
}
