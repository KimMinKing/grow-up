import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/growth_goal.dart';
import 'goal_sync_planner.dart';
import 'growth_backup.dart';
import 'growth_store.dart';

abstract class GoalSyncRemote {
  Future<List<RemoteGoalSnapshot>> fetchAll();
  Future<int?> put(
    String goalId,
    Map<String, dynamic> snapshot,
    int expectedRevision,
  );
}

class SupabaseGoalSyncRemote implements GoalSyncRemote {
  SupabaseGoalSyncRemote(this.client);

  final SupabaseClient client;

  @override
  Future<List<RemoteGoalSnapshot>> fetchAll() async {
    final goals = <RemoteGoalSnapshot>[];
    for (var offset = 0; ; offset += 500) {
      final rows = await client
          .from('user_goal_snapshots')
          .select('goal_id,revision,snapshot')
          .order('goal_id')
          .range(offset, offset + 499);
      for (final row in rows) {
        goals.add(
          RemoteGoalSnapshot(
            goalId: row['goal_id'] as String,
            revision: row['revision'] as int,
            snapshot: Map<String, dynamic>.from(row['snapshot'] as Map),
          ),
        );
      }
      if (rows.length < 500) return goals;
    }
  }

  @override
  Future<int?> put(
    String goalId,
    Map<String, dynamic> snapshot,
    int expectedRevision,
  ) async {
    final result = await client.rpc(
      'put_goal_snapshot',
      params: {
        'p_goal_id': goalId,
        'p_snapshot': snapshot,
        'p_expected_revision': expectedRevision,
      },
    );
    return result as int?;
  }
}

class GoalSyncCheckpointStore {
  GoalSyncCheckpointStore(this.prefs);

  final SharedPreferencesAsync prefs;
  static const _ownerKey = 'goal_sync_owner_v1';

  Future<String?> get ownerId => prefs.getString(_ownerKey);

  Future<void> clearLocalData() async {
    final owner = await ownerId;
    if (owner != null) {
      await prefs.remove('goal_sync_checkpoints_v1_$owner');
    }
    await prefs.remove(_ownerKey);
  }

  Future<void> bindOwner(String userId) async {
    final owner = await ownerId;
    if (owner != null && owner != userId) {
      throw StateError('다른 계정과 동기화한 기기예요. 기록을 옮기기 전에 계정을 확인해 주세요.');
    }
    if (owner == null) await prefs.setString(_ownerKey, userId);
  }

  Future<Map<String, GoalSyncCheckpoint>> load(String userId) async {
    final raw = await prefs.getString('goal_sync_checkpoints_v1_$userId');
    if (raw == null) return {};
    final decoded = jsonDecode(raw) as Map<String, dynamic>;
    return decoded.map((id, value) {
      final data = Map<String, dynamic>.from(value as Map);
      return MapEntry(
        id,
        GoalSyncCheckpoint(
          revision: data['revision'] as int,
          snapshot: Map<String, dynamic>.from(data['snapshot'] as Map),
        ),
      );
    });
  }

  Future<void> save(
    String userId,
    Map<String, GoalSyncCheckpoint> checkpoints,
  ) async {
    await prefs.setString(
      'goal_sync_checkpoints_v1_$userId',
      jsonEncode(
        checkpoints.map(
          (id, value) => MapEntry(id, {
            'revision': value.revision,
            'snapshot': value.snapshot,
          }),
        ),
      ),
    );
  }
}

class GoalSyncConflict {
  GoalSyncConflict({
    required this.goalId,
    required this.local,
    required this.remote,
  }) : localSnapshot = local == null ? null : _copy(local.toJson());

  final String goalId;
  final GrowthGoal? local;
  final Map<String, dynamic>? localSnapshot;
  final RemoteGoalSnapshot? remote;
}

class GoalSyncResult {
  const GoalSyncResult({
    required this.uploaded,
    required this.downloaded,
    required this.conflicts,
  });

  final int uploaded;
  final int downloaded;
  final List<GoalSyncConflict> conflicts;
}

class GoalSyncService {
  GoalSyncService({
    required this.store,
    required this.remote,
    required this.checkpoints,
    required this.userId,
  });

  final GrowthStore store;
  final GoalSyncRemote remote;
  final GoalSyncCheckpointStore checkpoints;
  final String? Function() userId;

  String _signedInUser() => userId() ?? (throw StateError('로그인 후 동기화할 수 있어요.'));

  void _checkUser(String owner) {
    if (userId() != owner) throw StateError('로그인 계정이 바뀌었어요.');
  }

