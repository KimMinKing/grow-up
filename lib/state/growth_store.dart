import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/growth_goal.dart';
import '../models/reward_grant.dart';
import '../models/daily_content.dart';
import '../models/daily_snapshot.dart';
import '../models/roadmap_plan.dart';
import 'goal_sync_planner.dart';
import 'growth_backup.dart';

typedef GoalActivity = ({DateTime date, String level, String? action});
typedef WeeklyActivity = ({DateTime start, int completedDays});
typedef WeekTaskEntry = ({ChecklistItem task, String day, String status});
const Object _unchangedGoalId = Object();

class GrowthStore extends ChangeNotifier {
  GrowthStore(this._prefs);

  static const _storageKey = 'growth_goals_v1';
  static const _guardianNameKey = 'guardian_name_v1';
  static const _darkThemeKey = 'dark_theme_v1';
  static const _showGameRewardsKey = 'show_game_rewards_v1';
  static const _dailyStorageKey = 'growth_daily_v1';
  static const _quietEnabledKey = 'task_quiet_enabled_v1';
  static const _quietStartKey = 'task_quiet_start_v1';
  static const _quietEndKey = 'task_quiet_end_v1';
  final SharedPreferencesAsync _prefs;
  final List<GrowthGoal> _goals = [];
  final List<ChecklistItem> _tasks = [];
  final List<DailyNote> _notes = [];
  String _guardianName = '루온';
  bool _darkTheme = false;
  bool _showGameRewards = true;
  bool _quietEnabled = false;
  String _quietStart = '22:00';
  String _quietEnd = '08:00';

  String get guardianName => _guardianName;
  bool get darkTheme => _darkTheme;
  bool get showGameRewards => _showGameRewards;
  bool get quietEnabled => _quietEnabled;
  String get quietStart => _quietStart;
  String get quietEnd => _quietEnd;

  Future<bool> setQuietHours({
    required bool enabled,
    required String start,
    required String end,
  }) async {
    if (!validTaskTime(start) || !validTaskTime(end) || start == end) {
      return false;
    }
    _quietEnabled = enabled;
    _quietStart = start;
    _quietEnd = end;
    notifyListeners();
    await _prefs.setBool(_quietEnabledKey, enabled);
    await _prefs.setString(_quietStartKey, start);
    await _prefs.setString(_quietEndKey, end);
    return true;
  }

  Future<void> setDarkTheme(bool value) async {
    if (_darkTheme == value) return;
    _darkTheme = value;
    notifyListeners();
    await _prefs.setBool(_darkThemeKey, value);
  }

  Future<void> setShowGameRewards(bool value) async {
    if (_showGameRewards == value) return;
    _showGameRewards = value;
    notifyListeners();
    await _prefs.setBool(_showGameRewardsKey, value);
  }

  List<GrowthGoal> get goals =>
      List.unmodifiable(_goals.where((goal) => !goal.archived));

  List<GrowthGoal> get archivedGoals =>
      List.unmodifiable(_goals.where((goal) => goal.archived));

  List<GrowthGoal> get allGoals => List.unmodifiable(_goals);

  List<ChecklistItem> get tasks => List.unmodifiable(_tasks);
  List<DailyNote> get notes => List.unmodifiable(_notes);

  DailySnapshot get dailySnapshot => DailySnapshot.fromJson({
    'version': 1,
    'tasks': _tasks.map((task) => task.toJson()).toList(),
    'notes': _notes.map((note) => note.toJson()).toList(),
  });

  Future<bool> replaceSyncedDaily(
    DailySnapshot incoming, {
    required DailySnapshot expectedLocal,
  }) async {
    if (jsonEncode(dailySnapshot.toJson()) !=
        jsonEncode(expectedLocal.toJson())) {
      return false;
    }
    final validated = DailySnapshot.fromJson(incoming.toJson());
    await _prefs.setString(
      _dailyStorageKey,
      jsonEncode({
        'tasks': validated.tasks.map((task) => task.toJson()).toList(),
        'notes': validated.notes.map((note) => note.toJson()).toList(),
      }),
    );
    if (jsonEncode(dailySnapshot.toJson()) !=
        jsonEncode(expectedLocal.toJson())) {
      await _saveDaily();
      return false;
    }
    _tasks
      ..clear()
      ..addAll(validated.tasks);
    _notes
      ..clear()
      ..addAll(validated.notes);
    notifyListeners();
    return true;
  }

  /// Erase local growth records and their presentation settings.
  Future<void> clearLocalData() async {
    for (final key in [
      _storageKey,
      _guardianNameKey,
      _darkThemeKey,
      _showGameRewardsKey,
      _dailyStorageKey,
      _quietEnabledKey,
      _quietStartKey,
      _quietEndKey,
      'growup.focus-session.v1',
    ]) {
      await _prefs.remove(key);
    }
    _goals.clear();
    _tasks.clear();
    _notes.clear();
    _guardianName = '루온';
    _darkTheme = false;
    _showGameRewards = true;
    _quietEnabled = false;
    _quietStart = '22:00';
    _quietEnd = '08:00';
    notifyListeners();
  }

  Iterable<String> get rewardableTaskCompletionIds sync* {
    for (final task in _tasks) {
      if (task.roadmapLinked) continue;
      if (task.completedDay != null &&
          !task.completedOccurrences.contains(task.completedDay)) {
        yield task.id;
      }
      for (final day in task.completedOccurrences) {
        yield '${task.id}:$day';
      }
    }
  }

  Iterable<RewardCandidate> get rewardCandidates sync* {
    for (final task in _tasks) {
      if (task.roadmapLinked) continue;
      if (task.completedDay != null &&
          !task.completedOccurrences.contains(task.completedDay)) {
        yield (
          sourceId: task.id,
          kind: 'task',
          trainingPasses: RewardRules.oneOffTrainingPasses,
          experience: 0,
          activityDay: task.completedDay!,
        );
      }
      for (final day in task.completedOccurrences) {
        yield (
          sourceId: '${task.id}:$day',
          kind: 'routine',
          trainingPasses: RewardRules.routineTrainingPasses,
          experience: 0,
          activityDay: day,
        );
      }
    }
    for (final goal in _goals) {
      if (goal.localBackup) continue;
      for (final entry in goal.completions.entries) {
        final kind = RewardRules.goalKind(entry.value);
        if (kind == null) continue;
        yield (
          sourceId: 'goal:${goal.id}:${entry.key}',
          kind: kind,
          trainingPasses: RewardRules.goalTrainingPasses(entry.value),
          experience: RewardRules.goalExperience(entry.value),
          activityDay: entry.key,
        );
      }
    }
  }

