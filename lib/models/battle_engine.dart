import 'adventure_stage.dart';
import 'game_creature.dart';

class BattleFighterState {
  const BattleFighterState(
    this.name,
    this.hp,
    this.maxHp,
    this.slot,
    this.id,
    this.boss, {
    this.level = 1,
  });
  final String name;
  final int hp;
  final int maxHp;
  final int slot;
  final String id;
  final bool boss;
  final int level;
}

enum BattleActionEffect { basic, heal, water, star, wind, dawn }

class BattleFrame {
  const BattleFrame({
    required this.wave,
    required this.round,
    required this.message,
    required this.allies,
    required this.enemies,
    this.actorSlot,
    this.actorIsAlly,
    this.effect = BattleActionEffect.basic,
  });
  final int wave;
  final int round;
  final String message;
  final List<BattleFighterState> allies;
  final List<BattleFighterState> enemies;
  final int? actorSlot;
  final bool? actorIsAlly;
  final BattleActionEffect effect;
}

class BattleResult {
  const BattleResult(
    this.frames,
    this.won,
    this.turns,
    this.stars, {
    this.rewardSpeciesId,
    this.leveledUpCreatureIds = const [],
    this.evolvedCreatureIds = const [],
    this.experiencePerCreature = 0,
    this.firstBattleClear = false,
  });
  final List<BattleFrame> frames;
  final bool won;
  final int turns;
  final int stars;

  /// A local, once-only companion granted by the store after a victory.
  final String? rewardSpeciesId;
  final List<String> leveledUpCreatureIds;
  final List<String> evolvedCreatureIds;
  final int experiencePerCreature;
  final bool firstBattleClear;
}

class BattleEngine {
  static ({int hp, int attack, int speed}) allyStatsFor(
    CreatureInstance creature,
  ) {
    final base = _allyStats(creature.speciesId);
    final stage = creature.evolutionStage;
    return (
      hp: base.hp + (creature.level - 1) * 6 + stage.bonusHp,
      attack: base.attack + (creature.level - 1) * 2 + stage.bonusAttack,
      speed: base.speed,
    );
  }

  static int estimatedPower(List<String?> squad, List<CreatureInstance> owned) {
    final byId = {for (final creature in owned) creature.id: creature};
    var total = 0;
    for (final id in squad) {
      final creature = byId[id];
      if (creature == null) continue;
      final stats = allyStatsFor(creature);
      total += stats.hp + stats.attack * 3 + stats.speed;
    }
    return total;
  }

