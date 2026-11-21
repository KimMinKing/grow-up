import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/daily_snapshot.dart';
import 'daily_sync_planner.dart';
import 'goal_sync_planner.dart';
import 'goal_sync_service.dart';
import 'growth_store.dart';

abstract class DailySyncRemote {
  Future<RemoteDailySnapshot?> fetch();
  Future<int?> put(DailySnapshot snapshot, int expectedRevision);
}

class SupabaseDailySyncRemote implements DailySyncRemote {
  SupabaseDailySyncRemote(this.client);
  final SupabaseClient client;

  @override
  Future<RemoteDailySnapshot?> fetch() async {
    final row = await client
        .from('user_daily_snapshots')
        .select('revision,snapshot')
        .maybeSingle();
    if (row == null) return null;
    return RemoteDailySnapshot(
      revision: (row['revision'] as num).toInt(),
      snapshot: DailySnapshot.fromJson(
        Map<String, dynamic>.from(row['snapshot'] as Map),
      ),
    );
  }

  @override
  Future<int?> put(DailySnapshot snapshot, int expectedRevision) async {
    final result = await client.rpc(
      'put_daily_snapshot',
      params: {
        'p_snapshot': snapshot.toJson(),
        'p_expected_revision': expectedRevision,
      },
    );
    return (result as num?)?.toInt();
  }
}

class DailySyncArchive {
  DailySyncArchive({
    required this.savedAt,
    required this.source,
    required DailySnapshot snapshot,
  }) : snapshot = DailySnapshot.fromJson(snapshot.toJson());

  final DateTime savedAt;
  final String source;
  final DailySnapshot snapshot;
}

class DailySyncCheckpointStore {
  DailySyncCheckpointStore(this.prefs);
  final SharedPreferencesAsync prefs;

  String _checkpointKey(String userId) => 'daily_sync_checkpoint_v1_$userId';
  String _archiveKey(String userId) => 'daily_sync_archives_v1_$userId';

  Future<DailySyncCheckpoint?> load(String userId) async {
    final raw = await prefs.getString(_checkpointKey(userId));
    if (raw == null) return null;
    final json = Map<String, dynamic>.from(jsonDecode(raw) as Map);
    return DailySyncCheckpoint(
      revision: (json['revision'] as num).toInt(),
      snapshot: DailySnapshot.fromJson(
        Map<String, dynamic>.from(json['snapshot'] as Map),
      ),
    );
  }

  Future<void> save(String userId, DailySyncCheckpoint checkpoint) =>
      prefs.setString(
        _checkpointKey(userId),
        jsonEncode({
          'revision': checkpoint.revision,
          'snapshot': checkpoint.snapshot.toJson(),
        }),
      );

  Future<void> clearCheckpoint(String userId) =>
      prefs.remove(_checkpointKey(userId));

  Future<List<DailySyncArchive>> archives(String userId) async {
    final raw = await prefs.getString(_archiveKey(userId));
    if (raw == null) return [];
    final rows = jsonDecode(raw) as List;
    return rows.map((row) {
      final json = Map<String, dynamic>.from(row as Map);
      return DailySyncArchive(
        savedAt: DateTime.parse(json['savedAt'] as String),
        source: json['source'] as String,
        snapshot: DailySnapshot.fromJson(
          Map<String, dynamic>.from(json['snapshot'] as Map),
        ),
      );
    }).toList();
  }

  Future<void> archive(
    String userId,
    DailySnapshot snapshot,
    String source,
  ) async {
    final previous = await archives(userId);
    final next = [
      DailySyncArchive(
        savedAt: DateTime.now().toUtc(),
        source: source,
        snapshot: snapshot,
      ),
      ...previous,
    ].take(10);
    await prefs.setString(
      _archiveKey(userId),
      jsonEncode([
        for (final item in next)
          {
            'savedAt': item.savedAt.toIso8601String(),
            'source': item.source,
            'snapshot': item.snapshot.toJson(),
          },
      ]),
    );
  }

  Future<void> clearLocalData(String? userId) async {
    if (userId == null) return;
    await prefs.remove(_checkpointKey(userId));
    await prefs.remove(_archiveKey(userId));
  }
}

class DailySyncConflict {
  DailySyncConflict({required DailySnapshot local, required this.remote})
    : local = DailySnapshot.fromJson(local.toJson());
  final DailySnapshot local;
  final RemoteDailySnapshot? remote;
}

class DailySyncResult {
  const DailySyncResult({required this.action, this.conflict});
  final DailySyncAction action;
  final DailySyncConflict? conflict;
}

class DailySyncService {
  DailySyncService({
    required this.store,
    required this.remote,
    required this.checkpoints,
    required this.ownerBinding,
    required this.userId,
  });

  final GrowthStore store;
  final DailySyncRemote remote;
  final DailySyncCheckpointStore checkpoints;
  final GoalSyncCheckpointStore ownerBinding;
  final String? Function() userId;

