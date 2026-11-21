import 'dart:convert';

import '../models/growth_goal.dart';

enum GoalSyncAction { upload, download, unchanged, conflict }

class RemoteGoalSnapshot {
  RemoteGoalSnapshot({
    required this.goalId,
    required this.revision,
    required Map<String, dynamic> snapshot,
  }) : snapshot = _copyJson(snapshot);

  final String goalId;
  final int revision;
  final Map<String, dynamic> snapshot;
}

class GoalSyncCheckpoint {
  GoalSyncCheckpoint({
    required this.revision,
    required Map<String, dynamic> snapshot,
  }) : snapshot = _copyJson(snapshot);

  final int revision;
  final Map<String, dynamic> snapshot;
}

class GoalSyncDecision {
  const GoalSyncDecision(this.action, {this.expectedRevision});

  final GoalSyncAction action;
  final int? expectedRevision;
}

GoalSyncDecision decideGoalSync({
  required GrowthGoal? local,
  required RemoteGoalSnapshot? remote,
  required GoalSyncCheckpoint? checkpoint,
}) {
  if (local == null && remote == null) {
    return const GoalSyncDecision(GoalSyncAction.unchanged);
  }
  if (local == null) {
    return const GoalSyncDecision(GoalSyncAction.download);
  }
  if (remote == null) {
    return checkpoint == null
        ? const GoalSyncDecision(GoalSyncAction.upload, expectedRevision: 0)
        : const GoalSyncDecision(GoalSyncAction.conflict);
  }
  if (remote.goalId != local.id ||
      remote.revision < 1 ||
      (checkpoint != null && remote.revision < checkpoint.revision)) {
    return const GoalSyncDecision(GoalSyncAction.conflict);
  }

  final snapshot = local.toJson();
  if (goalSnapshotsEqual(snapshot, remote.snapshot)) {
    return const GoalSyncDecision(GoalSyncAction.unchanged);
  }
  if (checkpoint == null) {
    return const GoalSyncDecision(GoalSyncAction.conflict);
  }
  if (remote.revision == checkpoint.revision &&
      goalSnapshotsEqual(remote.snapshot, checkpoint.snapshot)) {
    return GoalSyncDecision(
      GoalSyncAction.upload,
      expectedRevision: remote.revision,
    );
  }
  if (remote.revision > checkpoint.revision &&
      goalSnapshotsEqual(snapshot, checkpoint.snapshot)) {
    return const GoalSyncDecision(GoalSyncAction.download);
  }
  return const GoalSyncDecision(GoalSyncAction.conflict);
}

bool goalSnapshotsEqual(Object? a, Object? b) {
  if (identical(a, b)) return true;
  if (a is Map && b is Map) {
    if (a.length != b.length) return false;
    for (final key in a.keys) {
      if (!b.containsKey(key) || !goalSnapshotsEqual(a[key], b[key])) {
        return false;
      }
    }
    return true;
  }
  if (a is List && b is List) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (!goalSnapshotsEqual(a[i], b[i])) return false;
    }
    return true;
  }
  return a == b;
}

Map<String, dynamic> _copyJson(Map<String, dynamic> value) =>
    Map<String, dynamic>.from(jsonDecode(jsonEncode(value)) as Map);