  static BattleResult simulate(
    AdventureStage stage,
    List<String?> squad,
    List<CreatureInstance> owned,
  ) {
    final byId = {for (final creature in owned) creature.id: creature};
    final allies = <_Fighter>[];
    for (var slot = 0; slot < squad.length; slot++) {
      final creature = byId[squad[slot]];
      if (creature == null) continue;
      final stats = allyStatsFor(creature);
      final species = speciesById(creature.speciesId)!;
      allies.add(
        _Fighter(
          name: species.name,
          hp: stats.hp,
          attack: stats.attack,
          speed: stats.speed,
          slot: slot,
          speciesId: creature.speciesId,
          level: creature.level,
        ),
      );
    }
    if (allies.isEmpty) {
      return const BattleResult([], false, 0, 0);
    }
    final frames = <BattleFrame>[];
    var totalRounds = 0;
    var waveNumber = 0;
    for (final wave in stage.waves) {
      waveNumber++;
      final enemies = <_Fighter>[
        for (var i = 0; i < wave.enemies.length; i++)
          _enemy(wave.enemies[i], i),
      ];
      void record(
        String message, {
        _Fighter? actor,
        BattleActionEffect effect = BattleActionEffect.basic,
      }) => frames.add(
        BattleFrame(
          wave: waveNumber,
          round: totalRounds,
          message: message,
          allies: [for (final fighter in allies) fighter.state],
          enemies: [for (final fighter in enemies) fighter.state],
          actorSlot: actor?.slot,
          actorIsAlly: actor == null ? null : allies.contains(actor),
          effect: effect,
        ),
      );
      record('$waveNumber웨이브 시작');
      while (enemies.any((enemy) => enemy.hp > 0) &&
          allies.any((ally) => ally.hp > 0) &&
          totalRounds < 30) {
        totalRounds++;
        final order = [...allies, ...enemies]
          ..sort((a, b) {
            final speed = b.speed.compareTo(a.speed);
            return speed == 0 ? a.slot.compareTo(b.slot) : speed;
          });
        for (final fighter in order) {
          if (fighter.hp <= 0) continue;
          final isAlly = allies.contains(fighter);
          final targets = isAlly ? enemies : allies;
          if (!targets.any((target) => target.hp > 0)) break;
          final target = !isAlly && fighter.speciesId == 'river_reed_stalker'
              ? targets.lastWhere((target) => target.hp > 0)
              : targets.firstWhere((target) => target.hp > 0);
          fighter.actions++;
          if (isAlly &&
              fighter.speciesId == 'pebble_newt' &&
              fighter.actions % 3 == 0) {
            fighter.shield = fighter.shield < 6 ? 6 : fighter.shield;
            record(
              '${fighter.name}의 자갈 갑옷 · 다음 피해 6 흡수',
              actor: fighter,
              effect: BattleActionEffect.water,
            );
          }
          if (!isAlly &&
              fighter.speciesId == 'river_moon_ferryman' &&
              fighter.actions % 3 == 0) {
            fighter.shield = fighter.shield < 8 ? 8 : fighter.shield;
            record(
              '${fighter.name}이 달빛 장막 8을 둘렀어요.',
              actor: fighter,
              effect: BattleActionEffect.water,
            );
          }
          if (isAlly &&
              fighter.speciesId == 'pine_fox' &&
              fighter.actions % 3 == 0) {
            final hurt = allies
                .where((ally) => ally.hp > 0)
                .reduce((a, b) => a.hp * b.maxHp <= b.hp * a.maxHp ? a : b);
            final healed = (hurt.maxHp - hurt.hp).clamp(0, 13);
            hurt.hp += healed;
            record(
              '${fighter.name}의 숲의 숨결 · ${hurt.name} 체력 +$healed',
              actor: fighter,
              effect: BattleActionEffect.heal,
            );
          }
          final bonus = isAlly && fighter.slot >= 2 ? 3 : 0;
          final guard = !isAlly && target.slot < 2 ? 2 : 0;
          final attributeBonus = elementBonus(
            fighter.speciesId,
            target.speciesId,
          );
          var damage = (fighter.attack + bonus - guard + attributeBonus).clamp(
            1,
            999,
          );
          var action = '기본 공격';
          if (isAlly &&
              fighter.speciesId == 'wave_otter' &&
              fighter.actions % 3 == 0) {
            damage += 5;
            action = '물결 베기';
          }
          if (isAlly &&
              fighter.speciesId == 'star_crow' &&
              fighter.actions % 3 == 0) {
            target.marked = 2;
            action = '별빛 표식';
          }
          if (!isAlly &&
              fighter.speciesId == 'wind_shadow' &&
              fighter.actions % 2 == 0) {
            damage += 2;
            action = '돌풍 베기';
          }
          if (!isAlly &&
              fighter.speciesId == 'dawn_sentinel' &&
              fighter.actions % 2 == 0) {
            damage += 3;
            action = '새벽의 일격';
          }
          if (!isAlly && fighter.speciesId == 'river_reed_stalker') {
            action = '갈대 기습';
          }
          if (!isAlly &&
              fighter.speciesId == 'river_moon_ferryman' &&
              fighter.actions % 3 == 0) {
            damage += 2;
            action = '달빛 물결';
          }
          if (target.marked > 0) {
            damage += 4;
            target.marked--;
          }
          final absorbed = damage.clamp(0, target.shield);
          target.shield -= absorbed;
          damage -= absorbed;
          target.hp = (target.hp - damage).clamp(0, target.maxHp);
          record(
            '${fighter.name}의 $action → ${target.name} $damage 피해${absorbed > 0 ? ' · ${target.speciesId == 'river_moon_ferryman'
                      ? '달빛 장막'
                      : target.speciesId == 'pebble_newt'
                      ? '자갈 갑옷'
                      : '물안개 보호막'} $absorbed 흡수' : ''}',
            actor: fighter,
            effect: switch (action) {
              '물결 베기' => BattleActionEffect.water,
              '별빛 표식' => BattleActionEffect.star,
              '돌풍 베기' => BattleActionEffect.wind,
              '새벽의 일격' => BattleActionEffect.dawn,
              '갈대 기습' || '달빛 물결' => BattleActionEffect.water,
              _ => BattleActionEffect.basic,
            },
          );
          if (isAlly &&
              fighter.speciesId == 'wave_otter' &&
              fighter.actions % 3 == 0) {
            final secondary = enemies
                .where((enemy) => enemy != target && enemy.hp > 0)
                .firstOrNull;
            if (secondary != null) {
              final splash = (damage ~/ 2).clamp(1, 999);
              secondary.hp = (secondary.hp - splash).clamp(0, secondary.maxHp);
              record(
                '물결이 ${secondary.name}에게 $splash 추가 피해',
                actor: fighter,
                effect: BattleActionEffect.water,
              );
            }
          }
        }
      }
      if (allies.every((ally) => ally.hp <= 0)) break;
      if (enemies.every((enemy) => enemy.hp <= 0)) {
        record('$waveNumber웨이브 돌파');
      } else {
        break;
      }
    }
    final won =
        waveNumber == stage.waves.length &&
        frames.isNotEmpty &&
        frames.last.message.endsWith('돌파');
    final remaining = allies.fold<int>(0, (sum, ally) => sum + ally.hp);
    final maximum = allies.fold<int>(0, (sum, ally) => sum + ally.maxHp);
    final stars = !won
        ? 0
        : remaining * 10 >= maximum * 7
        ? 3
        : remaining * 10 >= maximum * 3
        ? 2
        : 1;
    frames.add(
      BattleFrame(
        wave: waveNumber,
        round: totalRounds,
        message: won
            ? '승리 · 별 $stars개'
            : allies.every((ally) => ally.hp <= 0)
            ? '패배 · 동료가 모두 쓰러졌어요. 전열을 보강해 보세요.'
            : '패배 · 30턴 안에 끝내지 못했어요. 공격 역할을 보강해 보세요.',
        allies: [for (final fighter in allies) fighter.state],
        enemies: const [],
      ),
    );
    return BattleResult(List.unmodifiable(frames), won, totalRounds, stars);
  }

