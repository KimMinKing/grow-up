import '../models/daily_content.dart';
import '../models/growth_goal.dart';
import 'growth_store.dart';

class WeeklyStatistics {
  const WeeklyStatistics({
    required this.start,
    required this.oneOffDone,
    required this.repeatDone,
    required this.goalPractices,
    required this.postponed,
    required this.restartDays,
  });

  final DateTime start;
  final int oneOffDone;
  final int repeatDone;
  final int goalPractices;
  final int postponed;
  final List<String> restartDays;

  static DateTime mondayOf(DateTime date) =>
      DateTime.utc(date.year, date.month, date.day - (date.weekday - 1));

  static WeeklyStatistics calculate({
    required DateTime week,
    required Iterable<GrowthGoal> goals,
    required Iterable<ChecklistItem> tasks,
  }) {
    final start = mondayOf(week);
    final end = start.add(const Duration(days: 6));
    final from = dayKey(start);
    final through = dayKey(end);
    bool inside(String day) =>
        day.compareTo(from) >= 0 && day.compareTo(through) <= 0;

    var oneOffDone = 0;
    var repeatDone = 0;
    var postponed = 0;
    for (final task in tasks) {
      if (task.roadmapLinked) continue;
      if (task.repeats) {
        repeatDone += task.completedOccurrences.where(inside).length;
      } else if (task.completedDay != null && inside(task.completedDay!)) {
        oneOffDone++;
      }
      postponed += task.movedOccurrences.keys.where(inside).length;
    }

    var goalPractices = 0;
    final restartDays = <String>{};
    for (final goal in goals) {
      final days = goal.completions.keys.toList()..sort();
      String? previous;
      for (final day in days) {
        if (inside(day)) goalPractices++;
        if (previous != null &&
            inside(day) &&
            DateTime.parse('${day}T00:00:00Z')
                    .difference(DateTime.parse('${previous}T00:00:00Z'))
                    .inDays >=
                3) {
          restartDays.add(day);
        }
        previous = day;
      }
    }
    return WeeklyStatistics(
      start: start,
      oneOffDone: oneOffDone,
      repeatDone: repeatDone,
      goalPractices: goalPractices,
      postponed: postponed,
      restartDays: restartDays.toList()..sort(),
    );
  }
}

class WeeklyGoalReview {
  const WeeklyGoalReview({
    required this.goal,
    required this.practiceDays,
    required this.restDays,
    required this.levels,
  });

  final GrowthGoal goal;
  final List<String> practiceDays;
  final int restDays;
  final Map<String, int> levels;

  static List<WeeklyGoalReview> calculate(
    DateTime week,
    Iterable<GrowthGoal> goals,
  ) {
    final start = dayKey(WeeklyStatistics.mondayOf(week));
    final end = dayKey(
      WeeklyStatistics.mondayOf(week).add(const Duration(days: 6)),
    );
    bool inside(String day) =>
        day.compareTo(start) >= 0 && day.compareTo(end) <= 0;
    return [
      for (final goal in goals)
        if ((goal.startDate ?? dayKey(goal.createdAt)).compareTo(end) <= 0 &&
            (!goal.archived ||
                goal.completions.keys.any(inside) ||
                goal.restDays.any(inside)))
          WeeklyGoalReview(
            goal: goal,
            practiceDays: goal.completions.keys.where(inside).toList()..sort(),
            restDays: goal.restDays.where(inside).length,
            levels: {
              for (final level in ['MINI', 'MORE', 'MAX'])
                level: goal.completions.entries
                    .where(
                      (entry) =>
                          inside(entry.key) &&
                          (entry.value == level ||
                              entry.value ==
                                  switch (level) {
                                    'MINI' => '쉬움',
                                    'MORE' => '보통',
                                    _ => '도전',
                                  }),
                    )
                    .length,
            },
          ),
    ];
  }
}
