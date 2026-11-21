import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import 'game_battle_remote.dart';

class PendingServerBattle {
  const PendingServerBattle(this.stageId, this.requestId);
  final String stageId;
  final String requestId;
}

class GameBattleCoordinator {
  GameBattleCoordinator({
    required this.prefs,
    required this.remote,
    String Function()? newRequestId,
  }) : _newRequestId = newRequestId ?? const Uuid().v4;

  final SharedPreferencesAsync prefs;
  final GameBattleRemote remote;
  final String Function() _newRequestId;

  Future<PendingServerBattle?> pending(String userId) async {
    if (userId.isEmpty) return null;
    final saved = await prefs.getString(_pendingKey(userId));
    if (saved == null) return null;
    final parts = saved.split('|');
    if (parts.length != 2 || parts.any((part) => part.isEmpty)) {
      await prefs.remove(_pendingKey(userId));
      return null;
    }
    return PendingServerBattle(parts[0], parts[1]);
  }

  Future<ServerBattleResult> battle(String userId, String stageId) async {
    if (userId.isEmpty) throw ArgumentError.value(userId, 'userId');
    final key = _pendingKey(userId);
    var attempt = await pending(userId);
    if (attempt == null) {
      attempt = PendingServerBattle(stageId, _newRequestId());
      await prefs.setString(key, '${attempt.stageId}|${attempt.requestId}');
    }
    late final ServerBattleResult result;
    try {
      result = await remote.battle(attempt.stageId, attempt.requestId);
    } on FunctionException catch (error) {
      final details = error.details;
      if (details is Map &&
          (details['error'] == 'battle_attempt_expired' ||
              (error.status == 409 &&
                  details['error'] == 'battle_start_failed'))) {
        await prefs.remove(key);
      }
      rethrow;
    }
    if (result.requestId != attempt.requestId ||
        result.stageId != attempt.stageId) {
      throw const FormatException('Server battle request mismatch');
    }
    await prefs.remove(key);
    return result;
  }

  String _pendingKey(String userId) => 'game_battle_pending_v1_$userId';
}
