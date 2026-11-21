// Deterministic adventure combat kernel. All inputs must come from server
// owned state before this is used for reward verification.
const allyStats = {
  pine_fox: [58, 15, 10],
  wave_otter: [52, 17, 13],
  star_crow: [47, 20, 16],
  pebble_newt: [60, 13, 9],
};
const enemyStats = {
  moss_spore: [22, 7, 5],
  moss_guard: [42, 10, 7],
  night_mushroom: [38, 12, 8],
  firefly_wisp: [60, 15, 12],
  wind_shadow: [50, 16, 14],
  dawn_sentinel: [94, 21, 13],
  river_mist_guard: [72, 17, 11],
  river_stone_crab: [44, 14, 7],
  river_reed_stalker: [46, 17, 15],
  river_moon_ferryman: [200, 29, 12],
};
const stages = {
  forest_moss_gate: [['moss_spore'], ['moss_guard']],
  forest_firefly_path: [
    ['night_mushroom', 'night_mushroom'],
    ['firefly_wisp'],
  ],
  forest_dawn_lookout: [
    ['wind_shadow', 'wind_shadow'],
    ['dawn_sentinel'],
  ],
  river_mist_entry: [['river_mist_guard']],
  river_shallow_crossing: [
    ['river_stone_crab', 'river_stone_crab'],
    ['river_reed_stalker', 'river_reed_stalker'],
  ],
  river_moon_ferry: [
    ['river_stone_crab', 'river_reed_stalker'],
    ['river_moon_ferryman'],
  ],
};

function element(id) {
  if (['pine_fox', 'moss_spore', 'moss_guard', 'dawn_sentinel'].includes(id)) {
    return 'forest';
  }
  if (['wave_otter', 'pebble_newt', 'night_mushroom', 'river_mist_guard',
    'river_stone_crab', 'river_reed_stalker', 'river_moon_ferryman'].includes(id)) return 'water';
  return 'sky';
}

function elementBonus(attacker, defender) {
  const attack = element(attacker);
  const defense = element(defender);
  if (attack === defense) return 0;
  return (
    (attack === 'forest' && defense === 'water') ||
    (attack === 'water' && defense === 'sky') ||
    (attack === 'sky' && defense === 'forest')
  ) ? 3 : -2;
}

function fighter(id, slot, level, stats) {
  const [bonusHp, bonusAttack] = !Object.hasOwn(allyStats, id)
    ? [0, 0]
    : level >= 5 ? [8, 2] : level >= 3 ? [4, 1] : [0, 0];
  return {
    id, slot, hp: stats[0] + (level - 1) * 6 + bonusHp,
    maxHp: stats[0] + (level - 1) * 6 + bonusHp,
    attack: stats[1] + (level - 1) * 2 + bonusAttack,
    speed: stats[2], actions: 0, marked: 0,
    shield: id === 'river_mist_guard' ? 8 : id === 'river_moon_ferryman' ? 14 : 0,
  };
}

function clamp(value, min, max) {
  return Math.max(min, Math.min(max, value));
}

function firstAlive(fighters) {
  return fighters.find((item) => item.hp > 0);
}

export function simulateForestBattle(stageId, squad) {
  if (!Object.hasOwn(stages, stageId)) throw new RangeError('Unknown stage');
  if (!Array.isArray(squad) || squad.length !== 5) {
    throw new TypeError('Squad must have five slots');
  }
  const allies = squad.flatMap((member, slot) => {
    if (member === null) return [];
    if (!member || !Object.hasOwn(allyStats, member.speciesId) ||
        !Number.isInteger(member.level) || member.level < 1 || member.level > 6) {
      throw new TypeError('Invalid squad member');
    }
    return [fighter(member.speciesId, slot, member.level, allyStats[member.speciesId])];
  });
  if (allies.length === 0) return { won: false, turns: 0, stars: 0, remainingHp: [] };

  let rounds = 0;
  let wavesCleared = 0;
  for (const wave of stages[stageId]) {
    const enemies = wave.map((id, slot) => fighter(id, slot, 1, enemyStats[id]));
    while (firstAlive(enemies) && firstAlive(allies) && rounds < 30) {
      rounds++;
      // Dart's stable sort keeps allies before enemies when speed and slot tie.
      const order = [...allies, ...enemies].sort((a, b) =>
        b.speed - a.speed || a.slot - b.slot);
      for (const actor of order) {
        if (actor.hp <= 0) continue;
        const isAlly = allies.includes(actor);
        const targets = isAlly ? enemies : allies;
        const target = !isAlly && actor.id === 'river_reed_stalker'
          ? targets.findLast((item) => item.hp > 0)
          : firstAlive(targets);
        if (!target) break;
        actor.actions++;
        if (isAlly && actor.id === 'pebble_newt' && actor.actions % 3 === 0) {
          actor.shield = Math.max(actor.shield, 6);
        }
        if (!isAlly && actor.id === 'river_moon_ferryman' && actor.actions % 3 === 0) {
          actor.shield = Math.max(actor.shield, 8);
        }
        if (isAlly && actor.id === 'pine_fox' && actor.actions % 3 === 0) {
          const hurt = allies.filter((item) => item.hp > 0).reduce((a, b) =>
            a.hp * b.maxHp <= b.hp * a.maxHp ? a : b);
          hurt.hp += clamp(hurt.maxHp - hurt.hp, 0, 13);
        }
        const bonus = isAlly && actor.slot >= 2 ? 3 : 0;
        const guard = !isAlly && target.slot < 2 ? 2 : 0;
        let damage = clamp(
          actor.attack + bonus - guard + elementBonus(actor.id, target.id), 1, 999);
        if (isAlly && actor.id === 'wave_otter' && actor.actions % 3 === 0) {
          damage += 5;
        }
        if (isAlly && actor.id === 'star_crow' && actor.actions % 3 === 0) {
          target.marked = 2;
        }
        if (!isAlly && actor.id === 'wind_shadow' && actor.actions % 2 === 0) {
          damage += 2;
        }
        if (!isAlly && actor.id === 'dawn_sentinel' && actor.actions % 2 === 0) {
          damage += 3;
        }
        if (!isAlly && actor.id === 'river_moon_ferryman' && actor.actions % 3 === 0) {
          damage += 2;
        }
        if (target.marked > 0) {
          damage += 4;
          target.marked--;
        }
        const absorbed = Math.min(damage, target.shield);
        target.shield -= absorbed;
        damage -= absorbed;
        target.hp = clamp(target.hp - damage, 0, target.maxHp);
        if (isAlly && actor.id === 'wave_otter' && actor.actions % 3 === 0) {
          const secondary = enemies.find((item) => item !== target && item.hp > 0);
          if (secondary) {
            secondary.hp = clamp(secondary.hp - clamp(Math.floor(damage / 2), 1, 999),
              0, secondary.maxHp);
          }
        }
      }
    }
    if (!firstAlive(enemies)) wavesCleared++;
    else break;
    if (!firstAlive(allies)) break;
  }
  const won = wavesCleared === stages[stageId].length;
  const remaining = allies.reduce((sum, ally) => sum + ally.hp, 0);
  const maximum = allies.reduce((sum, ally) => sum + ally.maxHp, 0);
  const stars = !won ? 0 : remaining * 10 >= maximum * 7 ? 3
    : remaining * 10 >= maximum * 3 ? 2 : 1;
  return { won, turns: rounds, stars, remainingHp: allies.map((ally) => ally.hp) };
}
