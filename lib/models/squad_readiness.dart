import 'adventure_stage.dart';
import 'battle_engine.dart';
import 'game_creature.dart';

class SquadReadiness {
  const SquadReadiness(this.members, this.power, this.advice);
  final List<CreatureInstance> members;
  final int power;
  final List<String> advice;

  static SquadReadiness evaluate(
    AdventureStage stage,
    List<String?> squad,
    List<CreatureInstance> owned,
  ) {
    final byId = {for (final creature in owned) creature.id: creature};
    final members = [
      for (final id in squad)
        if (byId[id] != null) byId[id]!,
    ];
    final power = BattleEngine.estimatedPower(squad, owned);
    final unused = owned
        .where((creature) => !squad.contains(creature.id))
        .length;
    return SquadReadiness(members, power, [
      if (members.isEmpty) '빈 칸을 눌러 동료를 한 마리 이상 편성해 주세요.',
      if (unused > 0 && members.length < 5)
        '편성하지 않은 동료가 $unused마리 있어요. 빈 칸에 넣으면 함께 싸우고 경험을 받아요.',
      if (members.isNotEmpty && squad.take(2).every((id) => byId[id] == null))
        '전열이 비어 있어요. 체력이 높은 동료를 앞 2칸에 두면 받는 피해가 2 줄어요.',
      if (members.isNotEmpty && power < stage.recommendedPower)
        '권장 전투력보다 낮아요. 앞 장소에서 동료를 키운 뒤 다시 도전할 수 있어요.',
      if (members.isNotEmpty && power >= stage.recommendedPower)
        '권장 전투력에 도달했어요. 적의 행동과 전열·후열 배치도 함께 살펴보세요.',
    ]);
  }

  static String skillSummary(String speciesId) => switch (speciesId) {
    'pine_fox' => '3번째 행동마다 체력이 부족한 아군 1마리 회복',
    'wave_otter' => '3번째 행동마다 추가 피해와 다른 적에게 물결 피해',
    'star_crow' => '3번째 행동마다 표식 · 표식이 걸린 적에게 2회 추가 피해',
    'pebble_newt' => '3번째 행동마다 자신에게 자갈 갑옷 · 다음 피해 6 흡수',
    _ => '기본 공격',
  };
}
