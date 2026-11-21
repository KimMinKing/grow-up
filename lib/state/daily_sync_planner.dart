import '../models/daily_snapshot.dart';
import 'goal_sync_planner.dart';

enum DailySyncAction { upload, download, unchanged, conflict }

class RemoteDailySnapshot {
  RemoteDailySnapshot({required this.revision, required DailySnapshot snapshot})
    : snapshot = DailySnapshot.fromJson(snapshot.toJson());
  final int revision;
  final DailySnapshot snapshot;
}

class DailySyncCheckpoint {
  DailySyncCheckpoint({required this.revision, required DailySnapshot snapshot})
    : snapshot = DailySnapshot.fromJson(snapshot.toJson());
  final int revision;
  final DailySnapshot snapshot;
}

class DailySyncDecision {
  const DailySyncDecision(this.action, {this.expectedRevision});
  final DailySyncAction action;
  final int? expectedRevision;
}

DailySyncDecision decideDailySync({
  required DailySnapshot local,
  required RemoteDailySnapshot? remote,
  required DailySyncCheckpoint? checkpoint,
}) {
  if (remote == null) {
    return checkpoint == null
        ? const DailySyncDecision(DailySyncAction.upload, expectedRevision: 0)
        : const DailySyncDecision(DailySyncAction.conflict);
  }
  if (remote.revision < 1 ||
      (checkpoint != null && remote.revision < checkpoint.revision)) {
    return const DailySyncDecision(DailySyncAction.conflict);
  }
  final localJson = local.toJson();
  final remoteJson = remote.snapshot.toJson();
  if (goalSnapshotsEqual(localJson, remoteJson)) {
    return const DailySyncDecision(DailySyncAction.unchanged);
  }
  if (checkpoint == null) {
    return const DailySyncDecision(DailySyncAction.conflict);
  }
  final baseline = checkpoint.snapshot.toJson();
  if (remote.revision == checkpoint.revision &&
      goalSnapshotsEqual(remoteJson, baseline)) {
    return DailySyncDecision(
      DailySyncAction.upload,
      expectedRevision: remote.revision,
    );
  }
  if (remote.revision > checkpoint.revision &&
      goalSnapshotsEqual(localJson, baseline)) {
    return const DailySyncDecision(DailySyncAction.download);
  }
  return const DailySyncDecision(DailySyncAction.conflict);
}