  String _signedInUser() => userId() ?? (throw StateError('로그인 후 동기화할 수 있어요.'));

  void _checkUser(String owner) {
    if (userId() != owner) throw StateError('로그인 계정이 바뀌었어요.');
  }

  Future<DailySyncResult> sync() async {
    final owner = _signedInUser();
    final existingOwner = await ownerBinding.ownerId;
    if (existingOwner != null && existingOwner != owner) {
      throw StateError('다른 계정과 동기화한 기기예요. 기록을 옮기기 전에 계정을 확인해 주세요.');
    }
    final server = await remote.fetch();
    _checkUser(owner);
    await ownerBinding.bindOwner(owner);
    final checkpoint = await checkpoints.load(owner);
    final local = store.dailySnapshot;
    final decision = decideDailySync(
      local: local,
      remote: server,
      checkpoint: checkpoint,
    );
    if (decision.action == DailySyncAction.upload) {
      _checkUser(owner);
      if (!goalSnapshotsEqual(local.toJson(), store.dailySnapshot.toJson())) {
        return DailySyncResult(
          action: DailySyncAction.conflict,
          conflict: DailySyncConflict(
            local: store.dailySnapshot,
            remote: server,
          ),
        );
      }
      final revision = await remote.put(local, decision.expectedRevision!);
      _checkUser(owner);
      if (revision == null) {
        return DailySyncResult(
          action: DailySyncAction.conflict,
          conflict: DailySyncConflict(
            local: store.dailySnapshot,
            remote: server,
          ),
        );
      }
      await checkpoints.save(
        owner,
        DailySyncCheckpoint(revision: revision, snapshot: local),
      );
    } else if (decision.action == DailySyncAction.download && server != null) {
      _checkUser(owner);
      final applied = await store.replaceSyncedDaily(
        server.snapshot,
        expectedLocal: local,
      );
      if (!applied) {
        return DailySyncResult(
          action: DailySyncAction.conflict,
          conflict: DailySyncConflict(
            local: store.dailySnapshot,
            remote: server,
          ),
        );
      }
      await checkpoints.save(
        owner,
        DailySyncCheckpoint(
          revision: server.revision,
          snapshot: server.snapshot,
        ),
      );
    } else if (decision.action == DailySyncAction.unchanged && server != null) {
      await checkpoints.save(
        owner,
        DailySyncCheckpoint(
          revision: server.revision,
          snapshot: server.snapshot,
        ),
      );
    }
    return DailySyncResult(
      action: decision.action,
      conflict: decision.action == DailySyncAction.conflict
          ? DailySyncConflict(local: local, remote: server)
          : null,
    );
  }

  Future<void> resolve(
    DailySyncConflict conflict, {
    required bool keepLocal,
  }) async {
    final owner = _signedInUser();
    await ownerBinding.bindOwner(owner);
    final fresh = await remote.fetch();
    _checkUser(owner);
    if (fresh?.revision != conflict.remote?.revision ||
        !goalSnapshotsEqual(
          fresh?.snapshot.toJson(),
          conflict.remote?.snapshot.toJson(),
        )) {
      throw StateError('서버 기록이 바뀌었어요. 다시 동기화해 주세요.');
    }
    final current = store.dailySnapshot;
    if (!goalSnapshotsEqual(current.toJson(), conflict.local.toJson())) {
      throw StateError('이 기기의 기록이 바뀌었어요. 다시 동기화해 주세요.');
    }
    if (keepLocal) {
      if (fresh != null) {
        await checkpoints.archive(owner, fresh.snapshot, '서버 기록');
      }
      final revision = await remote.put(current, fresh?.revision ?? 0);
      _checkUser(owner);
      if (revision == null) throw StateError('서버 기록이 바뀌었어요. 다시 동기화해 주세요.');
      await checkpoints.save(
        owner,
        DailySyncCheckpoint(revision: revision, snapshot: current),
      );
    } else {
      if (fresh == null) throw StateError('서버에 기록이 없어요.');
      await checkpoints.archive(owner, current, '이 기기 기록');
      final applied = await store.replaceSyncedDaily(
        fresh.snapshot,
        expectedLocal: current,
      );
      if (!applied) throw StateError('이 기기의 기록이 바뀌었어요. 다시 동기화해 주세요.');
      await checkpoints.save(
        owner,
        DailySyncCheckpoint(revision: fresh.revision, snapshot: fresh.snapshot),
      );
    }
  }

  Future<void> restoreArchive(DailySyncArchive archive) async {
    final owner = _signedInUser();
    await ownerBinding.bindOwner(owner);
    final current = store.dailySnapshot;
    await checkpoints.archive(owner, current, '복원 전 기록');
    await checkpoints.clearCheckpoint(owner);
    final applied = await store.replaceSyncedDaily(
      archive.snapshot,
      expectedLocal: current,
    );
    if (!applied) throw StateError('이 기기의 기록이 바뀌었어요. 다시 시도해 주세요.');
  }
}
