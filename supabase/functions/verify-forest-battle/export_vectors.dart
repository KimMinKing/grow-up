// Run with the project Flutter SDK's dart executable to refresh the parity
// vectors after changing the local combat rules.
import 'dart:convert';
import 'dart:io';

import 'package:growup/models/adventure_stage.dart';
import 'package:growup/models/battle_engine.dart';
import 'package:growup/models/game_creature.dart';

void main() {
  const species = ['pine_fox', 'wave_otter', 'star_crow', 'pebble_newt'];
  final vectors = <Map<String, Object?>>[];

  void add(String stageId, List<({String speciesId, int level})?> members) {
    final stage = allAdventureStages.firstWhere((item) => item.id == stageId);
    final owned = <CreatureInstance>[];
    final squad = <String?>[];
    for (var slot = 0; slot < members.length; slot++) {
      final member = members[slot];
      if (member == null) {
        squad.add(null);
      } else {
        final id = 'member-$slot';
        squad.add(id);
        owned.add(
          CreatureInstance(
            id: id,
            speciesId: member.speciesId,
            level: member.level,
          ),
        );
      }
    }
    final result = BattleEngine.simulate(stage, squad, owned);
    vectors.add({
      'stageId': stageId,
      'squad': [
        for (final member in members)
          if (member == null)
            null
          else
            {'speciesId': member.speciesId, 'level': member.level},
      ],
      'expected': {
        'won': result.won,
        'turns': result.turns,
        'stars': result.stars,
        'remainingHp': result.frames.isEmpty
            ? <int>[]
            : [for (final ally in result.frames.last.allies) ally.hp],
      },
    });
  }

  for (final stage in allAdventureStages) {
    add(stage.id, List.filled(5, null));
    for (final first in species) {
      for (final level in [1, 2, 3, 4, 5, 6]) {
        for (final slot in [0, 2]) {
          final squad = <({String speciesId, int level})?>[
            null,
            null,
            null,
            null,
            null,
          ];
          squad[slot] = (speciesId: first, level: level);
          add(stage.id, squad);
        }
      }
      for (final second in species) {
        for (final level in [1, 2, 3, 4, 5, 6]) {
          for (final slots in [(0, 1), (0, 2), (2, 3)]) {
            final squad = <({String speciesId, int level})?>[
              null,
              null,
              null,
              null,
              null,
            ];
            squad[slots.$1] = (speciesId: first, level: level);
            squad[slots.$2] = (speciesId: second, level: level);
            add(stage.id, squad);
          }
        }
      }
    }
    for (var rotation = 0; rotation < species.length; rotation++) {
      for (final level in [1, 3, 4, 5, 6]) {
        for (final slots in [
          [0, 1, 2],
          [0, 2, 4],
          [2, 3, 4],
        ]) {
          final squad = <({String speciesId, int level})?>[
            null,
            null,
            null,
            null,
            null,
          ];
          for (var index = 0; index < slots.length; index++) {
            squad[slots[index]] = (
              speciesId: species[(rotation + index) % species.length],
              level: level,
            );
          }
          add(stage.id, squad);
        }
        for (final first in [0, 2]) {
          final squad = <({String speciesId, int level})?>[
            for (var index = 0; index < 5; index++)
              (
                speciesId: species[(rotation + index + first) % species.length],
                level: level,
              ),
          ];
          add(stage.id, squad);
        }
      }
    }
  }
  File('supabase/functions/verify-forest-battle/battle_vectors.json')
      .writeAsStringSync(jsonEncode(vectors));
  stdout.writeln('Wrote ${vectors.length} combat parity vectors.');
}