  List<ChecklistItem> get pendingTasks {
    final pending = _tasks
        .where(
          (task) =>
              (task.repeats
                  ? task.occursOn(today) && !task.wasCompletedOn(today)
                  : task.completedDay == null) &&
              !task.archived &&
              task.createdDay.compareTo(today) <= 0 &&
              (task.repeats ||
                  task.scheduledDay == null ||
                  task.scheduledDay!.compareTo(today) <= 0),
        )
        .toList();
    final originalOrder = {
      for (var index = 0; index < pending.length; index++)
        pending[index].id: index,
    };
    pending.sort((a, b) {
      final aTime = a.scheduledTime;
      final bTime = b.scheduledTime;
      if (aTime == null) {
        return bTime == null
            ? originalOrder[a.id]!.compareTo(originalOrder[b.id]!)
            : 1;
      }
      if (bTime == null) return -1;
      final byTime = aTime.compareTo(bTime);
      return byTime != 0
          ? byTime
          : originalOrder[a.id]!.compareTo(originalOrder[b.id]!);
    });
    return List.unmodifiable(pending);
  }

  List<ChecklistItem> get overdueTasks => List.unmodifiable(
    pendingTasks
        .where(
          (task) =>
              task.scheduledDay != null &&
              !task.repeats &&
              task.scheduledDay!.compareTo(today) < 0,
        )
        .toList()
      ..sort((a, b) => a.scheduledDay!.compareTo(b.scheduledDay!)),
  );

  List<ChecklistItem> get dueTodayTasks => List.unmodifiable(
    pendingTasks.where((task) => task.repeats || task.scheduledDay == today),
  );

  List<ChecklistItem> get undatedTasks => List.unmodifiable(
    pendingTasks.where((task) => !task.repeats && task.scheduledDay == null),
  );

  List<ChecklistItem> get upcomingTasks {
    final upcoming = _tasks
        .where(
          (task) =>
              task.completedDay == null &&
              !task.repeats &&
              !task.archived &&
              task.scheduledDay != null &&
              task.scheduledDay!.compareTo(today) > 0,
        )
        .toList();
    final originalOrder = {
      for (var index = 0; index < upcoming.length; index++)
        upcoming[index].id: index,
    };
    upcoming.sort((a, b) {
      final byDay = a.scheduledDay!.compareTo(b.scheduledDay!);
      if (byDay != 0) return byDay;
      final aTime = a.scheduledTime;
      final bTime = b.scheduledTime;
      if (aTime == null) {
        return bTime == null
            ? originalOrder[a.id]!.compareTo(originalOrder[b.id]!)
            : 1;
      }
      if (bTime == null) return -1;
      final byTime = aTime.compareTo(bTime);
      return byTime != 0
          ? byTime
          : originalOrder[a.id]!.compareTo(originalOrder[b.id]!);
    });
    return List.unmodifiable(upcoming);
  }

  List<ChecklistItem> get archivedTasks => List.unmodifiable(
    _tasks.where(
      (task) => task.archived && (task.repeats || task.completedDay == null),
    ),
  );

  List<ChecklistItem> get recurringLaterTasks => List.unmodifiable(
    _tasks.where(
      (task) => task.repeats && !task.archived && !task.occursOn(today),
    ),
  );

  List<ChecklistItem> get completedTasks => List.unmodifiable(
    _tasks.where((task) => task.completedDay != null).toList()
      ..sort((a, b) => b.completedDay!.compareTo(a.completedDay!)),
  );

  List<ChecklistItem> tasksPlannedOn(String day) => List.unmodifiable(
    _tasks.where(
      (task) =>
          !task.archived &&
          !task.roadmapLinked &&
          (task.repeats ? task.occursOn(day) : task.scheduledDay == day),
    ),
  );

  List<WeekTaskEntry> weekTaskEntries(DateTime anchor) {
    final start = DateTime.utc(
      anchor.year,
      anchor.month,
      anchor.day,
    ).subtract(Duration(days: anchor.weekday - 1));
    final days = List.generate(
      7,
      (index) => dayKey(start.add(Duration(days: index))),
    );
    final entries = <WeekTaskEntry>[];
    for (final task in _tasks) {
      for (final day in days) {
        if (task.repeats) {
          final status = task.wasCompletedOn(day)
              ? 'done'
              : task.wasSkippedOn(day)
              ? 'skipped'
              : task.movedOccurrences.containsKey(day)
              ? 'moved'
              : task.occursOn(day) && !task.archived
              ? 'planned'
              : null;
          if (status != null) {
            entries.add((task: task, day: day, status: status));
          }
        } else if (task.completedDay == day) {
          entries.add((task: task, day: day, status: 'done'));
        } else if (task.movedOccurrences.containsKey(day)) {
          entries.add((task: task, day: day, status: 'moved'));
        } else if (task.scheduledDay == day &&
            !task.archived &&
            task.completedDay == null) {
          entries.add((task: task, day: day, status: 'planned'));
        }
      }
    }
    final originalOrder = {
      for (var index = 0; index < _tasks.length; index++)
        _tasks[index].id: index,
    };
    entries.sort((a, b) {
      final byDay = a.day.compareTo(b.day);
      if (byDay != 0) return byDay;
      final aTime = a.task.scheduledTime;
      final bTime = b.task.scheduledTime;
      if (aTime == null && bTime != null) return 1;
      if (aTime != null && bTime == null) return -1;
      final byTime = (aTime ?? '').compareTo(bTime ?? '');
      return byTime != 0
          ? byTime
          : originalOrder[a.task.id]!.compareTo(originalOrder[b.task.id]!);
    });
    return List.unmodifiable(entries);
  }

  GrowthBackup createBackup() => GrowthBackup(
    goals: _goals
        .map(
          (goal) => GrowthGoal.fromJson(
            Map<String, dynamic>.from(
              jsonDecode(jsonEncode(goal.toJson())) as Map,
            ),
          ),
        )
        .toList(),
    guardianName: _guardianName,
    darkTheme: _darkTheme,
    tasks: _tasks.map((task) => ChecklistItem.fromJson(task.toJson())).toList(),
    notes: _notes.map((note) => DailyNote.fromJson(note.toJson())).toList(),
  );

