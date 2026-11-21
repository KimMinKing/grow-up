import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/adventure_stage.dart';

class ServerStageRecord {
  const ServerStageRecord({
    required this.stageId,
    required this.stars,
    required this.bestTurns,
  });

  final String stageId;
  final int stars;
  final int bestTurns;
}

/// The battle attempts table is server written and readable only by its owner.
/// Two ordered single-row queries avoid truncating long battle histories.
Future<Map<String, ServerStageRecord>> loadServerStageRecords(
  SupabaseClient client,
) async {
  final entries = await Future.wait(
    allAdventureStages.map((stage) async {
      final bestStars = await client
          .from('game_battle_attempts')
          .select('stars,turns')
          .eq('stage_id', stage.id)
          .eq('status', 'resolved')
          .eq('won', true)
          .order('stars', ascending: false)
          .order('turns')
          .limit(1);
      if (bestStars.isEmpty) return null;
      final bestTurns = await client
          .from('game_battle_attempts')
          .select('turns')
          .eq('stage_id', stage.id)
          .eq('status', 'resolved')
          .eq('won', true)
          .order('turns')
          .limit(1);
      final stars = bestStars.first['stars'];
      final turns = bestTurns.first['turns'];
      if (stars is! int ||
          stars < 1 ||
          stars > 3 ||
          turns is! int ||
          turns < 1 ||
          turns > 30) {
        throw const FormatException('Invalid server stage record');
      }
      return ServerStageRecord(
        stageId: stage.id,
        stars: stars,
        bestTurns: turns,
      );
    }),
  );
  return {
    for (final entry in entries.whereType<ServerStageRecord>())
      entry.stageId: entry,
  };
}

class ServerExpedition {
  const ServerExpedition({required this.id, required this.readyAt});

  final String id;
  final DateTime readyAt;

  factory ServerExpedition.fromJson(Map<String, dynamic> json) =>
      ServerExpedition(
        id: json['id'] as String,
        readyAt: DateTime.parse(json['ready_at'] as String).toUtc(),
      );
}

class ServerCreature {
  const ServerCreature({
    required this.id,
    required this.speciesId,
    required this.level,
    this.battleExperience = 0,
  });

  final String id;
  final String speciesId;
  final int level;
  final int battleExperience;

  int get experienceToNextLevel => level >= 6 ? 0 : 3 - battleExperience;

  factory ServerCreature.fromJson(Map<String, dynamic> json) => ServerCreature(
    id: json['id'] as String,
    speciesId: json['species_id'] as String,
    level: (json['level'] as num).toInt(),
    battleExperience: (json['battle_experience'] as num?)?.toInt() ?? 0,
  );
}

class ServerStageFirstClear {
  const ServerStageFirstClear({
    required this.stageId,
    required this.badgeId,
    required this.awardedShards,
  });

  final String stageId;
  final String badgeId;
  final int awardedShards;

  factory ServerStageFirstClear.fromJson(Map<String, dynamic> json) =>
      ServerStageFirstClear(
        stageId: json['stage_id'] as String,
        badgeId: json['badge_id'] as String,
        awardedShards: (json['awarded_shards'] as num).toInt(),
      );
}

class ServerGameState {
  const ServerGameState({
    required this.serverNow,
    required this.starterSpeciesId,
    required this.drawShards,
    required this.activeExpedition,
    required this.todayStarts,
    required this.ownedCount,
    required this.discoveredSpeciesIds,
    required this.drawCount,
    required this.owned,
    required this.squad,
    this.stageFirstClears = const [],
    this.stageRecords = const {},
    this.todayBattleAttempts = 0,
    this.todayStageExperienceWins = const {},
    this.battlePasses = 2,
  });

  final DateTime serverNow;
  final String? starterSpeciesId;
  final int drawShards;
  final ServerExpedition? activeExpedition;
  final int todayStarts;
  final int ownedCount;
  final Set<String> discoveredSpeciesIds;
  final int drawCount;
  final List<ServerCreature> owned;
  final List<String?> squad;
  final List<ServerStageFirstClear> stageFirstClears;
  final Map<String, ServerStageRecord> stageRecords;
  final int todayBattleAttempts;
  final Map<String, int> todayStageExperienceWins;
  final int battlePasses;
}

class GameDrawResult {
  const GameDrawResult({
    required this.creatureId,
    required this.speciesId,
    required this.remainingShards,
    required this.guaranteed,
    required this.alreadyDrawn,
  });

  final String creatureId;
  final String speciesId;
  final int remainingShards;
  final bool guaranteed;
  final bool alreadyDrawn;

  factory GameDrawResult.fromJson(Map<String, dynamic> json) => GameDrawResult(
    creatureId: json['creatureId'] as String,
    speciesId: json['speciesId'] as String,
    remainingShards: (json['remainingShards'] as num).toInt(),
    guaranteed: json['guaranteed'] as bool,
    alreadyDrawn: json['alreadyDrawn'] as bool,
  );
}

abstract class GameExpeditionRemote {
  Future<ServerGameState> load();
  Future<void> claimStarter(String speciesId);
  Future<void> start();
  Future<int> claim(String expeditionId);
  Future<GameDrawResult> draw(String requestId);
  Future<void> setSquadSlot(String creatureId, int slot);
  Future<int> claimTaskBattlePasses();
}

