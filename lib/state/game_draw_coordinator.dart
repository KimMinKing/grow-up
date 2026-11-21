import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import 'game_expedition_remote.dart';

class GameDrawCoordinator {
  GameDrawCoordinator({
    required this.prefs,
    required this.remote,
    String Function()? newRequestId,
  }) : _newRequestId = newRequestId ?? const Uuid().v4;

  final SharedPreferencesAsync prefs;
  final GameExpeditionRemote remote;
  final String Function() _newRequestId;

  Future<bool> hasPendingRequest(String userId) async {
    if (userId.isEmpty) return false;
    return await prefs.getString(_pendingKey(userId)) != null;
  }

  Future<GameDrawResult> draw(String userId) async {
    if (userId.isEmpty) throw ArgumentError.value(userId, 'userId');
    final key = _pendingKey(userId);
    var requestId = await prefs.getString(key);
    if (requestId == null) {
      requestId = _newRequestId();
      await prefs.setString(key, requestId);
    }
    final result = await remote.draw(requestId);
    await prefs.remove(key);
    return result;
  }

  String _pendingKey(String userId) => 'game_draw_pending_v1_$userId';
}
