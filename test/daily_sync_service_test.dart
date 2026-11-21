import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:growup/daily_sync_page.dart';
import 'package:growup/models/daily_content.dart';
import 'package:growup/models/daily_snapshot.dart';
import 'package:growup/state/daily_sync_planner.dart';
import 'package:growup/state/daily_sync_service.dart';
import 'package:growup/state/goal_sync_service.dart';
import 'package:growup/state/growth_store.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

class _Remote implements DailySyncRemote {
  RemoteDailySnapshot? row;
  bool rejectNextPut = false;

  @override
  Future<RemoteDailySnapshot?> fetch() async => row;

  @override
  Future<int?> put(DailySnapshot snapshot, int expectedRevision) async {
    if (rejectNextPut) {
      rejectNextPut = false;
      return null;
    }
    if ((row?.revision ?? 0) != expectedRevision) return null;
    final revision = expectedRevision + 1;
    row = RemoteDailySnapshot(revision: revision, snapshot: snapshot);
    return revision;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
  });

  Future<(GrowthStore, DailySyncService)> setup(_Remote remote) async {
    final prefs = SharedPreferencesAsync();
    final store = GrowthStore(prefs);
    await store.load();
    return (
      store,
      DailySyncService(
        store: store,
        remote: remote,
        checkpoints: DailySyncCheckpointStore(prefs),
        ownerBinding: GoalSyncCheckpointStore(prefs),
        userId: () => 'user-a',
      ),
    );
  }

  test(
    'first upload, server conflict and archive restore preserve tasks',
    () async {
      final remote = _Remote();
      final (store, service) = await setup(remote);
      expect(await store.addTask('책 읽기'), isTrue);
      expect((await service.sync()).action, DailySyncAction.upload);
      expect(remote.row!.revision, 1);

      expect(await store.addNote('2026-11-07', '기기 메모'), isTrue);
      remote.row = RemoteDailySnapshot(
        revision: 2,
        snapshot: DailySnapshot(
          tasks: remote.row!.snapshot.tasks,
          notes: [
            DailyNote(id: 'server-note', day: '2026-11-07', text: '서버 메모'),
          ],
        ),
      );
      final result = await service.sync();
      expect(result.action, DailySyncAction.conflict);
      expect(store.notes.single.text, '기기 메모');
      await service.resolve(result.conflict!, keepLocal: false);
      expect(store.notes.single.text, '서버 메모');
      final archives = await service.checkpoints.archives('user-a');
      expect(archives.first.snapshot.notes.single.text, '기기 메모');
      await service.restoreArchive(archives.first);
      expect(store.notes.single.text, '기기 메모');
      expect((await service.sync()).action, DailySyncAction.conflict);
      expect((await service.checkpoints.archives('user-a')).length, 2);
    },
  );

  test('revision race does not overwrite the server', () async {
    final remote = _Remote();
    final (store, service) = await setup(remote);
    await store.addTask('첫 일');
    expect((await service.sync()).action, DailySyncAction.upload);
    await store.addTask('둘째 일');
    remote.rejectNextPut = true;
    final result = await service.sync();
    expect(result.action, DailySyncAction.conflict);
    expect(remote.row!.revision, 1);
    expect(store.tasks.length, 2);
  });

  test(
    'unknown server history stays a conflict even on an empty device',
    () async {
      final remote = _Remote()
        ..row = RemoteDailySnapshot(
          revision: 1,
          snapshot: DailySnapshot(
            tasks: [
              ChecklistItem(
                id: 'remote',
                title: '서버 일',
                createdDay: '2026-11-07',
              ),
            ],
            notes: [],
          ),
        );
      final (store, service) = await setup(remote);
      final result = await service.sync();
      expect(result.action, DailySyncAction.conflict);
      expect(store.tasks, isEmpty);
      await service.resolve(result.conflict!, keepLocal: false);
      expect(store.tasks.single.title, '서버 일');
    },
  );

  testWidgets('daily conflict fits a narrow large-text screen', (tester) async {
    tester.view.physicalSize = const Size(320, 700);
    tester.view.devicePixelRatio = 1;
    tester.binding.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(
      tester.binding.platformDispatcher.clearTextScaleFactorTestValue,
    );
    final remote = _Remote()
      ..row = RemoteDailySnapshot(
        revision: 1,
        snapshot: DailySnapshot(
          tasks: [
            ChecklistItem(
              id: 'remote',
              title: '서버 일',
              createdDay: '2026-11-07',
            ),
          ],
          notes: [],
        ),
      );
    final (store, service) = await setup(remote);
    await tester.pumpWidget(
      MaterialApp(
        home: DailySyncPage(
          service: service,
          accountEmail: 'reader@example.com',
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('지금 동기화'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('서버 기록 선택'));
    await tester.tap(find.text('서버 기록 선택'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('서버 선택'));
    await tester.pumpAndSettle();
    expect(store.tasks.single.title, '서버 일');
    expect(tester.takeException(), isNull);
  });
}
