import 'daily_content.dart';

/// Static adventure content. Local combat is playable; currency and badge
/// payout for new regions remains planned.
class AdventureStage {
  const AdventureStage({
    required this.id,
    required this.regionId,
    this.prerequisiteStageId,
    required this.at,
    required this.title,
    required this.place,
    required this.story,
    required this.mission,
    required this.strategy,
    required this.action,
    required this.waves,
    required this.entryTrainingPasses,
    required this.recommendedPower,
    required this.recommendedRole,
    required this.firstClearReward,
    required this.repeatReward,
    this.boss = false,
  });

  final String id;
  final String regionId;
  final String? prerequisiteStageId;
  final int at;
  final String title;
  final String place;
  final String story;
  final String mission;
  final String strategy;
  final String action;
  final List<AdventureWave> waves;
  final int entryTrainingPasses;
  final int recommendedPower;
  final String recommendedRole;
  final StageRewardPlan firstClearReward;
  final StageRewardPlan repeatReward;
  final bool boss;
}

class AdventureWave {
  const AdventureWave(this.enemies);
  final List<StageEnemy> enemies;
}

class StageEnemy {
  const StageEnemy(this.id, this.name, this.level, {this.boss = false});
  final String id;
  final String name;
  final int level;
  final bool boss;
}

/// Planned rewards. The current story map and first battle mint no currency.
class StageRewardPlan {
  const StageRewardPlan({this.badge = '', this.fragments = 0});
  final String badge;
  final int fragments;
}

/// A per-stage save record shared by story exploration and battles.
class StageProgress {
  const StageProgress({
    this.clearCount = 0,
    this.stars = 0,
    this.bestTurns,
    this.rewardDay,
    this.rewardedWinsToday = 0,
  });

  final int clearCount;
  final int stars;
  final int? bestTurns;
  final String? rewardDay;
  final int rewardedWinsToday;

  factory StageProgress.fromJson(Map<String, dynamic> json) {
    final clears = json['clearCount'];
    final stars = json['stars'];
    final turns = json['bestTurns'];
    final rewardDay = json['rewardDay'];
    final rewardedWinsToday = json['rewardedWinsToday'] ?? 0;
    if (clears is! int ||
        clears < 0 ||
        stars is! int ||
        stars < 0 ||
        stars > 3 ||
        (clears == 0 && (stars != 0 || turns != null)) ||
        (turns != null && (turns is! int || turns < 1)) ||
        (rewardDay != null &&
            (rewardDay is! String || !validDailyKey(rewardDay))) ||
        rewardedWinsToday is! int ||
        rewardedWinsToday < 0 ||
        rewardedWinsToday > 5 ||
        (rewardedWinsToday > 0 && (rewardDay == null || stars == 0))) {
      throw const FormatException('Invalid stage progress');
    }
    return StageProgress(
      clearCount: clears,
      stars: stars,
      bestTurns: turns as int?,
      rewardDay: rewardDay as String?,
      rewardedWinsToday: rewardedWinsToday,
    );
  }

  Map<String, Object?> toJson() => {
    'clearCount': clearCount,
    'stars': stars,
    'bestTurns': bestTurns,
    if (rewardDay != null) 'rewardDay': rewardDay,
    if (rewardedWinsToday > 0) 'rewardedWinsToday': rewardedWinsToday,
  };
}

