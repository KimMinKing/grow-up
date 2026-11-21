import 'daily_content.dart';

class DailySnapshot {
  DailySnapshot({required this.tasks, required this.notes});

  final List<ChecklistItem> tasks;
  final List<DailyNote> notes;

  factory DailySnapshot.fromJson(Map<String, dynamic> json) {
    try {
      if (json['version'] != 1 ||
          json['tasks'] is! List ||
          json['notes'] is! List ||
          (json['tasks'] as List).length > 1000 ||
          (json['notes'] as List).length > 1000) {
        throw const FormatException('할 일·메모 자료가 올바르지 않아요.');
      }
      final tasks = (json['tasks'] as List)
          .map(
            (item) =>
                ChecklistItem.fromJson(Map<String, dynamic>.from(item as Map)),
          )
          .toList();
      final notes = (json['notes'] as List)
          .map(
            (item) =>
                DailyNote.fromJson(Map<String, dynamic>.from(item as Map)),
          )
          .toList();
      if (tasks.map((item) => item.id).toSet().length != tasks.length ||
          notes.map((item) => item.id).toSet().length != notes.length) {
        throw const FormatException('할 일·메모 자료가 올바르지 않아요.');
      }
      return DailySnapshot(tasks: tasks, notes: notes);
    } on FormatException {
      rethrow;
    } catch (_) {
      throw const FormatException('할 일·메모 자료가 올바르지 않아요.');
    }
  }

  Map<String, dynamic> toJson() => {
    'version': 1,
    'tasks': tasks.map((task) => task.toJson()).toList(),
    'notes': notes.map((note) => note.toJson()).toList(),
  };

  bool get isEmpty => tasks.isEmpty && notes.isEmpty;
}
