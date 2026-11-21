import 'roadmap_plan.dart';
import 'daily_content.dart';

class MilestoneDetail {
  const MilestoneDetail({
    this.targetDate,
    this.criteria = '',
    this.method = '',
    this.rewardIdea = '',
  });

  final String? targetDate;
  final String criteria;
  final String method;
  final String rewardIdea;

  Map<String, dynamic> toJson() => {
    'targetDate': targetDate,
    'criteria': criteria,
    'method': method,
    if (rewardIdea.isNotEmpty) 'rewardIdea': rewardIdea,
  };

  factory MilestoneDetail.fromJson(Map<String, dynamic> json) {
    final targetDate = json['targetDate'];
    final criteria = json['criteria'] ?? '';
    final method = json['method'] ?? '';
    final rewardIdea = json['rewardIdea'] ?? '';
    if ((targetDate != null &&
            (targetDate is! String || !validDailyKey(targetDate))) ||
        criteria is! String ||
        criteria.length > 160 ||
        method is! String ||
        method.length > 300 ||
        rewardIdea is! String ||
        rewardIdea.length > 120) {
      throw const FormatException('로드맵 단계 정보가 올바르지 않아요.');
    }
    return MilestoneDetail(
      targetDate: targetDate as String?,
      criteria: criteria.trim(),
      method: method.trim(),
      rewardIdea: rewardIdea.trim(),
    );
  }
}

class GrowthGoal {
  GrowthGoal({
    required this.id,
    required this.title,
    required this.mini,
    required this.more,
    required this.max,
    required this.path,
    required this.weeklyTarget,
    required this.milestones,
    List<MilestoneDetail>? milestoneDetails,
    required this.createdAt,
    this.currentLevel = '',
    this.startDate,
    this.targetDate,
    this.weeklyMinutes,
    this.selectedPlan,
    Map<String, String>? completions,
    Map<String, String>? completionActions,
    Set<String>? restDays,
    Set<int>? completedMilestones,
    this.archived = false,
    this.localBackup = false,
  }) : milestoneDetails = List.generate(
         milestones.length,
         (index) => index < (milestoneDetails?.length ?? 0)
             ? milestoneDetails![index]
             : const MilestoneDetail(),
       ),
       completions = completions ?? {},
       completionActions = completionActions ?? {},
       restDays = restDays ?? {},
       completedMilestones = completedMilestones ?? {};

  final String id;
  String title;
  String mini;
  String more;
  String max;
  String path;
  int weeklyTarget;
  final List<String> milestones;
  final List<MilestoneDetail> milestoneDetails;
  final DateTime createdAt;
  String currentLevel;
  String? startDate;
  String? targetDate;
  int? weeklyMinutes;
  final RoadmapPlan? selectedPlan;
  final Map<String, String> completions;
  final Map<String, String> completionActions;
  final Set<String> restDays;
  final Set<int> completedMilestones;
  bool archived;
  bool localBackup;

  bool isDoneOn(String day) => completions.containsKey(day);

  int get completedDays => completions.length;

  String get startDay {
    if (startDate != null) return startDate!;
    final date = createdAt.toLocal();
    return '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'mini': mini,
    'more': more,
    'max': max,
    'path': path,
    'weeklyTarget': weeklyTarget,
    'milestones': milestones,
    'milestoneDetails': milestoneDetails
        .map((detail) => detail.toJson())
        .toList(),
    'createdAt': createdAt.toIso8601String(),
    'currentLevel': currentLevel,
    if (startDate != null) 'startDate': startDate,
    'targetDate': targetDate,
    'weeklyMinutes': weeklyMinutes,
    'selectedPlan': selectedPlan?.toJson(),
    'completions': completions,
    'completionActions': completionActions,
    'restDays': restDays.toList(),
    'completedMilestones': completedMilestones.toList(),
    'archived': archived,
    if (localBackup) 'localBackup': true,
  };

  factory GrowthGoal.fromJson(Map<String, dynamic> json) => GrowthGoal(
    id: json['id'] as String,
    title: json['title'] as String,
    mini: json['mini'] as String,
    more: json['more'] as String,
    max: json['max'] as String,
    path: json['path'] as String,
    weeklyTarget:
        ((json['weeklyTarget'] as num?)?.toInt() ??
                suggestedWeeklyTarget(json['path'] as String))
            .clamp(1, 7),
    milestones: (json['milestones'] as List<dynamic>? ?? [])
        .map((item) => item as String)
        .toList(),
    milestoneDetails: _readMilestoneDetails(json),
    createdAt: DateTime.parse(json['createdAt'] as String),
    currentLevel: json['currentLevel'] as String? ?? '',
    startDate: json['startDate'] as String?,
    targetDate: json['targetDate'] as String?,
    weeklyMinutes: (json['weeklyMinutes'] as num?)?.toInt(),
    selectedPlan: RoadmapPlan.tryFromJson(json['selectedPlan']),
    completedMilestones: (json['completedMilestones'] as List<dynamic>? ?? [])
        .map((item) => item as int)
        .toSet(),
    archived: json['archived'] as bool? ?? false,
    localBackup: json['localBackup'] as bool? ?? false,
    completions: (json['completions'] as Map<String, dynamic>? ?? {}).map(
      (key, value) => MapEntry(key, value as String),
    ),
    completionActions:
        (json['completionActions'] as Map<String, dynamic>? ?? {}).map(
          (key, value) => MapEntry(key, value as String),
        ),
    restDays: (json['restDays'] as List<dynamic>? ?? [])
        .map((day) => day as String)
        .toSet(),
  );
}

List<MilestoneDetail> _readMilestoneDetails(Map<String, dynamic> json) {
  final raw = json['milestoneDetails'];
  if (raw == null) return const [];
  final milestones = json['milestones'];
  if (raw is! List || milestones is! List || raw.length != milestones.length) {
    throw const FormatException('로드맵 단계 수가 맞지 않아요.');
  }
  return raw
      .map(
        (item) =>
            MilestoneDetail.fromJson(Map<String, dynamic>.from(item as Map)),
      )
      .toList();
}

int suggestedWeeklyTarget(String path) => switch (path) {
  '가볍게 시작' => 2,
  '집중해서' => 5,
  _ => 3,
};