  Future<GoalSyncResult> sync() async {
    final owner = _signedInUser();
    final existingOwner = await checkpoints.ownerId;
    if (existingOwner != null && existingOwner != owner) {
      throw StateError('다른 계정과 동기화한 기기예요. 기록을 옮기기 전에 계정을 확인해 주세요.');
    }
    final remoteRows = await remote.fetchAll();
    _checkUser(owner);
    final remoteById = <String, RemoteGoalSnapshot>{};
    for (final row in remoteRows) {
      if (remoteById.containsKey(row.goalId) ||
          row.revision < 1 ||
          row.snapshot['id'] != row.goalId) {
        throw const FormatException('서버 목표 자료를 확인하지 못했어요.');
      }
      try {
        GrowthBackup.decodeGoal(row.snapshot);
      } on FormatException {
        throw const FormatException('서버 목표 자료를 확인하지 못했어요.');
      }
      remoteById[row.goalId] = row;
    }
    await checkpoints.bindOwner(owner);
    _checkUser(owner);
    final cursors = await checkpoints.load(owner);
    _checkUser(owner);
    final localById = {
      for (final goal in store.allGoals.where((goal) => !goal.localBackup))
        goal.id: goal,
    };
    final ids = {...localById.keys, ...remoteById.keys}.toList()..sort();
    final conflicts = <GoalSyncConflict>[];
    var uploaded = 0;
    var downloaded = 0;

    for (final id in ids) {
      _checkUser(owner);
      final local = localById[id];
      final server = remoteById[id];
      final decision = decideGoalSync(
        local: local,
        remote: server,
        checkpoint: cursors[id],
      );
      if (decision.action == GoalSyncAction.upload && local != null) {
        final snapshot = _copy(local.toJson());
        if (store.goalById(id) != local ||
            !goalSnapshotsEqual(local.toJson(), snapshot)) {
          conflicts.add(
            GoalSyncConflict(goalId: id, local: local, remote: server),
          );
          continue;
        }
        final revision = await remote.put(
          id,
          snapshot,
          decision.expectedRevision!,
        );
        _checkUser(owner);
        if (revision == null) {
          conflicts.add(
            GoalSyncConflict(goalId: id, local: local, remote: server),
          );
          continue;
        }
        cursors[id] = GoalSyncCheckpoint(
          revision: revision,
          snapshot: snapshot,
        );
        await checkpoints.save(owner, cursors);
        uploaded++;
      } else if (decision.action == GoalSyncAction.download && server != null) {
        final expected = local == null ? null : _copy(local.toJson());
        final applied = await store.importSyncedGoal(
          GrowthGoal.fromJson(server.snapshot),
          expectedLocal: expected,
        );
        _checkUser(owner);
        if (!applied) {
          conflicts.add(
            GoalSyncConflict(goalId: id, local: local, remote: server),
          );
          continue;
        }
        cursors[id] = GoalSyncCheckpoint(
          revision: server.revision,
          snapshot: server.snapshot,
        );
        await checkpoints.save(owner, cursors);
        downloaded++;
      } else if (decision.action == GoalSyncAction.unchanged &&
          server != null) {
        cursors[id] = GoalSyncCheckpoint(
          revision: server.revision,
          snapshot: server.snapshot,
        );
        await checkpoints.save(owner, cursors);
      } else if (decision.action == GoalSyncAction.conflict) {
        conflicts.add(
          GoalSyncConflict(goalId: id, local: local, remote: server),
        );
      }
    }
    _checkUser(owner);
    return GoalSyncResult(
      uploaded: uploaded,
      downloaded: downloaded,
      conflicts: conflicts,
    );
  }

  Future<void> resolve(
    GoalSyncConflict conflict, {
    required bool keepLocal,
  }) async {
    final owner = _signedInUser();
    await checkpoints.bindOwner(owner);
    _checkUser(owner);
    final fresh = (await remote.fetchAll())
        .where((row) => row.goalId == conflict.goalId)
        .firstOrNull;
    _checkUser(owner);
    if (fresh != null) {
      try {
        if (fresh.revision < 1 || fresh.snapshot['id'] != fresh.goalId) {
          throw const FormatException();
        }
        GrowthBackup.decodeGoal(fresh.snapshot);
      } on FormatException {
        throw const FormatException('서버 목표 자료를 확인하지 못했어요.');
      }
    }
    final original = conflict.remote;
    if ((fresh?.revision != original?.revision) ||
        !goalSnapshotsEqual(fresh?.snapshot, original?.snapshot)) {
      throw StateError('서버 기록이 바뀌었어요. 다시 동기화해 주세요.');
    }
    final local = store.goalById(conflict.goalId);
    if (!goalSnapshotsEqual(local?.toJson(), conflict.localSnapshot)) {
      throw StateError('이 기기의 기록이 바뀌었어요. 다시 동기화해 주세요.');
    }
    final cursors = await checkpoints.load(owner);
    _checkUser(owner);
    if (keepLocal) {
      if (local == null) throw StateError('이 기기에 목표가 없어요.');
      if (fresh != null) await store.addSyncBackup(fresh.snapshot);
      _checkUser(owner);
      final snapshot = _copy(local.toJson());
      final revision = await remote.put(
        conflict.goalId,
        snapshot,
        fresh?.revision ?? 0,
      );
      _checkUser(owner);
      if (revision == null) throw StateError('서버 기록이 바뀌었어요. 다시 동기화해 주세요.');
      cursors[conflict.goalId] = GoalSyncCheckpoint(
        revision: revision,
        snapshot: snapshot,
      );
    } else {
      if (fresh == null) throw StateError('서버에 목표가 없어요.');
      final applied = await store.importSyncedGoal(
        GrowthGoal.fromJson(fresh.snapshot),
        expectedLocal: local == null ? null : _copy(local.toJson()),
        keepLocalBackup: local != null,
      );
      _checkUser(owner);
      if (!applied) throw StateError('목표가 바뀌었거나 진행 중인 목표가 5개예요.');
      cursors[conflict.goalId] = GoalSyncCheckpoint(
        revision: fresh.revision,
        snapshot: fresh.snapshot,
      );
    }
    _checkUser(owner);
    await checkpoints.save(owner, cursors);
  }
}

Map<String, dynamic> _copy(Map<String, dynamic> value) =>
    Map<String, dynamic>.from(jsonDecode(jsonEncode(value)) as Map);
