import 'game_creature.dart';
import 'adventure_stage.dart';
import 'reward_grant.dart';

const adventureTrainingThresholds = [1, 3, 7];

/// Local training collection only. Server expedition and draw data stay on the server.
class GameSnapshot {
  const GameSnapshot._({
    required this.owned,
    required this.squad,
    required this.discoveredSpeciesIds,
    required this.trainingEndsAt,
    required this.trainingCompletions,
    required this.adventureClears,
    required this.trainingPasses,
    required this.creditedTaskIds,
    required this.rewardGrants,
    required this.stageProgress,
  });

  final List<CreatureInstance> owned;
  final List<String?> squad;
  final Set<String> discoveredSpeciesIds;
  final DateTime? trainingEndsAt;
  final int trainingCompletions;
  final int adventureClears;
  final int trainingPasses;
  final Set<String> creditedTaskIds;
  final List<RewardGrant> rewardGrants;
  final Map<String, StageProgress> stageProgress;

  factory GameSnapshot.fromJson(Map<String, dynamic> data) {
    try {
      if (data['version'] != 1 ||
          data['owned'] is! List ||
          data['squad'] is! List ||
          data['discoveredSpeciesIds'] is! List ||
          data['trainingCompletions'] is! int) {
        throw const FormatException('게임 자료가 올바르지 않아요.');
      }
      final items = data['owned'] as List;
      final slots = data['squad'] as List;
      final discoveries = data['discoveredSpeciesIds'] as List;
      final completions = data['trainingCompletions'] as int;
      final rawClears = data['adventureClears'];
      final clears =
          rawClears ??
          adventureTrainingThresholds.where((at) => completions >= at).length;
      final passes = data['trainingPasses'] ?? 0;
      final rawCredited = data['creditedTaskIds'] ?? const [];
      final rawGrants = data['rewardGrants'] ?? const [];
      final rawEnd = data['trainingEndsAt'];
      final rawStageProgress = data['stageProgress'];
      if (items.isEmpty ||
          items.length > 20 ||
          slots.length != 5 ||
          completions < 0 ||
          clears is! int ||
          clears < 0 ||
          clears > adventureTrainingThresholds.length ||
          (clears > 0 &&
              completions < adventureTrainingThresholds[clears - 1]) ||
          passes is! int ||
          passes < 0 ||
          passes > 100000 ||
          rawCredited is! List ||
          rawCredited.length > 100000 ||
          rawGrants is! List ||
          rawGrants.length > 100000 ||
          discoveries.length > allCreatureSpecies.length ||
          (rawEnd != null &&
              (rawEnd is! String || DateTime.tryParse(rawEnd) == null))) {
        throw const FormatException('게임 자료가 올바르지 않아요.');
      }
      final owned = items
          .map(
            (item) => CreatureInstance.fromJson(
              Map<String, dynamic>.from(item as Map),
            ),
          )
          .toList();
      final ids = owned.map((item) => item.id).toSet();
      final squad = slots.map((id) => id as String?).toList();
      final discovered = discoveries.map((id) => id as String).toSet();
      final credited = rawCredited.map((id) => id as String).toSet();
      final grants = rawGrants
          .map(
            (item) =>
                RewardGrant.fromJson(Map<String, dynamic>.from(item as Map)),
          )
          .toList();
      final grantIds = grants.map((item) => item.sourceId).toSet();
      if (ids.length != owned.length ||
          credited.length != rawCredited.length ||
          credited.any((id) => id.isEmpty || id.length > 100) ||
          grantIds.length != grants.length ||
          discovered.length != discoveries.length ||
          discovered.any((id) => speciesById(id) == null) ||
          owned.any((item) => !discovered.contains(item.speciesId)) ||
          squad.any((id) => id != null && !ids.contains(id)) ||
          squad.whereType<String>().toSet().length !=
              squad.whereType<String>().length ||
          (rawEnd != null && squad.every((id) => id == null))) {
        throw const FormatException('게임 자료가 올바르지 않아요.');
      }
      for (final id in credited) {
        if (grantIds.add(id)) grants.add(RewardGrant.fromLegacyTaskId(id));
      }
      if (grants.length > 100000) {
        throw const FormatException('Too many reward grants');
      }
      final progress = readStageProgress(rawStageProgress, clears);
      return GameSnapshot._(
        owned: List.unmodifiable(owned),
        squad: List.unmodifiable(squad),
        discoveredSpeciesIds: Set.unmodifiable(discovered),
        trainingEndsAt: rawEnd == null ? null : DateTime.parse(rawEnd).toUtc(),
        trainingCompletions: completions,
        adventureClears: clears,
        trainingPasses: passes,
        creditedTaskIds: Set.unmodifiable(credited),
        rewardGrants: List.unmodifiable(grants),
        stageProgress: Map.unmodifiable(progress),
      );
    } on FormatException {
      rethrow;
    } catch (_) {
      throw const FormatException('게임 자료가 올바르지 않아요.');
    }
  }

  Map<String, Object?> toJson() => {
    'version': 1,
    'owned': owned.map((item) => item.toJson()).toList(),
    'squad': squad,
    'discoveredSpeciesIds': discoveredSpeciesIds.toList(),
    'trainingEndsAt': trainingEndsAt?.toIso8601String(),
    'trainingCompletions': trainingCompletions,
    'adventureClears': adventureClears,
    'trainingPasses': trainingPasses,
    'creditedTaskIds': creditedTaskIds.toList(),
    'rewardGrants': rewardGrants.map((item) => item.toJson()).toList(),
    'stageProgress': stageProgress.map(
      (id, record) => MapEntry(id, record.toJson()),
    ),
  };
}
