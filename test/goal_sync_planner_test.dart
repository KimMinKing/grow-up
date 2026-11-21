import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:growup/models/growth_goal.dart';
import 'package:growup/state/goal_sync_planner.dart';

GrowthGoal sampleGoal() => GrowthGoal(
  id: 'goal-1',
  title: '독서',
  mini: '2쪽',
  more: '15분',
  max: '40분',
  path: '균형 있게',
  weeklyTarget: 3,
  milestones: ['첫 책'],
  createdAt: DateTime(2026, 10, 31),
);

Map<String, dynamic> snapshotOf(GrowthGoal goal) =>
    Map<String, dynamic>.from(jsonDecode(jsonEncode(goal.toJson())) as Map);

void main() {
  test('old snapshots stay equal and new goal dates sync together', () {
    final old = sampleGoal().toJson()..remove('startDate');
    final restoredOld = GrowthGoal.fromJson(old);
    expect(restoredOld.startDay, '2026-10-31');
    expect(goalSnapshotsEqual(restoredOld.toJson(), old), isTrue);

    restoredOld.startDate = '2026-11-01';
    restoredOld.targetDate = '2026-12-31';
    final remote = RemoteGoalSnapshot(
      goalId: restoredOld.id,
      revision: 2,
      snapshot: restoredOld.toJson(),
    );
    final downloaded = GrowthGoal.fromJson(remote.snapshot);
    expect(downloaded.startDay, '2026-11-01');
    expect(downloaded.targetDate, '2026-12-31');
  });

  test('first upload and download keep existing goal snapshots', () {
    final goal = sampleGoal();
    expect(
      decideGoalSync(local: goal, remote: null, checkpoint: null).action,
      GoalSyncAction.upload,
    );
    expect(
      decideGoalSync(
        local: goal,
        remote: null,
        checkpoint: null,
      ).expectedRevision,
      0,
    );
    expect(
      decideGoalSync(
        local: null,
        remote: RemoteGoalSnapshot(
          goalId: goal.id,
          revision: 1,
          snapshot: goal.toJson(),
        ),
        checkpoint: null,
      ).action,
      GoalSyncAction.download,
    );
  });

  test('one-sided edit can advance the matching revision', () {
    final goal = sampleGoal();
    final baseline = snapshotOf(goal);
    final checkpoint = GoalSyncCheckpoint(revision: 4, snapshot: baseline);
    goal.completions['2026-10-31'] = 'MINI';
    final remote = RemoteGoalSnapshot(
      goalId: goal.id,
      revision: 4,
      snapshot: baseline,
    );
    final upload = decideGoalSync(
      local: goal,
      remote: remote,
      checkpoint: checkpoint,
    );
    expect(upload.action, GoalSyncAction.upload);
    expect(upload.expectedRevision, 4);

    final unchangedLocal = GrowthGoal.fromJson(baseline);
    final advancedRemote = RemoteGoalSnapshot(
      goalId: goal.id,
      revision: 5,
      snapshot: goal.toJson(),
    );
    expect(
      decideGoalSync(
        local: unchangedLocal,
        remote: advancedRemote,
        checkpoint: checkpoint,
      ).action,
      GoalSyncAction.download,
    );
  });

  test('two edited devices and unknown baseline never overwrite either', () {
    final goal = sampleGoal();
    final baseline = snapshotOf(goal);
    final checkpoint = GoalSyncCheckpoint(revision: 2, snapshot: baseline);
    goal.completions['2026-10-31'] = 'MINI';
    final remoteJson = sampleGoal().toJson();
    (remoteJson['completions'] as Map<String, String>)['2026-10-30'] = 'MAX';
    final remote = RemoteGoalSnapshot(
      goalId: goal.id,
      revision: 3,
      snapshot: remoteJson,
    );
    expect(
      decideGoalSync(
        local: goal,
        remote: remote,
        checkpoint: checkpoint,
      ).action,
      GoalSyncAction.conflict,
    );
    expect(
      decideGoalSync(local: goal, remote: remote, checkpoint: null).action,
      GoalSyncAction.conflict,
    );
    expect(
      decideGoalSync(
        local: GrowthGoal.fromJson(baseline),
        remote: RemoteGoalSnapshot(
          goalId: goal.id,
          revision: 1,
          snapshot: baseline,
        ),
        checkpoint: checkpoint,
      ).action,
      GoalSyncAction.conflict,
    );
    expect(goal.completions['2026-10-31'], 'MINI');
    expect(remoteJson['completions'], {'2026-10-30': 'MAX'});
  });
}
