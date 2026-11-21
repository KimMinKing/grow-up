import 'daily_content.dart';

typedef RewardCandidate = ({
  String sourceId,
  String kind,
  int trainingPasses,
  int experience,
  String activityDay,
});

/// A real-world completion can have exactly one local game reward.
class RewardGrant {
  const RewardGrant({
    required this.sourceId,
    required this.kind,
    required this.trainingPasses,
    required this.experience,
    required this.grantedAt,
    this.activityDay,
    this.capped = false,
  });

  final String sourceId;
  final String kind;
  final int trainingPasses;
  final int experience;
  final DateTime grantedAt;
  final String? activityDay;
  final bool capped;

  /// Old saves recorded only a credited task ID, without a timestamp.
  factory RewardGrant.fromLegacyTaskId(String sourceId) => RewardGrant(
    sourceId: sourceId,
    kind: RegExp(r':\d{4}-\d{2}-\d{2}$').hasMatch(sourceId)
        ? 'routine'
        : 'task',
    trainingPasses: 2,
    experience: 0,
    grantedAt: DateTime.utc(1970),
  );

  factory RewardGrant.fromJson(Map<String, dynamic> json) {
    final sourceId = json['sourceId'];
    final kind = json['kind'];
    final passes = json['trainingPasses'];
    final experience = json['experience'];
    final at = json['grantedAt'];
    final activityDay = json['activityDay'];
    final capped = json['capped'] ?? false;
    if (sourceId is! String ||
        sourceId.isEmpty ||
        sourceId.length > 150 ||
        !{'task', 'routine', 'mini', 'more', 'max'}.contains(kind) ||
        passes is! int ||
        passes < 0 ||
        passes > 3 ||
        experience is! int ||
        experience < 0 ||
        experience > 30 ||
        at is! String ||
        DateTime.tryParse(at) == null ||
        (activityDay != null &&
            (activityDay is! String || !validDailyKey(activityDay))) ||
        capped is! bool ||
        (capped && activityDay == null)) {
      throw const FormatException('Invalid reward grant');
    }
    final expected = RewardRules.expectedForKind(kind as String);
    if (passes != (capped ? 0 : expected.passes) || experience != expected.xp) {
      throw const FormatException('Invalid reward amount');
    }
    return RewardGrant(
      sourceId: sourceId,
      kind: kind,
      trainingPasses: passes,
      experience: experience,
      grantedAt: DateTime.parse(at).toUtc(),
      activityDay: activityDay as String?,
      capped: capped,
    );
  }

  Map<String, Object?> toJson() => {
    'sourceId': sourceId,
    'kind': kind,
    'trainingPasses': trainingPasses,
    'experience': experience,
    'grantedAt': grantedAt.toUtc().toIso8601String(),
    'activityDay': activityDay,
    if (capped) 'capped': true,
  };
}

/// Provisional balance. XP for goal practice is derived by GrowthStore;
/// this ledger records it for display and auditing without adding it twice.
class RewardRules {
  static const oneOffTrainingPasses = 2;
  static const routineTrainingPasses = 2;
  static const dailyChecklistRewardLimit = 5;
  static const backfillDays = 14;

  static ({int passes, int xp}) expectedForKind(String kind) => switch (kind) {
    'task' || 'routine' => (passes: 2, xp: 0),
    'mini' => (passes: 1, xp: 10),
    'more' => (passes: 2, xp: 20),
    'max' => (passes: 3, xp: 30),
    _ => (passes: -1, xp: -1),
  };

  static int goalExperience(String intensity) => switch (intensity) {
    'MINI' || '쉬움' => 10,
    'MORE' || '보통' => 20,
    'MAX' || '도전' => 30,
    _ => 0,
  };

  static int goalTrainingPasses(String intensity) => switch (intensity) {
    'MINI' || '쉬움' => 1,
    'MORE' || '보통' => 2,
    'MAX' || '도전' => 3,
    _ => 0,
  };

  static String? goalKind(String intensity) => switch (intensity) {
    'MINI' || '쉬움' => 'mini',
    'MORE' || '보통' => 'more',
    'MAX' || '도전' => 'max',
    _ => null,
  };
}
