import 'growth_goal.dart';

class RoadmapDraft {
  const RoadmapDraft({
    required this.path,
    required this.weeklyTarget,
    required this.summary,
    required this.firstWeekActions,
    required this.stages,
    this.durationWeeks,
    this.weeklyMinutes,
  });

  final String path;
  final int weeklyTarget;
  final String summary;
  final List<String> firstWeekActions;
  final List<RoadmapStage> stages;
  final int? durationWeeks;
  final int? weeklyMinutes;
}

class RoadmapStage {
  const RoadmapStage({
    required this.title,
    required this.criteria,
    required this.method,
    this.targetDate,
  });

  final String title;
  final String criteria;
  final String method;
  final String? targetDate;

  MilestoneDetail get detail => MilestoneDetail(
    targetDate: targetDate,
    criteria: criteria,
    method: method,
  );
}

List<RoadmapDraft> manualRoadmapDrafts({
  required String mini,
  required String more,
  required String max,
  String? firstMilestone,
  DateTime? targetDate,
  DateTime? startDate,
  int? weeklyMinutes,
}) {
  final start = startDate ?? DateTime.now();
  final days = targetDate
      ?.difference(DateTime(start.year, start.month, start.day))
      .inDays;
  final weeks = days == null || days < 1 || days > 728 ? null : (days + 6) ~/ 7;
  String day(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';
  final firstDate = days != null && days >= 21
      ? day(start.add(const Duration(days: 7)))
      : null;
  final middleDate = days != null && days >= 21
      ? day(start.add(Duration(days: days ~/ 2)))
      : null;
  final finalDate = days != null && days >= 0 ? day(targetDate!) : null;
  final outcome = firstMilestone?.trim();
  RoadmapStage stage(
    String title,
    String criteria,
    String method,
    String? date,
  ) => RoadmapStage(
    title: title,
    criteria: criteria,
    method: method,
    targetDate: date,
  );
  List<RoadmapStage> stagesForDuration(
    RoadmapStage first,
    RoadmapStage middle,
    RoadmapStage last,
  ) {
    if (days == null || days < 0 || days >= 21) {
      return [first, middle, last];
    }
    if (days < 7) return [last];
    return [
      stage(
        '첫 실천',
        '목표 기간 전반에 1회 실천 기록',
        first.method,
        day(start.add(Duration(days: days ~/ 2))),
      ),
      last,
    ];
  }

  return [
    RoadmapDraft(
      path: '가볍게 시작',
      weeklyTarget: suggestedWeeklyTarget('가볍게 시작'),
      summary: '작은 실천을 먼저 반복하며 부담을 낮춰요.',
      firstWeekActions: ['MINI · $mini', '여유 있는 날 MORE · $more'],
      durationWeeks: weeks,
      weeklyMinutes: weeklyMinutes,
      stages: stagesForDuration(
        stage('첫 주 · MINI로 시작', '첫 주에 2일 실천 기록', mini, firstDate),
        stage('반복 · 부담 낮게 이어가기', '2주 동안 주 2일 실천 기록', mini, middleDate),
        stage(
          outcome?.isNotEmpty == true ? outcome! : 'MORE 한 번 시도',
          outcome?.isNotEmpty == true ? '적은 이정표의 결과를 직접 확인' : 'MORE 실천 1회 기록',
          more,
          finalDate,
        ),
      ),
    ),
    RoadmapDraft(
      path: '균형 있게',
      weeklyTarget: suggestedWeeklyTarget('균형 있게'),
      summary: '평소에는 MORE, 바쁜 날에는 MINI로 이어가요.',
      firstWeekActions: ['MORE · $more', '바쁜 날 MINI · $mini'],
      durationWeeks: weeks,
      weeklyMinutes: weeklyMinutes,
      stages: stagesForDuration(
        stage('첫 주 · 실천 리듬 만들기', '첫 주에 3일 실천 기록', more, firstDate),
        stage('반복 · MORE 중심으로', '2주 동안 주 3일 실천 기록', more, middleDate),
        stage(
          outcome?.isNotEmpty == true ? outcome! : 'MAX 한 번 시도',
          outcome?.isNotEmpty == true ? '적은 이정표의 결과를 직접 확인' : 'MAX 실천 1회 기록',
          max,
          finalDate,
        ),
      ),
    ),
    RoadmapDraft(
      path: '집중해서',
      weeklyTarget: suggestedWeeklyTarget('집중해서'),
      summary: '실천일을 늘리고 여유 있는 날 MAX를 시도해요.',
      firstWeekActions: ['MORE · $more', '여유 있는 날 MAX · $max'],
      durationWeeks: weeks,
      weeklyMinutes: weeklyMinutes,
      stages: stagesForDuration(
        stage('첫 주 · MORE로 출발', '첫 주에 5일 실천 기록', more, firstDate),
        stage('반복 · MAX 섞기', '2주 동안 주 5일 실천 기록', max, middleDate),
        stage(
          outcome?.isNotEmpty == true ? outcome! : 'MAX 실천 이어가기',
          outcome?.isNotEmpty == true ? '적은 이정표의 결과를 직접 확인' : 'MAX 실천 2회 기록',
          max,
          finalDate,
        ),
      ),
    ),
  ];
}