  Future<BackupImportResult> importBackup(GrowthBackup backup) async {
    final next = List<GrowthGoal>.from(_goals);
    final ids = {
      ...next.map((goal) => goal.id),
      ...backup.goals.map((goal) => goal.id),
    };
    var activeCount = next.where((goal) => !goal.archived).length;
    var added = 0;
    var skipped = 0;
    var archivedCopies = 0;
    var copyIndex = 0;
    final importedGoalIdRemap = <String, String>{};
    for (final original in backup.goals) {
      final incoming = GrowthGoal.fromJson(original.toJson());
      final existing = goalById(incoming.id);
      if (existing == null) {
        if (!incoming.archived && activeCount >= 5) {
          incoming.archived = true;
          incoming.localBackup = true;
          archivedCopies++;
        } else {
          if (!incoming.archived) activeCount++;
          added++;
        }
        next.add(incoming);
        ids.add(incoming.id);
      } else if (goalSnapshotsEqual(existing.toJson(), incoming.toJson())) {
        skipped++;
      } else {
        String copyId;
        do {
          copyId =
              'import-${DateTime.now().microsecondsSinceEpoch}-${copyIndex++}';
        } while (ids.contains(copyId));
        final copy = Map<String, dynamic>.from(incoming.toJson())
          ..['id'] = copyId
          ..['title'] =
              '${incoming.title.substring(0, incoming.title.length > 140 ? 140 : incoming.title.length)} (가져온 보관본)'
          ..['archived'] = true
          ..['localBackup'] = true;
        next.add(GrowthGoal.fromJson(copy));
        ids.add(copyId);
        importedGoalIdRemap[incoming.id] = copyId;
        archivedCopies++;
      }
    }
    final nextTasks = List<ChecklistItem>.from(_tasks);
    final taskIds = nextTasks.map((task) => task.id).toSet();
    var tasksAdded = 0;
    for (final incoming in backup.tasks) {
      final incomingJson = incoming.toJson();
      final remappedGoalId = importedGoalIdRemap[incoming.goalId];
      if (remappedGoalId != null) incomingJson['goalId'] = remappedGoalId;
      if (incoming.roadmapLinked) {
        final linkedGoal = next
            .where((goal) => goal.id == incomingJson['goalId'])
            .firstOrNull;
        if (linkedGoal != null) {
          incomingJson['completedDay'] =
              linkedGoal.isDoneOn(incoming.scheduledDay!)
              ? incoming.scheduledDay
              : null;
        }
        if (linkedGoal == null ||
            linkedGoal.archived ||
            nextTasks.any(
              (task) =>
                  task.roadmapLinked &&
                  !task.archived &&
                  task.goalId == incomingJson['goalId'] &&
                  task.scheduledDay == incoming.scheduledDay &&
                  (task.id != incoming.id ||
                      jsonEncode(task.toJson()) != jsonEncode(incomingJson)),
            )) {
          incomingJson['archived'] = true;
        }
      }
      final existing = nextTasks
          .where((task) => task.id == incoming.id)
          .firstOrNull;
      if (existing == null) {
        nextTasks.add(ChecklistItem.fromJson(incomingJson));
        taskIds.add(incoming.id);
        tasksAdded++;
      } else if (jsonEncode(existing.toJson()) != jsonEncode(incomingJson)) {
        final copy = incomingJson..['id'] = _freshDailyId('task', taskIds);
        nextTasks.add(ChecklistItem.fromJson(copy));
        tasksAdded++;
      }
    }
    final nextNotes = List<DailyNote>.from(_notes);
    final noteIds = nextNotes.map((note) => note.id).toSet();
    var notesAdded = 0;
    for (final incoming in backup.notes) {
      final existing = nextNotes
          .where((note) => note.id == incoming.id)
          .firstOrNull;
      if (existing == null) {
        nextNotes.add(DailyNote.fromJson(incoming.toJson()));
        noteIds.add(incoming.id);
        notesAdded++;
      } else if (jsonEncode(existing.toJson()) !=
          jsonEncode(incoming.toJson())) {
        final copy = incoming.toJson()..['id'] = _freshDailyId('note', noteIds);
        nextNotes.add(DailyNote.fromJson(copy));
        notesAdded++;
      }
    }
    if (nextTasks.length > 1000 || nextNotes.length > 1000) {
      throw const FormatException('할 일이나 메모가 너무 많아 백업을 가져올 수 없어요.');
    }
    final settingsRestored = _goals.isEmpty && _tasks.isEmpty && _notes.isEmpty;
    await _prefs.setString(
      _storageKey,
      jsonEncode(next.map((goal) => goal.toJson()).toList()),
    );
    if (settingsRestored) {
      await _prefs.setString(_guardianNameKey, backup.guardianName);
      await _prefs.setBool(_darkThemeKey, backup.darkTheme);
      _guardianName = backup.guardianName;
      _darkTheme = backup.darkTheme;
    }
    _goals
      ..clear()
      ..addAll(next);
    _tasks
      ..clear()
      ..addAll(nextTasks);
    _notes
      ..clear()
      ..addAll(nextNotes);
    _reconcileRoadmapTasks();
    await _saveDaily();
    notifyListeners();
    return BackupImportResult(
      added: added,
      skipped: skipped,
      archivedCopies: archivedCopies,
      settingsRestored: settingsRestored,
      tasksAdded: tasksAdded,
      notesAdded: notesAdded,
    );
  }

  GrowthGoal? goalById(String id) {
    for (final goal in _goals) {
      if (goal.id == id) return goal;
    }
    return null;
  }

  Future<bool> importSyncedGoal(
    GrowthGoal incoming, {
    Map<String, dynamic>? expectedLocal,
    bool keepLocalBackup = false,
    void Function()? beforeApply,
  }) async {
    final current = goalById(incoming.id);
    if (current == null && expectedLocal != null) return false;
    if (current != null &&
        (expectedLocal == null ||
            jsonEncode(current.toJson()) != jsonEncode(expectedLocal))) {
      return false;
    }
    final activeAfter =
        goals.length -
        (current != null && !current.archived ? 1 : 0) +
        (!incoming.archived ? 1 : 0);
    if (activeAfter > 5) return false;
    if (current != null && keepLocalBackup) {
      await addSyncBackup(current.toJson());
    }
    beforeApply?.call();
    final activeAfterBackup =
        goals.length -
        (current != null && !current.archived ? 1 : 0) +
        (!incoming.archived ? 1 : 0);
    if (!identical(goalById(incoming.id), current) ||
        (current != null &&
            jsonEncode(current.toJson()) != jsonEncode(expectedLocal)) ||
        activeAfterBackup > 5) {
      return false;
    }
    if (current != null) {
      _goals[_goals.indexOf(current)] = incoming;
    } else {
      _goals.add(incoming);
    }
    notifyListeners();
    await _save();
    return true;
  }