class SupabaseGameExpeditionRemote implements GameExpeditionRemote {
  SupabaseGameExpeditionRemote(
    this.client, {
    this.drawEnabled = false,
    this.stageRewardsEnabled = false,
  });

  final SupabaseClient client;
  final bool drawEnabled;
  final bool stageRewardsEnabled;

  @override
  Future<ServerGameState> load() async {
    final creatures = await client
        .from('game_creature_instances')
        .select('id,species_id,source,level,battle_experience');
    final starter = creatures
        .where((item) => item['source'] == 'starter')
        .firstOrNull;
    final slots = await client
        .from('game_squad_slots')
        .select('slot,creature_id');
    final squad = List<String?>.filled(5, null);
    for (final row in slots) {
      final slot = (row['slot'] as num).toInt();
      if (slot >= 1 && slot <= 5) {
        squad[slot - 1] = row['creature_id'] as String;
      }
    }
    final wallet = await client
        .from('game_wallets')
        .select('draw_shards,battle_passes')
        .maybeSingle();
    final active = await client
        .from('game_expeditions')
        .select('id,ready_at')
        .isFilter('claimed_at', null)
        .maybeSingle();
    final draws = drawEnabled
        ? await client.from('game_draw_requests').select('request_id')
        : null;
    final rewardStatusResult = stageRewardsEnabled
        ? await client.rpc('get_game_stage_reward_status')
        : null;
    final rewardStatus = rewardStatusResult == null
        ? null
        : Map<String, dynamic>.from(rewardStatusResult as Map);
    final stageRecords = stageRewardsEnabled
        ? await loadServerStageRecords(client)
        : const <String, ServerStageRecord>{};
    final statusResult = await client.rpc('get_game_status');
    final status = Map<String, dynamic>.from(statusResult as Map);
    final serverNow = DateTime.parse(status['serverNow'] as String).toUtc();
    final koreaNow = serverNow.add(const Duration(hours: 9));
    final todayStart = DateTime.utc(
      koreaNow.year,
      koreaNow.month,
      koreaNow.day,
    ).subtract(const Duration(hours: 9));
    final battleAttempts = stageRewardsEnabled
        ? await client
              .from('game_battle_attempts')
              .select('stage_id,status,experience_awarded')
              .gte('started_at', todayStart.toIso8601String())
        : null;
    final experienceWins = <String, int>{};
    for (final attempt in battleAttempts ?? <Map<String, dynamic>>[]) {
      if (attempt['status'] != 'resolved' ||
          (attempt['experience_awarded'] as num).toInt() <= 0) {
        continue;
      }
      final stageId = attempt['stage_id'] as String;
      experienceWins[stageId] = (experienceWins[stageId] ?? 0) + 1;
    }
    return ServerGameState(
      serverNow: serverNow,
      starterSpeciesId: starter?['species_id'] as String?,
      drawShards:
          (rewardStatus?['draw_shards'] as num?)?.toInt() ??
          (wallet?['draw_shards'] as num?)?.toInt() ??
          0,
      activeExpedition: active == null
          ? null
          : ServerExpedition.fromJson(active),
      todayStarts: (status['todayStarts'] as num).toInt(),
      ownedCount: creatures.length,
      discoveredSpeciesIds: creatures
          .map((item) => item['species_id'] as String)
          .toSet(),
      drawCount: draws?.length ?? 0,
      owned: creatures.map(ServerCreature.fromJson).toList(),
      squad: squad,
      stageFirstClears: (rewardStatus?['first_clears'] as List<dynamic>? ?? [])
          .map(
            (item) => ServerStageFirstClear.fromJson(
              Map<String, dynamic>.from(item as Map),
            ),
          )
          .toList(),
      stageRecords: stageRecords,
      todayBattleAttempts: battleAttempts?.length ?? 0,
      todayStageExperienceWins: experienceWins,
      battlePasses: (wallet?['battle_passes'] as num?)?.toInt() ?? 2,
    );
  }

  @override
  Future<void> claimStarter(String speciesId) async {
    await client.rpc('claim_game_starter', params: {'p_species_id': speciesId});
  }

  @override
  Future<void> start() async {
    await client.rpc(
      'start_game_expedition',
      params: {'p_region_id': 'pine_forest'},
    );
  }

  @override
  Future<int> claim(String expeditionId) async {
    final result = await client.rpc(
      'claim_game_expedition',
      params: {'p_expedition_id': expeditionId},
    );
    return (result['awardedShards'] as num).toInt();
  }

  @override
  Future<GameDrawResult> draw(String requestId) async {
    final result = await client.rpc(
      'draw_game_creature',
      params: {'p_request_id': requestId},
    );
    return GameDrawResult.fromJson(Map<String, dynamic>.from(result as Map));
  }

  @override
  Future<void> setSquadSlot(String creatureId, int slot) async {
    await client.rpc(
      'set_game_squad_slot',
      params: {'p_creature_id': creatureId, 'p_slot': slot},
    );
  }

  @override
  Future<int> claimTaskBattlePasses() async {
    final result = await client.rpc('claim_game_task_battle_passes');
    return (result['addedPasses'] as num).toInt();
  }
}
