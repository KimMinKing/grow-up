import 'dart:convert';

import 'roadmap_draft.dart';

class RoadmapPlan {
  const RoadmapPlan({
    required this.source,
    required this.title,
    required this.summary,
    required this.weeklyTarget,
    required this.firstWeekActions,
    required this.milestones,
    this.durationWeeks,
    this.weeklyMinutes,
  });

  final String source;
  final String title;
  final String summary;
  final int weeklyTarget;
  final int? durationWeeks;
  final int? weeklyMinutes;
  final List<String> milestones;
  final List<String> firstWeekActions;

  factory RoadmapPlan.fromManualDraft(
    RoadmapDraft draft, {
    String? firstMilestone,
  }) => RoadmapPlan(
    source: 'manual',
    title: draft.path,
    summary: draft.summary,
    weeklyTarget: draft.weeklyTarget,
    durationWeeks: draft.durationWeeks,
    weeklyMinutes: draft.weeklyMinutes,
    firstWeekActions: List.unmodifiable(draft.firstWeekActions),
    milestones: List.unmodifiable([
      for (final entry in draft.stages.asMap().entries)
        entry.key == draft.stages.length - 1 &&
                firstMilestone != null &&
                firstMilestone.trim().isNotEmpty
            ? firstMilestone.trim()
            : entry.value.title,
    ]),
  );

  Map<String, dynamic> toJson() => {
    'source': source,
    'title': title,
    'summary': summary,
    'weeklyTarget': weeklyTarget,
    'durationWeeks': durationWeeks,
    'weeklyMinutes': weeklyMinutes,
    'milestones': milestones,
    'firstWeekActions': firstWeekActions,
  };

  factory RoadmapPlan.fromJson(Map<String, dynamic> json) {
    final plan = RoadmapPlan(
      source: json['source'] as String,
      title: json['title'] as String,
      summary: json['summary'] as String,
      weeklyTarget: json['weeklyTarget'] as int,
      durationWeeks: json['durationWeeks'] as int?,
      weeklyMinutes: json['weeklyMinutes'] as int?,
      milestones: (json['milestones'] as List<dynamic>)
          .map((item) => item as String)
          .toList(),
      firstWeekActions: (json['firstWeekActions'] as List<dynamic>)
          .map((item) => item as String)
          .toList(),
    );
    plan.validate();
    return plan;
  }

  static RoadmapPlan? tryFromJson(Object? value) {
    if (value is! Map) return null;
    try {
      return RoadmapPlan.fromJson(Map<String, dynamic>.from(value));
    } catch (_) {
      return null;
    }
  }

  void validate({bool requireFullPlan = false, int? availableMinutes}) {
    if (!['manual', 'ai'].contains(source) ||
        title.trim().isEmpty ||
        title.length > 80 ||
        summary.trim().isEmpty ||
        summary.length > 500 ||
        weeklyTarget < 1 ||
        weeklyTarget > 7 ||
        firstWeekActions.isEmpty ||
        firstWeekActions.length > 7 ||
        firstWeekActions.any(
          (action) =>
              action.trim().isEmpty ||
              action.length > (source == 'manual' ? 200 : 160),
        ) ||
        milestones.length > 12 ||
        milestones.any((step) => step.trim().isEmpty || step.length > 120) ||
        (durationWeeks != null &&
            (durationWeeks! < 1 || durationWeeks! > 104)) ||
        (weeklyMinutes != null &&
            (weeklyMinutes! < 1 || weeklyMinutes! > 10080))) {
      throw const FormatException('Invalid roadmap plan');
    }
    if (requireFullPlan &&
        (source != 'ai' ||
            durationWeeks == null ||
            weeklyMinutes == null ||
            milestones.isEmpty ||
            (availableMinutes != null && weeklyMinutes! > availableMinutes))) {
      throw const FormatException('Incomplete or infeasible AI roadmap plan');
    }
  }
}

List<RoadmapPlan> parseAiRoadmapOptions(
  Object? value, {
  int? availableMinutes,
}) {
  if (value is! List || value.length != 3) {
    throw const FormatException('Exactly three roadmap options are required');
  }
  late final List<RoadmapPlan> plans;
  try {
    plans = value.map((item) {
      if (item is! Map) throw const FormatException('Invalid roadmap option');
      final json = Map<String, dynamic>.from(item);
      json['source'] = 'ai';
      final plan = RoadmapPlan.fromJson(json);
      plan.validate(requireFullPlan: true, availableMinutes: availableMinutes);
      return plan;
    }).toList();
  } on FormatException {
    rethrow;
  } catch (_) {
    throw const FormatException('Invalid roadmap option fields');
  }
  if (plans.map((plan) => plan.title).toSet().length != 3) {
    throw const FormatException('Roadmap options need distinct titles');
  }
  final variants = plans
      .map(
        (plan) => jsonEncode([
          plan.summary,
          plan.weeklyTarget,
          plan.durationWeeks,
          plan.weeklyMinutes,
          plan.milestones,
          plan.firstWeekActions,
        ]),
      )
      .toSet();
  if (variants.length != 3) {
    throw const FormatException('Roadmap options need distinct contents');
  }
  final pacing = plans
      .map(
        (plan) => jsonEncode([
          plan.weeklyTarget,
          plan.durationWeeks,
          plan.weeklyMinutes,
        ]),
      )
      .toSet();
  if (pacing.length != 3) {
    throw const FormatException('Roadmap options need distinct pacing');
  }
  return plans;
}