  Future<void> addSyncBackup(Map<String, dynamic> snapshot) async {
    final data = Map<String, dynamic>.from(
      jsonDecode(jsonEncode(snapshot)) as Map,
    );
    var backupId = 'backup-${DateTime.now().microsecondsSinceEpoch}';
    while (goalById(backupId) != null) {
      backupId = 'backup-${DateTime.now().microsecondsSinceEpoch}';
    }
    data['id'] = backupId;
    const suffix = ' (동기화 보관본)';
    final title = data['title'] as String;
    final maxTitleLength = 160 - suffix.length;
    data['title'] =
        '${title.length > maxTitleLength ? title.substring(0, maxTitleLength) : title}$suffix';
    data['archived'] = true;
    data['localBackup'] = true;
    _goals.add(GrowthGoal.fromJson(data));
    notifyListeners();
    await _save();
  }

  String get today => dayKey(DateTime.now());

  String _freshDailyId(String prefix, Set<String> used) {
    var index = 0;
    String id;
    do {
      id = '$prefix-${DateTime.now().microsecondsSinceEpoch}-${index++}';
    } while (used.contains(id));
    used.add(id);
    return id;
  }

  Future<bool> addTask(
    String title, {
    String? scheduledDay,
    String? scheduledTime,
    String repeatPattern = 'none',
    List<int> repeatWeekdays = const [],
    int repeatIntervalDays = 2,
    String priority = 'normal',
    List<String> tags = const [],
    String? goalId,
    bool reminderEnabled = false,
  }) async {
    final value = title.trim();
    if (value.isEmpty ||
        value.length > 160 ||
        _tasks.length >= 1000 ||
        !_validRepeat(repeatPattern, repeatWeekdays, repeatIntervalDays) ||
        !_validTaskCategory(priority, tags, goalId) ||
        (reminderEnabled &&
            (scheduledTime == null ||
                (repeatPattern == 'none' && scheduledDay == null))) ||
        (scheduledDay != null && !validDailyKey(scheduledDay)) ||
        (scheduledTime != null && !validTaskTime(scheduledTime))) {
      return false;
    }
    _tasks.add(
      ChecklistItem(
        id: _freshDailyId('task', _tasks.map((task) => task.id).toSet()),
        title: value,
        createdDay: today,
        scheduledDay: scheduledDay,
        scheduledTime: scheduledTime,
        repeatPattern: repeatPattern,
        repeatWeekdays: List.of(repeatWeekdays),
        repeatIntervalDays: repeatIntervalDays,
        priority: priority,
        tags: List.of(tags),
        goalId: goalId,
        reminderEnabled: reminderEnabled,
      ),
    );
    notifyListeners();
    await _saveDaily();
    return true;
  }

  Future<bool> copyTask(ChecklistItem source) async {
    if (!_tasks.contains(source) ||
        source.roadmapLinked ||
        _tasks.length >= 1000) {
      return false;
    }
    final stepIds = _tasks
        .expand((task) => task.steps.map((step) => step.id))
        .toSet();
    final copy = ChecklistItem(
      id: _freshDailyId('task', _tasks.map((task) => task.id).toSet()),
      title: source.title,
      createdDay: today,
      scheduledDay: source.scheduledDay == null
          ? null
          : source.scheduledDay!.compareTo(today) < 0
          ? today
          : source.scheduledDay,
      scheduledTime: source.scheduledTime,
      repeatPattern: source.repeatPattern,
      repeatWeekdays: List.of(source.repeatWeekdays),
      repeatIntervalDays: source.repeatIntervalDays,
      priority: source.priority,
      tags: List.of(source.tags),
      goalId: source.goalId,
      steps: [
        for (final step in source.steps)
          ChecklistStep(id: _freshDailyId('step', stepIds), title: step.title),
      ],
    );
    await _saveDaily(tasks: [..._tasks, copy]);
    _tasks.add(copy);
    notifyListeners();
    return true;
  }

  Future<bool> addRoadmapAction(GrowthGoal goal, int milestoneIndex) async {
    if (!_goals.contains(goal) ||
        goal.archived ||
        milestoneIndex < 0 ||
        milestoneIndex >= goal.milestones.length ||
        goal.completedMilestones.contains(milestoneIndex) ||
        goal.isDoneOn(today) ||
        goal.restDays.contains(today) ||
        List.generate(
          milestoneIndex,
          (index) => index,
        ).any((index) => !goal.completedMilestones.contains(index)) ||
        _tasks.length >= 1000 ||
        _tasks.any(
          (task) =>
              task.roadmapLinked &&
              !task.archived &&
              task.goalId == goal.id &&
              task.scheduledDay == today,
        )) {
      return false;
    }
    final method = goal.milestoneDetails[milestoneIndex].method.trim();
    final proposed = method.isEmpty
        ? goal.milestones[milestoneIndex].trim()
        : method.split(RegExp(r'[\n\r]')).first.trim();
    final title = proposed.length > 160
        ? proposed.substring(0, 160).trimRight()
        : proposed;
    if (title.isEmpty) return false;
    _tasks.add(
      ChecklistItem(
        id: _freshDailyId('task', _tasks.map((task) => task.id).toSet()),
        title: title,
        createdDay: today,
        scheduledDay: today,
        goalId: goal.id,
        roadmapLinked: true,
      ),
    );
    notifyListeners();
    await _saveDaily();
    return true;
  }

