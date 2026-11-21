import 'package:flutter_test/flutter_test.dart';
import 'package:growup/models/daily_content.dart';
import 'package:growup/models/daily_snapshot.dart';
import 'package:growup/state/daily_sync_planner.dart';

DailySnapshot snapshot({bool withTask = false, bool withNote = false}) =>
    DailySnapshot(
      tasks: withTask
          ? [ChecklistItem(id: 'task-1', title: '읽기', createdDay: '2026-11-01')]
          : [],
      notes: withNote
          ? [DailyNote(id: 'note-1', day: '2026-11-01', text: '시작')]
          : [],
    );

void main() {
  test('first upload and unknown empty-device history', () {
    expect(
      decideDailySync(
        local: snapshot(withTask: true),
        remote: null,
        checkpoint: null,
      ).expectedRevision,
      0,
    );
    expect(
      decideDailySync(
        local: snapshot(),
        remote: RemoteDailySnapshot(
          revision: 1,
          snapshot: snapshot(withTask: true),
        ),
        checkpoint: null,
      ).action,
      DailySyncAction.conflict,
    );
  });

  test('one-sided edit, including deletion, advances safely', () {
    final baseline = snapshot(withTask: true);
    final checkpoint = DailySyncCheckpoint(revision: 2, snapshot: baseline);
    final remote = RemoteDailySnapshot(revision: 2, snapshot: baseline);
    final deletion = decideDailySync(
      local: snapshot(),
      remote: remote,
      checkpoint: checkpoint,
    );
    expect(deletion.action, DailySyncAction.upload);
    expect(deletion.expectedRevision, 2);
    expect(
      decideDailySync(
        local: baseline,
        remote: RemoteDailySnapshot(
          revision: 3,
          snapshot: snapshot(withNote: true),
        ),
        checkpoint: checkpoint,
      ).action,
      DailySyncAction.download,
    );
  });

  test('two-sided edits never silently resurrect deleted tasks', () {
    final baseline = snapshot(withTask: true);
    final decision = decideDailySync(
      local: snapshot(),
      remote: RemoteDailySnapshot(
        revision: 3,
        snapshot: snapshot(withTask: true, withNote: true),
      ),
      checkpoint: DailySyncCheckpoint(revision: 2, snapshot: baseline),
    );
    expect(decision.action, DailySyncAction.conflict);
    expect(
      decideDailySync(
        local: snapshot(withTask: true),
        remote: RemoteDailySnapshot(
          revision: 1,
          snapshot: snapshot(withNote: true),
        ),
        checkpoint: null,
      ).action,
      DailySyncAction.conflict,
    );
  });

  test('snapshot validates dates, IDs, and shape', () {
    final valid = snapshot(withTask: true).toJson();
    expect(DailySnapshot.fromJson(valid).tasks.single.title, '읽기');
    final duplicate = {
      ...valid,
      'tasks': [valid['tasks'][0], valid['tasks'][0]],
    };
    expect(() => DailySnapshot.fromJson(duplicate), throwsFormatException);
    final invalid = {
      ...valid,
      'notes': [
        {'id': 'n', 'day': '2026-02-30', 'text': 'x'},
      ],
    };
    expect(() => DailySnapshot.fromJson(invalid), throwsFormatException);
  });

  test('checkpoint keeps its baseline when the source task is edited', () {
    final original = snapshot(withTask: true);
    final checkpoint = DailySyncCheckpoint(revision: 1, snapshot: original);
    final remote = RemoteDailySnapshot(revision: 1, snapshot: original);
    original.tasks.single.title = '바뀐 일';
    expect(checkpoint.snapshot.tasks.single.title, '읽기');
    expect(remote.snapshot.tasks.single.title, '읽기');
    expect(
      decideDailySync(
        local: original,
        remote: remote,
        checkpoint: checkpoint,
      ).action,
      DailySyncAction.upload,
    );
  });
}
