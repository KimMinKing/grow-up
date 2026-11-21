import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:growup/account_page.dart';
import 'package:growup/state/auth_gateway.dart';
import 'package:growup/state/game_store.dart';
import 'package:growup/state/goal_sync_planner.dart';
import 'package:growup/state/goal_sync_service.dart';
import 'package:growup/state/growth_store.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

class _FakeRemote implements GoalSyncRemote {
  final rows = <String, RemoteGoalSnapshot>{};
  int putCalls = 0;
  void Function()? afterPut;

  @override
  Future<List<RemoteGoalSnapshot>> fetchAll() async => rows.values.toList();

  @override
  Future<int?> put(
    String goalId,
    Map<String, dynamic> snapshot,
    int expectedRevision,
  ) async {
    putCalls++;
    final previous = rows[goalId];
    if ((previous?.revision ?? 0) != expectedRevision) return null;
    final next = expectedRevision + 1;
    rows[goalId] = RemoteGoalSnapshot(
      goalId: goalId,
      revision: next,
      snapshot: snapshot,
    );
    afterPut?.call();
    return next;
  }
}

class _SignedInAuth implements AuthGateway {
  @override
  String? get currentUserId => 'user-a';
  @override
  String? get currentUserEmail => 'reader@example.com';
  @override
  String? get currentDisplayName => null;
  @override
  DateTime? get currentUserCreatedAt => null;
  @override
  Stream<String?> get authChanges => const Stream.empty();
  @override
  Future<String?> accessToken() async => 'token';
  @override
  Future<void> sendEmailCode(String email) async {}
  @override
  Future<void> verifyEmailCode(String email, String code) async {}
  @override
  Future<bool> signUpWithPassword(String email, String password) async => false;
  @override
  Future<void> confirmSignUp(String email, String code) async {}
  @override
  Future<void> signInWithPassword(String email, String password) async {}
  @override
  Future<void> signInWithSocial(SocialProvider provider) async {}
  @override
  Future<Set<SocialProvider>> availableSocialProviders() async => {};
  @override
  Future<void> updateDisplayName(String name) async {}
  @override
  Future<void> deleteAccount() async {}
  @override
  Future<void> signOut() async {}
}

Future<GrowthStore> _store() async {
  SharedPreferencesAsyncPlatform.instance =
      InMemorySharedPreferencesAsync.empty();
  final store = GrowthStore(SharedPreferencesAsync());
  await store.load();
  return store;
}