  Future<bool> updateTask(
    ChecklistItem task,
    String title, {
    String? scheduledDay,
    String? scheduledTime,
    String? repeatPattern,
    List<int>? repeatWeekdays,
    int? repeatIntervalDays,
    String? priority,
    List<String>? tags,
    Object? goalId = _unchangedGoalId,
    bool? reminderEnabled,
  }) async {
    final value = title.trim();
    final pattern = repeatPattern ?? task.repeatPattern;
    final weekdays = repeatWeekdays ?? task.repeatWeekdays;
    final nextWeekdays = List<int>.of(weekdays);
    final interval = repeatIntervalDays ?? task.repeatIntervalDays;
    final nextPriority = priority ?? task.priority;
    final nextTags = List<String>.of(tags ?? task.tags);
    final nextGoalId = identical(goalId, _unchangedGoalId)
        ? task.goalId
        : goalId;
    final nextReminder = reminderEnabled ?? task.reminderEnabled;
    if (!_tasks.contains(task) ||
        value.isEmpty ||
        value.length > 160 ||
        !_validRepeat(pattern, weekdays, interval) ||
        nextGoalId is! String? ||
        !_validTaskCategory(nextPriority, nextTags, nextGoalId) ||
        (task.roadmapLinked &&
            (pattern != 'none' ||
                scheduledDay == null ||
                nextGoalId != task.goalId ||
                _tasks.any(
                  (other) =>
                      other != task &&
                      other.roadmapLinked &&
                      !other.archived &&
                      other.goalId == task.goalId &&
                      other.scheduledDay == scheduledDay,
                ))) ||
        (nextReminder &&
            (scheduledTime == null ||
                (pattern == 'none' && scheduledDay == null))) ||
        (scheduledDay != null && !validDailyKey(scheduledDay)) ||
        (scheduledTime != null && !validTaskTime(scheduledTime))) {
      return false;
    }
    final previousDay = task.scheduledDay;
    if (!task.repeats &&
        task.completedDay == null &&
        previousDay != null &&
        scheduledDay != null &&
        scheduledDay.compareTo(previousDay) > 0) {
      task.movedOccurrences[previousDay] = scheduledDay;
    }
    task.title = value;
    task.scheduledDay = scheduledDay;
    task.scheduledTime = scheduledTime;
    if (task.repeats &&
        pattern == 'none' &&
        task.completedOccurrences.contains(today)) {
      task.completedDay = today;
    }
    task.repeatPattern = pattern;
    task.repeatWeekdays
      ..clear()
      ..addAll(nextWeekdays);
    task.repeatIntervalDays = interval;
    task.priority = nextPriority;
    task.tags
      ..clear()
      ..addAll(nextTags);
    task.goalId = nextGoalId;
    task.reminderEnabled = nextReminder;
    if (task.roadmapLinked) {
      final goal = goalById(task.goalId!);
      task.completedDay = goal?.isDoneOn(scheduledDay!) == true
          ? scheduledDay
          : null;
    }
    notifyListeners();
    await _saveDaily();
    return true;
  }

  Future<void> toggleTask(ChecklistItem task) async {
    if (!_tasks.contains(task) || task.archived || task.roadmapLinked) return;
    if (task.repeats) {
      if (!task.occursOn(today)) return;
      if (task.completedOccurrences.contains(today)) {
        task.completedOccurrences.remove(today);
      } else if (task.completedDay == today) {
        task.completedDay = null;
      } else {
        task.completedOccurrences.add(today);
        task.completedOccurrences.sort();
      }
    } else {
      task.completedDay = task.completedDay == null ? today : null;
    }
    notifyListeners();
    await _saveDaily();
  }

  Future<bool> deferTaskUntilTomorrow(ChecklistItem task) async {
    if (!_tasks.contains(task) ||
        task.archived ||
        task.repeats ||
        task.completedDay != null) {
      return false;
    }
    final fromDay = task.scheduledDay ?? today;
    final now = DateTime.now();
    final tomorrow = dayKey(DateTime(now.year, now.month, now.day + 1));
    final moved = await updateTask(
      task,
      task.title,
      scheduledDay: tomorrow,
      scheduledTime: task.scheduledTime,
    );
    if (!moved) return false;
    if (fromDay == today && !task.movedOccurrences.containsKey(fromDay)) {
      task.movedOccurrences[fromDay] = tomorrow;
      notifyListeners();
      await _saveDaily();
    }
    return true;
  }

  Future<bool> skipTaskOccurrence(ChecklistItem task, String day) async {
    if (!_tasks.contains(task) ||
        task.archived ||
        !task.repeats ||
        !validDailyKey(day) ||
        day.compareTo(today) < 0 ||
        !task.occursOn(day) ||
        task.wasCompletedOn(day)) {
      return false;
    }
    task.skippedOccurrences.add(day);
    task.skippedOccurrences.sort();
    notifyListeners();
    await _saveDaily();
    return true;
  }

  Future<bool> moveTaskOccurrence(
    ChecklistItem task,
    String fromDay,
    String toDay,
  ) async {
    if (!_tasks.contains(task) ||
        task.archived ||
        !task.repeats ||
        !validDailyKey(fromDay) ||
        !validDailyKey(toDay) ||
        fromDay.compareTo(today) < 0 ||
        toDay.compareTo(today) < 0 ||
        fromDay == toDay ||
        !task.occursOn(fromDay) ||
        task.wasCompletedOn(fromDay)) {
      return false;
    }
    final original =
        task.movedOccurrences.entries
            .where((entry) => entry.value == fromDay)
            .map((entry) => entry.key)
            .firstOrNull ??
        fromDay;
    task.movedOccurrences[original] = toDay;
    notifyListeners();
    await _saveDaily();
    return true;
  }

  Future<void> restoreTaskOccurrence(ChecklistItem task, String day) async {
    if (!_tasks.contains(task) || !task.repeats) return;
    final removedSkip = task.skippedOccurrences.remove(day);
    final removedMove = task.movedOccurrences.remove(day) != null;
    if (!removedSkip && !removedMove) return;
    notifyListeners();
    await _saveDaily();
  }

  Future<void> deleteTask(ChecklistItem task) async {
    if (!_tasks.remove(task)) return;
    notifyListeners();
    await _saveDaily();
  }

  Future<void> setTaskArchived(ChecklistItem task, bool archived) async {
    if (!_tasks.contains(task) ||
        (!task.repeats && task.completedDay != null)) {
      return;
    }
    task.archived = archived;
    if (task.roadmapLinked) _reconcileRoadmapTasks();
    notifyListeners();
    await _saveDaily();
  }

