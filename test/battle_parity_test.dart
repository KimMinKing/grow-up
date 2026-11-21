import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:growup/models/adventure_stage.dart';
import 'package:growup/models/battle_engine.dart';
import 'package:growup/models/game_creature.dart';

void main() {
  test('local combat matches shared server parity vectors', () {
    final file = File(
      'supabase/functions/verify-forest-battle/battle_vectors.json',
    );
    final vectors = jsonDecode(file.readAsStringSync()) as List<dynamic>;
    expect(vectors.length, 2622);
    for (final raw in vectors) {
      final vector = raw as Map<String, dynamic>;
      final stage = allAdventureStages.firstWhere(
        (item) => item.id == vector['stageId'],
      );
      final members = vector['squad'] as List<dynamic>;
      final owned = <CreatureInstance>[];
      final squad = <String?>[];
      for (var slot = 0; slot < members.length; slot++) {
        final member = members[slot];
        if (member == null) {
          squad.add(null);
        } else {
          final values = member as Map<String, dynamic>;
          final id = 'member-$slot';
          squad.add(id);
          owned.add(
            CreatureInstance(
              id: id,
              speciesId: values['speciesId'] as String,
              level: values['level'] as int,
            ),
          );
        }
      }
      final result = BattleEngine.simulate(stage, squad, owned);
      final expected = vector['expected'] as Map<String, dynamic>;
      expect(result.won, expected['won'], reason: '$stage ${vector['squad']}');
      expect(
        result.turns,
        expected['turns'],
        reason: '$stage ${vector['squad']}',
      );
      expect(
        result.stars,
        expected['stars'],
        reason: '$stage ${vector['squad']}',
      );
      expect(
        result.frames.isEmpty
            ? <int>[]
            : result.frames.last.allies.map((ally) => ally.hp).toList(),
        expected['remainingHp'],
        reason: '$stage ${vector['squad']}',
      );
    }
  });
}