Future<void> _addGoal(GrowthStore store) => store
    .addGoal(
      title: '독서',
      mini: '2쪽',
      more: '15분',
      max: '40분',
      path: '균형 있게',
      milestones: ['첫 책'],
    )
    .then((_) {});

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'account switch during upload leaves no saved sync checkpoint',
    () async {
      final store = await _store();
      await _addGoal(store);
      var user = 'user-a';
      final remote = _FakeRemote()..afterPut = () => user = 'user-b';
      final checkpoints = GoalSyncCheckpointStore(SharedPreferencesAsync());
      final service = GoalSyncService(
        store: store,
        remote: remote,
        checkpoints: checkpoints,
        userId: () => user,
      );

      await expectLater(service.sync(), throwsStateError);
      expect(remote.rows.length, 1);
      expect(await checkpoints.load('user-a'), isEmpty);
    },
  );

  test(
    'uploads, downloads, and keeps conflict loser as a local backup',
    () async {
      final remote = _FakeRemote();
      final firstStore = await _store();
      await _addGoal(firstStore);
      final firstPrefs = SharedPreferencesAsync();
      var user = 'user-a';
      final first = GoalSyncService(
        store: firstStore,
        remote: remote,
        checkpoints: GoalSyncCheckpointStore(firstPrefs),
        userId: () => user,
      );
      final initial = await first.sync();
      expect(initial.uploaded, 1);
      expect(remote.rows.length, 1);
      final id = firstStore.goals.single.id;
      final originalRevision = remote.rows[id]!.revision;

      final secondStore = await _store();
      final second = GoalSyncService(
        store: secondStore,
        remote: remote,
        checkpoints: GoalSyncCheckpointStore(SharedPreferencesAsync()),
        userId: () => 'user-a',
      );
      expect((await second.sync()).downloaded, 1);
      expect(secondStore.goals.single.title, '독서');

      await firstStore.complete(firstStore.goals.single, 'MINI');
      final secondGoal = secondStore.goals.single;
      await secondStore.updateGoalSettings(
        secondGoal,
        title: '매일 독서',
        path: secondGoal.path,
        weeklyTarget: secondGoal.weeklyTarget,
      );
      expect((await second.sync()).uploaded, 1);
      expect(remote.rows[id]!.revision, originalRevision + 1);
      final conflictResult = await first.sync();
      expect(conflictResult.conflicts.length, 1);
      expect(firstStore.goals.single.completions[firstStore.today], 'MINI');
      expect(remote.rows[id]!.snapshot['title'], '매일 독서');

      await first.resolve(conflictResult.conflicts.single, keepLocal: true);
      expect(remote.rows[id]!.snapshot['title'], '독서');
      expect(firstStore.archivedGoals.single.localBackup, isTrue);
      expect(firstStore.archivedGoals.single.title, contains('보관본'));
      expect((await first.sync()).conflicts, isEmpty);
      expect(remote.rows.length, 1);

      user = 'user-b';
      await expectLater(first.sync(), throwsStateError);
      expect(remote.rows.length, 1);
    },
  );

  test('choosing server keeps the changed local record in archives', () async {
    final remote = _FakeRemote();
    final store = await _store();
    await _addGoal(store);
    final service = GoalSyncService(
      store: store,
      remote: remote,
      checkpoints: GoalSyncCheckpointStore(SharedPreferencesAsync()),
      userId: () => 'user-a',
    );
    await service.sync();
    final goal = store.goals.single;
    await store.complete(goal, 'MAX');
    final serverData = Map<String, dynamic>.from(
      jsonDecode(jsonEncode(remote.rows[goal.id]!.snapshot)) as Map,
    )..['title'] = '서버 이름';
    remote.rows[goal.id] = RemoteGoalSnapshot(
      goalId: goal.id,
      revision: 2,
      snapshot: serverData,
    );
    final conflict = (await service.sync()).conflicts.single;
    await service.resolve(conflict, keepLocal: false);
    expect(store.goals.single.title, '서버 이름');
    expect(store.archivedGoals.single.completions[store.today], 'MAX');
    expect(store.archivedGoals.single.completionActions[store.today], '40분');
    expect(store.archivedGoals.single.localBackup, isTrue);
  });

  test(
    'invalid server goal stops sync before changing local records',
    () async {
      final remote = _FakeRemote();
      final store = await _store();
      await _addGoal(store);
      final localSnapshot = store.goals.single.toJson();
      final invalid = Map<String, dynamic>.from(localSnapshot)
        ..['id'] = 'remote-invalid'
        ..['completions'] = {'2026-02-30': 'MAX'};
      remote.rows['remote-invalid'] = RemoteGoalSnapshot(
        goalId: 'remote-invalid',
        revision: 1,
        snapshot: invalid,
      );
      final service = GoalSyncService(
        store: store,
        remote: remote,
        checkpoints: GoalSyncCheckpointStore(SharedPreferencesAsync()),
        userId: () => 'user-a',
      );
      await expectLater(service.sync(), throwsFormatException);
      expect(remote.putCalls, 0);
      expect(store.allGoals.single.toJson(), localSnapshot);
    },
  );

  test('invalid fresh server goal cannot resolve a conflict', () async {
    final remote = _FakeRemote();
    final store = await _store();
    await _addGoal(store);
    final service = GoalSyncService(
      store: store,
      remote: remote,
      checkpoints: GoalSyncCheckpointStore(SharedPreferencesAsync()),
      userId: () => 'user-a',
    );
    await service.sync();
    final goal = store.goals.single;
    await store.complete(goal, 'MINI');
    final changed = Map<String, dynamic>.from(remote.rows[goal.id]!.snapshot)
      ..['title'] = '서버 이름';
    remote.rows[goal.id] = RemoteGoalSnapshot(
      goalId: goal.id,
      revision: 2,
      snapshot: changed,
    );
    final conflict = (await service.sync()).conflicts.single;
    remote.rows[goal.id] = RemoteGoalSnapshot(
      goalId: goal.id,
      revision: 2,
      snapshot: {
        ...changed,
        'restDays': ['2026-02-30'],
      },
    );
    await expectLater(
      service.resolve(conflict, keepLocal: true),
      throwsFormatException,
    );
    expect(remote.putCalls, 1);
    expect(store.archivedGoals, isEmpty);
    expect(goal.completions[store.today], 'MINI');
  });

  testWidgets('conflict comparison shows the action saved on each side', (
    tester,
  ) async {
    final remote = _FakeRemote();
    final store = await _store();
    await _addGoal(store);
    final service = GoalSyncService(
      store: store,
      remote: remote,
      checkpoints: GoalSyncCheckpointStore(SharedPreferencesAsync()),
      userId: () => 'user-a',
    );
    await service.sync();
    final goal = store.goals.single;
    await store.complete(goal, 'MINI');
    final serverSnapshot =
        Map<String, dynamic>.from(remote.rows[goal.id]!.snapshot)
          ..['completions'] = {store.today: 'MAX'}
          ..['completionActions'] = {store.today: '40분'};
    remote.rows[goal.id] = RemoteGoalSnapshot(
      goalId: goal.id,
      revision: 2,
      snapshot: serverSnapshot,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: AccountPage(
          auth: _SignedInAuth(),
          store: store,
          gameStore: GameStore(SharedPreferencesAsync()),
          goalSyncService: service,
        ),
      ),
    );
    await tester.tap(find.text('지금 동기화'));
    await tester.pumpAndSettle();
    expect(find.textContaining('충돌 1개'), findsOneWidget);
    expect(find.textContaining('2쪽'), findsOneWidget);
    expect(find.textContaining('40분'), findsOneWidget);
  });

  testWidgets('account page syncs on a phone width without losing goals', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(411, 915);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final store = await _store();
    await _addGoal(store);
    final service = GoalSyncService(
      store: store,
      remote: _FakeRemote(),
      checkpoints: GoalSyncCheckpointStore(SharedPreferencesAsync()),
      userId: () => 'user-a',
    );
    await tester.pumpWidget(
      MaterialApp(
        home: AccountPage(
          auth: _SignedInAuth(),
          store: store,
          gameStore: GameStore(SharedPreferencesAsync()),
          goalSyncService: service,
        ),
      ),
    );
    await tester.tap(find.text('지금 동기화'));
    await tester.pumpAndSettle();
    expect(find.text('이 계정에 기록 연결'), findsOneWidget);
    await tester.tap(find.text('연결하고 동기화'));
    await tester.pumpAndSettle();
    expect(find.textContaining('올림 1개'), findsOneWidget);
    expect(store.goals.single.title, '독서');
    expect(tester.takeException(), isNull);
  });
}