  static bool _validRepeat(String pattern, List<int> weekdays, int interval) =>
      {'none', 'daily', 'weekly', 'interval'}.contains(pattern) &&
      weekdays.length <= 7 &&
      weekdays.toSet().length == weekdays.length &&
      weekdays.every((day) => day >= 1 && day <= 7) &&
      (pattern != 'weekly' || weekdays.isNotEmpty) &&
      interval >= 2 &&
      interval <= 30;

  static bool _validTaskCategory(
    String priority,
    List<String> tags,
    String? goalId,
  ) =>
      {'low', 'normal', 'high'}.contains(priority) &&
      tags.length <= 3 &&
      tags.every(
        (tag) => tag.isNotEmpty && tag.length <= 24 && tag.trim() == tag,
      ) &&
      tags.map((tag) => tag.toLowerCase()).toSet().length == tags.length &&
      (goalId == null || (goalId.isNotEmpty && goalId.length <= 120));

  Future<bool> addTaskStep(ChecklistItem task, String title) async {
    final value = title.trim();
    if (!_tasks.contains(task) ||
        task.archived ||
        value.isEmpty ||
        value.length > 120 ||
        task.steps.length >= 20) {
      return false;
    }
    task.steps.add(
      ChecklistStep(
        id: _freshDailyId('step', task.steps.map((step) => step.id).toSet()),
        title: value,
      ),
    );
    notifyListeners();
    await _saveDaily();
    return true;
  }

  Future<void> toggleTaskStep(ChecklistItem task, ChecklistStep step) async {
    if (!_tasks.contains(task) || task.archived || !task.steps.contains(step)) {
      return;
    }
    if (task.repeats) {
      if (!task.occursOn(today)) return;
      if (step.completedDays.contains(today)) {
        step.completedDays.remove(today);
      } else {
        step.completedDays.add(today);
        step.completedDays.sort();
      }
    } else {
      step.completed = !step.completed;
    }
    notifyListeners();
    await _saveDaily();
  }

  Future<void> deleteTaskStep(ChecklistItem task, ChecklistStep step) async {
    if (!_tasks.contains(task) || !task.steps.remove(step)) return;
    notifyListeners();
    await _saveDaily();
  }

  Future<bool> addNote(String day, String text) async {
    final value = text.trim();
    if (!validDailyKey(day) ||
        value.isEmpty ||
        value.length > 1000 ||
        _notes.length >= 1000) {
      return false;
    }
    _notes.add(
      DailyNote(
        id: _freshDailyId('note', _notes.map((note) => note.id).toSet()),
        day: day,
        text: value,
      ),
    );
    notifyListeners();
    await _saveDaily();
    return true;
  }

  Future<bool> updateNote(DailyNote note, String day, String text) async {
    final value = text.trim();
    if (!_notes.contains(note) ||
        !validDailyKey(day) ||
        value.isEmpty ||
        value.length > 1000) {
      return false;
    }
    note.day = day;
    note.text = value;
    notifyListeners();
    await _saveDaily();
    return true;
  }

  Future<void> deleteNote(DailyNote note) async {
    if (!_notes.remove(note)) return;
    notifyListeners();
    await _saveDaily();
  }

  Future<void> _saveDaily({List<ChecklistItem>? tasks}) async {
    await _prefs.setString(
      _dailyStorageKey,
      jsonEncode({
        'tasks': (tasks ?? _tasks).map((task) => task.toJson()).toList(),
        'notes': _notes.map((note) => note.toJson()).toList(),
      }),
    );
  }

  int get todayDone => goals.where((goal) => goal.isDoneOn(today)).length;

  int get todayRest =>
      goals.where((goal) => goal.restDays.contains(today)).length;

  String get guardianReaction {
    final taskDoneToday = _tasks.any(
      (task) =>
          !task.roadmapLinked &&
          (task.repeats
              ? task.wasCompletedOn(today)
              : task.completedDay == today),
    );
    if (goals.isEmpty && !taskDoneToday) return '첫 목표부터 함께 시작해요.';
    if (goals.isEmpty) return '오늘의 할 일을 해냈어요!';
    if (todayDone == goals.length && taskDoneToday) {
      return '목표와 할 일을 모두 해냈어요!';
    }
    if (todayDone == goals.length) return '오늘의 실천을 모두 해냈어요!';
    if (todayDone > 0 && taskDoneToday) return '목표도 할 일도 한 걸음 해냈어요.';
    if (todayDone > 0) return '오늘도 한 걸음 자랐어요.';
    if (taskDoneToday) return '오늘의 할 일을 하나 해냈어요!';
    if (todayRest == goals.length) return '오늘은 함께 쉬어 가요.';
    if (todayRest > 0) return '쉬어도 괜찮아요. 곁에 있을게요.';
    return '작은 한 걸음부터 시작해요.';
  }

  int completedDaysThisWeek(GrowthGoal goal, {DateTime? on}) {
    final weekStart = startOfWeek(on ?? DateTime.now());
    final nextWeek = weekStart.add(const Duration(days: 7));
    return goal.completions.keys.where((key) {
      final date = DateTime.tryParse(key);
      if (date == null) return false;
      final day = DateTime.utc(date.year, date.month, date.day);
      return !day.isBefore(weekStart) && day.isBefore(nextWeek);
    }).length;
  }

  List<WeeklyActivity> recentWeeks(
    GrowthGoal goal, {
    DateTime? on,
    int count = 4,
  }) {
    final currentStart = startOfWeek(on ?? DateTime.now());
    return List.generate(count, (index) {
      final start = currentStart.subtract(
        Duration(days: (count - 1 - index) * 7),
      );
      return (
        start: start,
        completedDays: completedDaysThisWeek(goal, on: start),
      );
    });
  }

  List<GoalActivity> recentActivity(GrowthGoal goal, {int limit = 30}) {
    final entries = <GoalActivity>[];
    for (final entry in goal.completions.entries) {
      final date = DateTime.tryParse(entry.key);
      if (date != null) {
        entries.add((
          date: date,
          level: entry.value,
          action: goal.completionActions[entry.key],
        ));
      }
    }
    for (final key in goal.restDays) {
      if (goal.completions.containsKey(key)) continue;
      final date = DateTime.tryParse(key);
      if (date != null) entries.add((date: date, level: '쉼', action: null));
    }
    entries.sort((a, b) => b.date.compareTo(a.date));
    return entries.take(limit).toList();
  }