  static ({int hp, int attack, int speed}) _allyStats(String id) =>
      switch (id) {
        'pine_fox' => (hp: 58, attack: 15, speed: 10),
        'wave_otter' => (hp: 52, attack: 17, speed: 13),
        'star_crow' => (hp: 47, attack: 20, speed: 16),
        'pebble_newt' => (hp: 60, attack: 13, speed: 9),
        _ => (hp: 40, attack: 12, speed: 8),
      };

  static int elementBonus(String attacker, String defender) {
    String element(String id) => switch (id) {
      'pine_fox' || 'moss_spore' || 'moss_guard' || 'dawn_sentinel' => 'forest',
      'wave_otter' ||
      'pebble_newt' ||
      'night_mushroom' ||
      'river_mist_guard' ||
      'river_stone_crab' ||
      'river_reed_stalker' ||
      'river_moon_ferryman' => 'water',
      _ => 'sky',
    };
    final attack = element(attacker);
    final defense = element(defender);
    if (attack == defense) return 0;
    if (attack == 'forest' && defense == 'water' ||
        attack == 'water' && defense == 'sky' ||
        attack == 'sky' && defense == 'forest') {
      return 3;
    }
    return -2;
  }

  static _Fighter _enemy(StageEnemy enemy, int slot) {
    final stats = switch (enemy.id) {
      'moss_spore' => (hp: 22, attack: 7, speed: 5),
      'moss_guard' => (hp: 42, attack: 10, speed: 7),
      'night_mushroom' => (hp: 38, attack: 12, speed: 8),
      'firefly_wisp' => (hp: 60, attack: 15, speed: 12),
      'wind_shadow' => (hp: 50, attack: 16, speed: 14),
      'dawn_sentinel' => (hp: 94, attack: 21, speed: 13),
      'river_mist_guard' => (hp: 72, attack: 17, speed: 11),
      'river_stone_crab' => (hp: 44, attack: 14, speed: 7),
      'river_reed_stalker' => (hp: 46, attack: 17, speed: 15),
      'river_moon_ferryman' => (hp: 200, attack: 29, speed: 12),
      _ => (hp: 100, attack: 22, speed: 13),
    };
    return _Fighter(
      name: enemy.name,
      hp: stats.hp,
      attack: stats.attack,
      speed: stats.speed,
      slot: slot,
      speciesId: enemy.id,
      boss: enemy.boss,
    );
  }
}

class _Fighter {
  _Fighter({
    required this.name,
    required int hp,
    required this.attack,
    required this.speed,
    required this.slot,
    required this.speciesId,
    this.level = 1,
    this.boss = false,
  }) : hp = hp,
       maxHp = hp,
       shield = switch (speciesId) {
         'river_mist_guard' => 8,
         'river_moon_ferryman' => 14,
         _ => 0,
       };

  final String name;
  int hp;
  final int maxHp;
  final int attack;
  final int speed;
  final int slot;
  final String speciesId;
  final int level;
  final bool boss;
  int actions = 0;
  int marked = 0;
  int shield;

  BattleFighterState get state =>
      BattleFighterState(name, hp, maxHp, slot, speciesId, boss, level: level);
}