/// Older saves only had a cleared-stage count. Preserve those story clears.
Map<String, StageProgress> readStageProgress(Object? raw, int cleared) {
  if (raw == null) {
    return {
      for (var index = 0; index < cleared; index++)
        firstForestStages[index].id: const StageProgress(clearCount: 1),
    };
  }
  if (raw is! Map<String, dynamic> || raw.length > allAdventureStages.length) {
    throw const FormatException('Invalid stage records');
  }
  final knownIds = allAdventureStages.map((stage) => stage.id).toSet();
  final records = <String, StageProgress>{};
  for (final entry in raw.entries) {
    if (!knownIds.contains(entry.key) || entry.value is! Map) {
      throw const FormatException('Invalid stage record');
    }
    records[entry.key] = StageProgress.fromJson(
      Map<String, dynamic>.from(entry.value as Map),
    );
  }
  for (var index = 0; index < firstForestStages.length; index++) {
    final record = records[firstForestStages[index].id];
    if (index < cleared && (record == null || record.clearCount < 1) ||
        index >= cleared && record != null && record.clearCount > 0) {
      throw const FormatException('Stage count and records disagree');
    }
  }
  for (final stage in riverStages) {
    if ((records[stage.id]?.clearCount ?? 0) > 0 &&
        (records[stage.prerequisiteStageId]?.stars ?? 0) == 0) {
      throw const FormatException('River stage requires its previous victory');
    }
  }
  return records;
}

const firstForestStages = <AdventureStage>[
  AdventureStage(
    id: 'forest_moss_gate',
    regionId: 'first_forest',
    at: 1,
    title: '첫 발자국',
    place: '이끼 문턱',
    story: '작은 발자국이 돌아올 길을 기억합니다.',
    mission: '동료와 함께 이끼 문턱을 지나 첫 발자국을 찾아보세요.',
    strategy: '첫 장소예요. 앞줄에 체력이 높은 동료를 두고 한 마리씩 공격해 보세요.',
    action: '발자국 찾기',
    waves: [
      AdventureWave([StageEnemy('moss_spore', '이끼 포자', 1)]),
      AdventureWave([StageEnemy('moss_guard', '이끼 수호자', 2, boss: true)]),
    ],
    entryTrainingPasses: 1,
    recommendedPower: 100,
    recommendedRole: '균형',
    firstClearReward: StageRewardPlan(badge: '첫 발자국', fragments: 1),
    repeatReward: StageRewardPlan(),
  ),
  AdventureStage(
    id: 'forest_firefly_path',
    regionId: 'first_forest',
    prerequisiteStageId: 'forest_moss_gate',
    at: 3,
    title: '반딧불이의 길',
    place: '반딧불이 오솔길',
    story: '반딧불이가 숲 안쪽 길을 비춥니다.',
    mission: '반딧불이를 따라 숲 안쪽으로 이어지는 길을 살펴보세요.',
    strategy: '첫 웨이브에 적이 둘이에요. 한 마리를 먼저 쓰러뜨려 받는 공격을 줄여 보세요.',
    action: '빛 따라가기',
    waves: [
      AdventureWave([
        StageEnemy('night_mushroom', '밤버섯', 2),
        StageEnemy('night_mushroom', '밤버섯', 2),
      ]),
      AdventureWave([StageEnemy('firefly_wisp', '반딧불 정령', 3)]),
    ],
    entryTrainingPasses: 1,
    recommendedPower: 180,
    recommendedRole: '탐험',
    firstClearReward: StageRewardPlan(badge: '숲의 등불', fragments: 1),
    repeatReward: StageRewardPlan(),
  ),
  AdventureStage(
    id: 'forest_dawn_lookout',
    regionId: 'first_forest',
    prerequisiteStageId: 'forest_firefly_path',
    at: 7,
    title: '숲의 새벽',
    place: '새벽 전망대',
    story: '새벽빛 너머에 다음 여행이 기다립니다.',
    mission: '새벽 전망대에 올라 숲 너머의 새 길을 발견하세요.',
    strategy: '마지막 웨이브가 보스예요. 앞줄의 체력을 남기고 보스전에 들어가 보세요.',
    action: '전망대 오르기',
    waves: [
      AdventureWave([
        StageEnemy('wind_shadow', '바람 그림자', 3),
        StageEnemy('wind_shadow', '바람 그림자', 3),
      ]),
      AdventureWave([StageEnemy('dawn_sentinel', '새벽 파수꾼', 4, boss: true)]),
    ],
    entryTrainingPasses: 1,
    recommendedPower: 300,
    recommendedRole: '관찰',
    firstClearReward: StageRewardPlan(badge: '숲의 새벽', fragments: 2),
    repeatReward: StageRewardPlan(),
    boss: true,
  ),
];

