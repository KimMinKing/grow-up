import 'dart:convert';

import '../models/growth_goal.dart';
import '../models/daily_content.dart';
import '../models/game_snapshot.dart';

class GrowthBackup {
  const GrowthBackup({
    required this.goals,
    required this.guardianName,
    required this.darkTheme,
    this.tasks = const [],
    this.notes = const [],
    this.game,
  });

  static const maxBytes = 2 * 1024 * 1024;
  final List<GrowthGoal> goals;
  final String guardianName;
  final bool darkTheme;
  final List<ChecklistItem> tasks;
  final List<DailyNote> notes;
  final GameSnapshot? game;

  GrowthBackup withGame(GameSnapshot? snapshot) => GrowthBackup(
    goals: goals,
    guardianName: guardianName,
    darkTheme: darkTheme,
    tasks: tasks,
    notes: notes,
    game: snapshot,
  );

  String encode() => jsonEncode({
    'format': 'growup-backup',
    'version': 3,
    'exportedAt': DateTime.now().toUtc().toIso8601String(),
    'guardianName': guardianName,
    'darkTheme': darkTheme,
    'goals': goals.map((goal) => goal.toJson()).toList(),
    'tasks': tasks.map((task) => task.toJson()).toList(),
    'notes': notes.map((note) => note.toJson()).toList(),
    'game': game?.toJson(),
  });

  static GrowthBackup decode(String text) {
    if (utf8.encode(text).length > maxBytes) {
      throw const FormatException('백업 파일이 너무 커요.');
    }
    try {
      final data = jsonDecode(text);
      if (data is! Map ||
          data['format'] != 'growup-backup' ||
          !{1, 2, 3}.contains(data['version']) ||
          data['guardianName'] is! String ||
          (data['guardianName'] as String).trim().isEmpty ||
          (data['guardianName'] as String).length > 80 ||
          data['darkTheme'] is! bool ||
          data['goals'] is! List ||
          (data['goals'] as List).length > 1000 ||
          (data['version'] >= 2 &&
              (data['tasks'] is! List ||
                  data['notes'] is! List ||
                  (data['tasks'] as List).length > 1000 ||
                  (data['notes'] as List).length > 1000)) ||
          (data['version'] == 3 && !data.containsKey('game'))) {
        throw const FormatException('전설키우기 백업 형식을 확인해 주세요.');
      }
      final ids = <String>{};
      final goals = <GrowthGoal>[];
      for (final item in data['goals'] as List) {
        if (item is! Map) throw const FormatException('목표 자료가 올바르지 않아요.');
        final json = Map<String, dynamic>.from(item);
        final goal = decodeGoal(json);
        if (!ids.add(goal.id)) {
          throw const FormatException('목표 자료가 올바르지 않아요.');
        }
        goals.add(goal);
      }
      final taskIds = <String>{};
      final tasks = <ChecklistItem>[];
      for (final item in data['tasks'] as List? ?? const []) {
        final task = ChecklistItem.fromJson(
          Map<String, dynamic>.from(item as Map),
        );
        if (!taskIds.add(task.id)) {
          throw const FormatException('할 일 자료가 올바르지 않아요.');
        }
        tasks.add(task);
      }
      final noteIds = <String>{};
      final notes = <DailyNote>[];
      for (final item in data['notes'] as List? ?? const []) {
        final note = DailyNote.fromJson(Map<String, dynamic>.from(item as Map));
        if (!noteIds.add(note.id)) {
          throw const FormatException('메모 자료가 올바르지 않아요.');
        }
        notes.add(note);
      }
      return GrowthBackup(
        goals: goals,
        guardianName: (data['guardianName'] as String).trim(),
        darkTheme: data['darkTheme'] as bool,
        tasks: tasks,
        notes: notes,
        game: data['version'] == 3 && data['game'] != null
            ? GameSnapshot.fromJson(
                Map<String, dynamic>.from(data['game'] as Map),
              )
            : null,
      );
    } on FormatException {
      rethrow;
    } catch (_) {
      throw const FormatException('전설키우기 백업 형식을 확인해 주세요.');
    }
  }

  static GrowthGoal decodeGoal(Map<String, dynamic> json) {
    try {
      final weeklyTarget = json['weeklyTarget'];
      final weeklyMinutes = json['weeklyMinutes'];
      final targetDate = json['targetDate'];
      final startDate = json['startDate'];
      if (weeklyTarget is! int ||
          weeklyTarget < 1 ||
          weeklyTarget > 7 ||
          (weeklyMinutes != null &&
              (weeklyMinutes is! int ||
                  weeklyMinutes < 0 ||
                  weeklyMinutes > 10080)) ||
          (targetDate != null &&
              (targetDate is! String || !_validDay(targetDate))) ||
          (startDate != null &&
              (startDate is! String || !_validDay(startDate))) ||
          (startDate is String &&
              targetDate is String &&
              startDate.compareTo(targetDate) > 0)) {
        throw const FormatException('목표 자료가 올바르지 않아요.');
      }
      final goal = GrowthGoal.fromJson(json);
      if (goal.id.isEmpty ||
          goal.id.length > 80 ||
          goal.title.trim().isEmpty ||
          goal.title.length > 160 ||
          [
            goal.mini,
            goal.more,
            goal.max,
          ].any((value) => value.trim().isEmpty || value.length > 160) ||
          (json['selectedPlan'] != null && goal.selectedPlan == null) ||
          goal.completedMilestones.any(
            (index) => index < 0 || index >= goal.milestones.length,
          ) ||
          goal.completions.entries.any(
            (entry) =>
                !_validDay(entry.key) ||
                !{
                  'MINI',
                  'MORE',
                  'MAX',
                  '쉬움',
                  '보통',
                  '도전',
                }.contains(entry.value),
          ) ||
          goal.completionActions.entries.any(
            (entry) =>
                !goal.completions.containsKey(entry.key) ||
                entry.value.trim().isEmpty ||
                entry.value.length > 160,
          ) ||
          goal.restDays.any(
            (day) => !_validDay(day) || goal.completions.containsKey(day),
          )) {
        throw const FormatException('목표 자료가 올바르지 않아요.');
      }
      return goal;
    } on FormatException {
      rethrow;
    } catch (_) {
      throw const FormatException('목표 자료가 올바르지 않아요.');
    }
  }

  static bool _validDay(String value) {
    if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(value)) return false;
    final date = DateTime.tryParse(value);
    return date != null &&
        '${date.year.toString().padLeft(4, '0')}-'
                '${date.month.toString().padLeft(2, '0')}-'
                '${date.day.toString().padLeft(2, '0')}' ==
            value;
  }
}

class BackupImportResult {
  const BackupImportResult({
    required this.added,
    required this.skipped,
    required this.archivedCopies,
    required this.settingsRestored,
    this.tasksAdded = 0,
    this.notesAdded = 0,
  });

  final int added;
  final int skipped;
  final int archivedCopies;
  final bool settingsRestored;
  final int tasksAdded;
  final int notesAdded;
}