  int? daysSinceLastPractice(GrowthGoal goal, {DateTime? on}) {
    if (goal.completions.isEmpty) return null;
    final date = on ?? DateTime.now();
    final todayDate = DateTime.utc(date.year, date.month, date.day);
    final lastDay = goal.completions.keys
        .map(DateTime.tryParse)
        .whereType<DateTime>()
        .map((day) => DateTime.utc(day.year, day.month, day.day))
        .fold<DateTime?>(
          null,
          (latest, day) => latest == null || day.isAfter(latest) ? day : latest,
        );
    if (lastDay == null) return null;
    return todayDate.difference(lastDay).inDays;
  }

  int get totalCompletedDays =>
      _goals.fold(0, (total, goal) => total + goal.completedDays);

  int get maxCompletions => countIntensity('MAX');

  int countIntensity(String level) {
    final legacy = switch (level) {
      'MINI' => '쉬움',
      'MORE' => '보통',
      'MAX' => '도전',
      _ => level,
    };
    return _goals.fold(
      0,
      (total, goal) =>
          total +
          goal.completions.values
              .where((value) => value == level || value == legacy)
              .length,
    );
  }

  int get completedMilestoneCount =>
      _goals.fold(0, (total, goal) => total + goal.completedMilestones.length);

  int get activeDays =>
      _goals.expand((goal) => goal.completions.keys).toSet().length;

  static const experiencePerLevel = 60;

  int get experience => _goals.fold(
    0,
    (total, goal) =>
        total +
        goal.completions.values.fold(
          0,
          (sum, level) => sum + RewardRules.goalExperience(level),
        ),
  );

  int get level => 1 + experience ~/ experiencePerLevel;
  int get experienceInLevel => experience % experiencePerLevel;

  int get guardianStage {
    if (activeDays >= 15) return 2;
    if (activeDays >= 5) return 1;
    return 0;
  }

  Future<void> load() async {
    _darkTheme = await _prefs.getBool(_darkThemeKey) ?? false;
    _showGameRewards = await _prefs.getBool(_showGameRewardsKey) ?? true;
    _quietEnabled = await _prefs.getBool(_quietEnabledKey) ?? false;
    final savedQuietStart = await _prefs.getString(_quietStartKey);
    final savedQuietEnd = await _prefs.getString(_quietEndKey);
    if (savedQuietStart != null && validTaskTime(savedQuietStart)) {
      _quietStart = savedQuietStart;
    }
    if (savedQuietEnd != null && validTaskTime(savedQuietEnd)) {
      _quietEnd = savedQuietEnd;
    }
    final savedName = await _prefs.getString(_guardianNameKey);
    if (savedName != null && savedName.trim().isNotEmpty) {
      _guardianName = savedName.trim();
    }
    final dailyRaw = await _prefs.getString(_dailyStorageKey);
    if (dailyRaw != null) {
      try {
        final daily = Map<String, dynamic>.from(jsonDecode(dailyRaw) as Map);
        final tasks = (daily['tasks'] as List)
            .map(
              (item) => ChecklistItem.fromJson(
                Map<String, dynamic>.from(item as Map),
              ),
            )
            .toList();
        final notes = (daily['notes'] as List)
            .map(
              (item) =>
                  DailyNote.fromJson(Map<String, dynamic>.from(item as Map)),
            )
            .toList();
        _tasks
          ..clear()
          ..addAll(tasks);
        _notes
          ..clear()
          ..addAll(notes);
      } catch (error) {
        debugPrint('Could not load daily content: $error');
      }
    }
    final raw = await _prefs.getString(_storageKey);
    if (raw == null) {
      notifyListeners();
      return;
    }
    try {
      final data = jsonDecode(raw) as List<dynamic>;
      _goals
        ..clear()
        ..addAll(
          data.map(
            (item) =>
                GrowthGoal.fromJson(Map<String, dynamic>.from(item as Map)),
          ),
        );
      if (_reconcileRoadmapTasks()) await _saveDaily();
      notifyListeners();
    } catch (error) {
      debugPrint('Could not load local goals: $error');
    }
  }

  Future<bool> addGoal({
    required String title,
    required String mini,
    required String more,
    required String max,
    required String path,
    int? weeklyTarget,
    required List<String> milestones,
    List<MilestoneDetail>? milestoneDetails,
    String currentLevel = '',
    String? startDate,
    String? targetDate,
    int? weeklyMinutes,
    RoadmapPlan? selectedPlan,
  }) async {
    if (goals.length >= 5) return false;
    if (milestoneDetails != null &&
        milestoneDetails.length != milestones.length) {
      return false;
    }
    selectedPlan?.validate();
    final goalStart = startDate ?? dayKey(DateTime.now());
    if (!validDailyKey(goalStart) ||
        (targetDate != null &&
            (!validDailyKey(targetDate) ||
                goalStart.compareTo(targetDate) > 0))) {
      return false;
    }
    _goals.add(
      GrowthGoal(
        id: DateTime.now().microsecondsSinceEpoch.toString(),
        title: title.trim(),
        mini: mini.trim(),
        more: more.trim(),
        max: max.trim(),
        path: path,
        weeklyTarget: (weeklyTarget ?? suggestedWeeklyTarget(path)).clamp(1, 7),
        milestones: milestones,
        milestoneDetails: milestoneDetails,
        createdAt: DateTime.now(),
        currentLevel: currentLevel.trim(),
        startDate: goalStart,
        targetDate: targetDate,
        weeklyMinutes: weeklyMinutes,
        selectedPlan: selectedPlan,
      ),
    );
    notifyListeners();
    await _save();
    return true;
  }

  Future<void> complete(GrowthGoal goal, String intensity) async {
    if (goal.archived) return;
    await setPracticeOn(goal, today, intensity);
  }

  /// Correct a dated practice record. Game rewards use a stable goal/day ID,
  /// so changing intensity never creates a second grant for the same day.
  Future<bool> setPracticeOn(
    GrowthGoal goal,
    String day,
    String? intensity,
  ) async {
    if (!_goals.contains(goal) ||
        !validDailyKey(day) ||
        day.compareTo(today) > 0 ||
        (day.compareTo(goal.startDay) < 0 && !goal.isDoneOn(day)) ||
        (intensity != null && !{'MINI', 'MORE', 'MAX'}.contains(intensity))) {
      return false;
    }
    if (goal.completions[day] == intensity &&
        (intensity == null || !goal.restDays.contains(day))) {
      return true;
    }
    if (intensity == null) {
      goal.completions.remove(day);
      goal.completionActions.remove(day);
    } else {
      goal.restDays.remove(day);
      goal.completions[day] = intensity;
      final action = switch (intensity) {
        'MINI' => goal.mini,
        'MORE' => goal.more,
        'MAX' => goal.max,
        _ => null,
      };
      if (action != null) goal.completionActions[day] = action;
    }
    final linkedChanged = _reconcileRoadmapTasks();
    notifyListeners();
    await _save();
    if (linkedChanged) await _saveDaily();
    return true;
  }