const riverStages = <AdventureStage>[
  AdventureStage(
    id: 'river_mist_entry',
    regionId: 'mist_river',
    prerequisiteStageId: 'forest_dawn_lookout',
    at: 7,
    title: '물안개 너머',
    place: '강가 입구',
    story: '새벽 전망대 아래로 안개 낀 강이 흐릅니다.',
    mission: '강가 입구를 지키는 물안개 수호자의 보호막을 돌파하세요.',
    strategy: '수호자의 물안개 보호막은 첫 피해 8을 흡수해요. 동료를 편성해 연속 공격으로 깨 보세요.',
    action: '강가 살피기',
    waves: [
      AdventureWave([StageEnemy('river_mist_guard', '물안개 수호자', 4)]),
    ],
    entryTrainingPasses: 1,
    recommendedPower: 310,
    recommendedRole: '연속 공격',
    firstClearReward: StageRewardPlan(badge: '강가의 첫 발', fragments: 0),
    repeatReward: StageRewardPlan(),
  ),
  AdventureStage(
    id: 'river_shallow_crossing',
    regionId: 'mist_river',
    prerequisiteStageId: 'river_mist_entry',
    at: 7,
    title: '갈대 사이의 길',
    place: '물안개 여울',
    story: '얕은 물길 너머로 부서진 다리와 갈대밭이 보입니다.',
    mission: '앞줄을 막는 돌게와 뒷줄을 노리는 갈대 추적자를 넘어가세요.',
    strategy: '첫 웨이브의 돌게는 앞줄을 공격하고, 다음 웨이브의 갈대 추적자는 가장 뒤의 동료를 노려요. 후열도 버틸 수 있게 편성하세요.',
    action: '여울 건너기',
    waves: [
      AdventureWave([
        StageEnemy('river_stone_crab', '여울 돌게', 4),
        StageEnemy('river_stone_crab', '여울 돌게', 4),
      ]),
      AdventureWave([
        StageEnemy('river_reed_stalker', '갈대 추적자', 5),
        StageEnemy('river_reed_stalker', '갈대 추적자', 5),
      ]),
    ],
    entryTrainingPasses: 1,
    recommendedPower: 350,
    recommendedRole: '전열·후열 균형',
    firstClearReward: StageRewardPlan(badge: '여울의 길', fragments: 0),
    repeatReward: StageRewardPlan(),
  ),
  AdventureStage(
    id: 'river_moon_ferry',
    regionId: 'mist_river',
    prerequisiteStageId: 'river_shallow_crossing',
    at: 7,
    title: '달빛의 건넘',
    place: '달빛 나루',
    story: '달빛이 물결 위에 길을 그리고 오래된 나룻배가 떠 있습니다.',
    mission: '달빛 사공의 장막을 걷고 강가의 마지막 길을 여세요.',
    strategy: '달빛 사공은 처음 피해 14를 흡수하고 세 번째 행동마다 보호막 8을 다시 둘러요. 동료의 공격 순서를 조정해 장막을 빠르게 깨세요.',
    action: '나룻배로 가기',
    waves: [
      AdventureWave([
        StageEnemy('river_stone_crab', '여울 돌게', 5),
        StageEnemy('river_reed_stalker', '갈대 추적자', 5),
      ]),
      AdventureWave([
        StageEnemy('river_moon_ferryman', '달빛 사공', 6, boss: true),
      ]),
    ],
    entryTrainingPasses: 1,
    recommendedPower: 400,
    recommendedRole: '보호막 돌파',
    firstClearReward: StageRewardPlan(badge: '강가의 달빛', fragments: 0),
    repeatReward: StageRewardPlan(),
    boss: true,
  ),
];

const allAdventureStages = <AdventureStage>[
  ...firstForestStages,
  ...riverStages,
];
