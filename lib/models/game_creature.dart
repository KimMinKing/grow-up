class CreatureSpecies {
  const CreatureSpecies({
    required this.id,
    required this.name,
    required this.element,
    required this.role,
    required this.description,
    this.rarity = '일반',
  });

  final String id;
  final String name;
  final String element;
  final String role;
  final String description;
  final String rarity;
}

const starterSpecies = [
  CreatureSpecies(
    id: 'pine_fox',
    name: '솔여우',
    element: '숲',
    role: '균형',
    description: '작은 발걸음으로 숲길을 찾는 동료',
  ),
  CreatureSpecies(
    id: 'wave_otter',
    name: '파도수달',
    element: '물',
    role: '탐험',
    description: '물길을 따라 새로운 곳을 발견하는 동료',
  ),
  CreatureSpecies(
    id: 'star_crow',
    name: '별까마귀',
    element: '하늘',
    role: '관찰',
    description: '밤하늘의 길을 먼저 살피는 동료',
  ),
];

const riverSpecies = [
  CreatureSpecies(
    id: 'pebble_newt',
    name: '자갈도롱뇽',
    element: '물',
    role: '수호',
    description: '여울의 자갈을 등에 얹고 동료의 길을 지키는 신수',
  ),
];

const allCreatureSpecies = [...starterSpecies, ...riverSpecies];

CreatureSpecies? speciesById(String id) {
  for (final species in allCreatureSpecies) {
    if (species.id == id) return species;
  }
  return null;
}

String firstForestCompanionSpeciesId(String starterSpeciesId) =>
    switch (starterSpeciesId) {
      'pine_fox' => 'wave_otter',
      'wave_otter' => 'star_crow',
      _ => 'pine_fox',
    };

enum CreatureEvolutionStage {
  seed('태동', 1, 0, 0),
  awakened('각성', 3, 4, 1),
  transcended('초월', 5, 8, 2);

  const CreatureEvolutionStage(
    this.label,
    this.firstLevel,
    this.bonusHp,
    this.bonusAttack,
  );

  final String label;
  final int firstLevel;
  final int bonusHp;
  final int bonusAttack;
}

CreatureEvolutionStage evolutionStageForLevel(int level) =>
    level >= CreatureEvolutionStage.transcended.firstLevel
    ? CreatureEvolutionStage.transcended
    : level >= CreatureEvolutionStage.awakened.firstLevel
    ? CreatureEvolutionStage.awakened
    : CreatureEvolutionStage.seed;

class CreatureInstance {
  const CreatureInstance({
    required this.id,
    required this.speciesId,
    required this.level,
    this.battleExperience = 0,
  });

  final String id;
  final String speciesId;
  final int level;
  final int battleExperience;

  CreatureEvolutionStage get evolutionStage => evolutionStageForLevel(level);

  CreatureEvolutionStage? get nextEvolutionStage => switch (evolutionStage) {
    CreatureEvolutionStage.seed => CreatureEvolutionStage.awakened,
    CreatureEvolutionStage.awakened => CreatureEvolutionStage.transcended,
    CreatureEvolutionStage.transcended => null,
  };

  int? get experienceToNextEvolution {
    final next = nextEvolutionStage;
    if (next == null) return null;
    return (next.firstLevel - level) * 3 - battleExperience;
  }

  CreatureInstance earnBattleExperience(int amount) {
    if (level >= 6) return this;
    final total = battleExperience + amount;
    final nextLevel = (level + total ~/ 3).clamp(1, 6);
    return CreatureInstance(
      id: id,
      speciesId: speciesId,
      level: nextLevel,
      battleExperience: nextLevel == 6 ? 0 : total % 3,
    );
  }

  Map<String, Object> toJson() => {
    'id': id,
    'speciesId': speciesId,
    'level': level,
    'battleExperience': battleExperience,
  };

  factory CreatureInstance.fromJson(Map<String, dynamic> json) {
    final id = json['id'];
    final speciesId = json['speciesId'];
    final level = json['level'];
    final battleExperience = json['battleExperience'] ?? 0;
    if (id is! String ||
        id.isEmpty ||
        speciesId is! String ||
        speciesById(speciesId) == null ||
        level is! int ||
        level < 1 ||
        battleExperience is! int ||
        battleExperience < 0 ||
        battleExperience > 2) {
      throw const FormatException('Invalid creature');
    }
    return CreatureInstance(
      id: id,
      speciesId: speciesId,
      level: level,
      battleExperience: battleExperience,
    );
  }
}