  Future<void> undo(GrowthGoal goal) async {
    await setPracticeOn(goal, today, null);
  }

  bool _reconcileRoadmapTasks() {
    var changed = false;
    for (final task in _tasks) {
      if (!task.roadmapLinked || task.archived) continue;
      final goal = goalById(task.goalId!);
      if (goal == null) continue;
      final day = task.scheduledDay!;
      final expected = goal.isDoneOn(day) ? day : null;
      if (task.completedDay == expected) continue;
      task.completedDay = expected;
      changed = true;
    }
    return changed;
  }

  Future<void> rest(GrowthGoal goal) async {
    if (!_goals.contains(goal) || goal.archived || goal.isDoneOn(today)) return;
    goal.restDays.add(today);
    notifyListeners();
    await _save();
  }

  Future<void> clearRest(GrowthGoal goal) async {
    if (!_goals.contains(goal)) return;
    goal.restDays.remove(today);
    notifyListeners();
    await _save();
  }

  Future<void> archiveGoal(GrowthGoal goal) async {
    goal.archived = true;
    notifyListeners();
    await _save();
  }

  Future<bool> restoreGoal(GrowthGoal goal) async {
    if (goals.length >= 5) return false;
    goal.archived = false;
    goal.localBackup = false;
    notifyListeners();
    await _save();
    return true;
  }

  Future<void> toggleMilestone(GrowthGoal goal, int index) async {
    if (!_goals.contains(goal) ||
        index < 0 ||
        index >= goal.milestones.length) {
      return;
    }
    if (!goal.completedMilestones.add(index)) {
      goal.completedMilestones.remove(index);
    }
    notifyListeners();
    await _save();
  }

  Future<bool> addMilestone(
    GrowthGoal goal,
    String title, {
    MilestoneDetail detail = const MilestoneDetail(),
  }) async {
    final value = title.trim();
    if (!_goals.contains(goal) || goal.archived || value.isEmpty) return false;
    goal.milestones.add(value);
    goal.milestoneDetails.add(detail);
    notifyListeners();
    await _save();
    return true;
  }

  Future<bool> updateMilestone(
    GrowthGoal goal,
    int index,
    String title, {
    MilestoneDetail? detail,
  }) async {
    final value = title.trim();
    if (!_goals.contains(goal) ||
        goal.archived ||
        index < 0 ||
        index >= goal.milestones.length ||
        value.isEmpty) {
      return false;
    }
    goal.milestones[index] = value;
    if (detail != null) goal.milestoneDetails[index] = detail;
    notifyListeners();
    await _save();
    return true;
  }

  Future<bool> removeMilestone(GrowthGoal goal, int index) async {
    if (!_goals.contains(goal) ||
        goal.archived ||
        index < 0 ||
        index >= goal.milestones.length) {
      return false;
    }
    goal.milestones.removeAt(index);
    goal.milestoneDetails.removeAt(index);
    final shifted = goal.completedMilestones
        .where((completed) => completed != index)
        .map((completed) => completed > index ? completed - 1 : completed)
        .toSet();
    goal.completedMilestones
      ..clear()
      ..addAll(shifted);
    notifyListeners();
    await _save();
    return true;
  }

  Future<void> updateGoalActions(
    GrowthGoal goal, {
    required String mini,
    required String more,
    required String max,
  }) async {
    if (!_goals.contains(goal)) return;
    if (mini.trim().isEmpty || more.trim().isEmpty || max.trim().isEmpty) {
      return;
    }
    goal.mini = mini.trim();
    goal.more = more.trim();
    goal.max = max.trim();
    notifyListeners();
    await _save();
  }

  Future<bool> updateGoalSettings(
    GrowthGoal goal, {
    required String title,
    required String path,
    required int weeklyTarget,
    String? currentLevel,
    String? startDate,
    String? targetDate,
    int? weeklyMinutes,
  }) async {
    final value = title.trim();
    if (!_goals.contains(goal) ||
        goal.archived ||
        value.isEmpty ||
        weeklyTarget < 1 ||
        weeklyTarget > 7) {
      return false;
    }
    if (weeklyMinutes != null &&
        weeklyMinutes != 0 &&
        (weeklyMinutes < 1 || weeklyMinutes > 10080)) {
      return false;
    }
    final nextStart = startDate ?? goal.startDay;
    final nextEnd = targetDate == null
        ? goal.targetDate
        : targetDate.isEmpty
        ? null
        : targetDate;
    if (!validDailyKey(nextStart) ||
        (nextEnd != null &&
            (!validDailyKey(nextEnd) || nextStart.compareTo(nextEnd) > 0))) {
      return false;
    }
    goal.title = value;
    goal.path = path;
    goal.weeklyTarget = weeklyTarget;
    if (currentLevel != null) goal.currentLevel = currentLevel.trim();
    if (startDate != null) goal.startDate = startDate;
    if (targetDate != null) {
      goal.targetDate = targetDate.isEmpty ? null : targetDate;
    }
    if (weeklyMinutes != null) {
      goal.weeklyMinutes = weeklyMinutes == 0 ? null : weeklyMinutes;
    }
    notifyListeners();
    await _save();
    return true;
  }

  Future<void> setGuardianName(String name) async {
    final value = name.trim();
    if (value.isEmpty) return;
    _guardianName = value;
    notifyListeners();
    await _prefs.setString(_guardianNameKey, value);
  }

  Future<void> _save() async {
    await _prefs.setString(
      _storageKey,
      jsonEncode(_goals.map((goal) => goal.toJson()).toList()),
    );
  }
}

String dayKey(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-'
    '${date.month.toString().padLeft(2, '0')}-'
    '${date.day.toString().padLeft(2, '0')}';

DateTime startOfWeek(DateTime date) => DateTime.utc(
  date.year,
  date.month,
  date.day,
).subtract(Duration(days: date.weekday - DateTime.monday));
