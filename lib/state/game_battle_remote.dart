import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/game_creature.dart';

class ServerBattleResult {
  const ServerBattleResult({
    required this.requestId,
    required this.stageId,
    required this.won,
    required this.stars,
    required this.turns,
    required this.experienceAwarded,
    required this.firstClearShards,
    required this.alreadyResolved,
    this.companionSpeciesId,
  });

  final String requestId;
  final String stageId;
  final bool won;
  final int stars;
  final int turns;
  final int experienceAwarded;
  final int firstClearShards;
  final bool alreadyResolved;
  final String? companionSpeciesId;

  factory ServerBattleResult.fromJson(Map<String, dynamic> json) {
    final requestId = json['requestId'];
    final stageId = json['stageId'];
    final won = json['won'];
    final stars = json['stars'];
    final turns = json['turns'];
    final experience = json['experienceAwarded'];
    final shards = json['firstClearShards'];
    final alreadyResolved = json['alreadyResolved'];
    final companionSpeciesId = json['companionSpeciesId'];
    if (requestId is! String ||
        stageId is! String ||
        won is! bool ||
        stars is! int ||
        turns is! int ||
        experience is! int ||
        shards is! int ||
        alreadyResolved is! bool ||
        (companionSpeciesId != null &&
            (companionSpeciesId is! String ||
                speciesById(companionSpeciesId) == null)) ||
        stars < 0 ||
        stars > 3 ||
        turns < 0 ||
        turns > 30 ||
        experience < 0 ||
        experience > 3 ||
        shards < 0 ||
        shards > 2) {
      throw const FormatException('Invalid server battle result');
    }
    return ServerBattleResult(
      requestId: requestId,
      stageId: stageId,
      won: won,
      stars: stars,
      turns: turns,
      experienceAwarded: experience,
      firstClearShards: shards,
      alreadyResolved: alreadyResolved,
      companionSpeciesId: companionSpeciesId as String?,
    );
  }
}

abstract class GameBattleRemote {
  Future<ServerBattleResult> battle(String stageId, String requestId);
}

class SupabaseGameBattleRemote implements GameBattleRemote {
  SupabaseGameBattleRemote(this.client);

  final SupabaseClient client;

  @override
  Future<ServerBattleResult> battle(String stageId, String requestId) async {
    final response = await client.functions.invoke(
      'verify-forest-battle',
      body: {'stageId': stageId, 'requestId': requestId},
    );
    final body = response.data;
    if (body is! Map) {
      throw const FormatException('Invalid server battle result');
    }
    return ServerBattleResult.fromJson(Map<String, dynamic>.from(body));
  }
}
