import 'dart:convert';

import 'package:file_selector_platform_interface/file_selector_platform_interface.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:growup/backup_page.dart';
import 'package:growup/main.dart';
import 'package:growup/models/growth_goal.dart';
import 'package:growup/state/growth_backup.dart';
import 'package:growup/state/game_store.dart';
import 'package:growup/state/growth_store.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

Future<GrowthStore> newStore() async {
  SharedPreferencesAsyncPlatform.instance =
      InMemorySharedPreferencesAsync.empty();
  final store = GrowthStore(SharedPreferencesAsync());
  await store.load();
  return store;
}

GrowthGoal sample(String id) => GrowthGoal(
  id: id,
  title: '독서',
  mini: '2쪽',
  more: '15분',
  max: '40분',
  path: '균형 있게',
  weeklyTarget: 3,
  milestones: ['첫 책'],
  createdAt: DateTime(2026, 10, 31),
  completions: {'2026-10-30': 'MINI'},
  restDays: {'2026-10-29'},
);

class TestFileSelector extends FileSelectorPlatform {
  TestFileSelector(this.file);

  final XFile file;

  @override
  Future<XFile?> openFile({
    List<XTypeGroup>? acceptedTypeGroups,
    String? initialDirectory,
    String? confirmButtonText,
  }) async => file;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'backup round trip includes dates and settings without auth tokens',
    () async {
      final store = await newStore();
      await store.addGoal(
        title: '독서',
        mini: '2쪽',
        more: '15분',
        max: '40분',
        path: '균형 있게',
        milestones: ['첫 책'],
      );
      await store.complete(store.goals.single, 'MAX');
      await store.setGuardianName('별이');
      await store.setDarkTheme(true);
      final json = store.createBackup().encode();
      final backup = GrowthBackup.decode(json);
      expect(backup.guardianName, '별이');
      expect(backup.darkTheme, isTrue);
      expect(backup.goals.single.completions[store.today], 'MAX');
      expect(json, isNot(contains('accessToken')));

      final restored = await newStore();
      final result = await restored.importBackup(backup);
      expect(result.added, 1);
      expect(result.settingsRestored, isTrue);
      expect(restored.guardianName, '별이');
      expect(restored.darkTheme, isTrue);
      expect(restored.goals.single.completions[store.today], 'MAX');
      expect(restored.goals.single.completionActions[store.today], '40분');
    },
  );

  test('game collection round trip restores only on an empty device', () async {
    final store = await newStore();
    final game = GameStore(SharedPreferencesAsync());
    await game.load();
    expect(await game.chooseStarter('star_crow'), isTrue);
    expect(await game.moveCreatureToSlot('starter-1', 2), isTrue);
    expect(await game.creditCompletedTasks(['task-a']), 2);
    expect(await game.startTraining(now: DateTime.utc(2026, 11, 1)), isTrue);
    final backup = GrowthBackup.decode(
      store.createBackup().withGame(game.exportSnapshot()).encode(),
    );
    expect(backup.game!.squad[2], 'starter-1');
    expect(backup.game!.trainingEndsAt, DateTime.utc(2026, 11, 1, 0, 0, 30));
    expect(backup.game!.trainingPasses, 1);

    await newStore();
    final restored = GameStore(SharedPreferencesAsync());
    await restored.load();
    expect(await restored.importIfEmpty(backup.game!), isTrue);
    expect(restored.owned.single.speciesId, 'star_crow');
    expect(restored.squad[2], 'starter-1');
    expect(restored.trainingPasses, 1);
    expect(
      restored.trainingRemaining(now: DateTime.utc(2026, 11, 1)),
      GameStore.trainingDuration,
    );
    final reloaded = GameStore(SharedPreferencesAsync());
    await reloaded.load();
    expect(reloaded.squad[2], 'starter-1');
    expect(reloaded.trainingEndsAt, DateTime.utc(2026, 11, 1, 0, 0, 30));
    expect(await reloaded.importIfEmpty(backup.game!), isFalse);
    expect(reloaded.owned, hasLength(1));
  });

  test('invalid game data rejects the whole backup', () async {
    await newStore();
    final game = GameStore(SharedPreferencesAsync());
    await game.chooseStarter('pine_fox');
    final encoded = GrowthBackup(
      goals: const [],
      guardianName: '루온',
      darkTheme: false,
      game: game.exportSnapshot(),
    ).encode();
    final invalid = jsonDecode(encoded) as Map<String, dynamic>;
    (invalid['game'] as Map)['squad'] = ['missing', null, null, null, null];
    expect(
      () => GrowthBackup.decode(jsonEncode(invalid)),
      throwsFormatException,
    );
  });

  test(
    'old game backups gain zero tickets and invalid ticket ledgers fail',
    () async {
      await newStore();
      final game = GameStore(SharedPreferencesAsync());
      await game.chooseStarter('pine_fox');
      final backup = GrowthBackup(
        goals: const [],
        guardianName: '루온',
        darkTheme: false,
        game: game.exportSnapshot(),
      );
      final old = jsonDecode(backup.encode()) as Map<String, dynamic>;
      final oldGame = old['game'] as Map<String, dynamic>;
      oldGame.remove('trainingPasses');
      oldGame.remove('creditedTaskIds');
      oldGame.remove('adventureClears');
      expect(GrowthBackup.decode(jsonEncode(old)).game!.trainingPasses, 0);
      expect(GrowthBackup.decode(jsonEncode(old)).game!.adventureClears, 0);
      oldGame['trainingPasses'] = -1;
      expect(() => GrowthBackup.decode(jsonEncode(old)), throwsFormatException);
      oldGame['trainingPasses'] = 2;
      oldGame['creditedTaskIds'] = ['task-a', 'task-a'];
      expect(() => GrowthBackup.decode(jsonEncode(old)), throwsFormatException);
      oldGame['creditedTaskIds'] = ['task-a'];
      oldGame['adventureClears'] = 1;
      expect(() => GrowthBackup.decode(jsonEncode(old)), throwsFormatException);
    },
  );

  test('old records without action text stay readable', () {
    final legacy = sample('legacy').toJson()..remove('completionActions');
    final restored = GrowthGoal.fromJson(legacy);
    expect(restored.completions['2026-10-30'], 'MINI');
    expect(restored.completionActions, isEmpty);
  });

  test('undo removes the saved action text', () async {
    final store = await newStore();
    await store.addGoal(
      title: '독서',
      mini: '2쪽',
      more: '15분',
      max: '40분',
      path: '균형 있게',
      milestones: [],
    );
    final goal = store.goals.single;
    await store.complete(goal, 'MINI');
    await store.undo(goal);
    expect(goal.completions, isEmpty);
    expect(goal.completionActions, isEmpty);
  });

  test('invalid backup is rejected before existing data changes', () async {
    final store = await newStore();
    await store.addGoal(
      title: '기존 목표',
      mini: '2쪽',
      more: '15분',
      max: '40분',
      path: '균형 있게',
      milestones: [],
    );
    final original = store.goals.single.toJson();
    final invalid =
        jsonDecode(store.createBackup().encode()) as Map<String, dynamic>;
    (invalid['goals'] as List).first['completions'] = {'2026-02-30': 'MAX'};
    expect(
      () => GrowthBackup.decode(jsonEncode(invalid)),
      throwsFormatException,
    );
    expect(store.goals.single.toJson(), original);
  });

  test('invalid goal settings and overlapping day records are rejected', () {
    final goal = sample('goal-1').toJson();
    final backup = {
      'format': 'growup-backup',
      'version': 1,
      'guardianName': '루온',
      'darkTheme': false,
      'goals': [goal],
    };
    for (final invalid in [
      {'weeklyTarget': 9},
      {'weeklyTarget': 2.5},
      {'weeklyMinutes': -1},
      {'targetDate': '2026-02-30'},
      {'startDate': '2026-99-01'},
      {'startDate': '2026-12-31', 'targetDate': '2026-12-01'},
      {
        'completionActions': {'2026-10-29': '2쪽'},
      },
      {
        'completionActions': {'2026-10-30': '가' * 161},
      },
      {
        'restDays': ['2026-10-30'],
      },
    ]) {
      final changed = {...goal, ...invalid};
      expect(
        () => GrowthBackup.decode(
          jsonEncode({
            ...backup,
            'goals': [changed],
          }),
        ),
        throwsFormatException,
      );
    }
  });

  test('same ID with different records becomes an archived copy', () async {
    final store = await newStore();
    final local = sample('same-id');
    await store.importBackup(
      GrowthBackup(goals: [local], guardianName: '루온', darkTheme: false),
    );
    final imported = sample('same-id')..completions['2026-10-31'] = 'MAX';
    final result = await store.importBackup(
      GrowthBackup(goals: [imported], guardianName: '다른 이름', darkTheme: true),
    );
    expect(result.archivedCopies, 1);
    expect(result.settingsRestored, isFalse);
    expect(store.goals.single.completions.containsKey('2026-10-31'), isFalse);
    expect(store.archivedGoals.single.completions['2026-10-31'], 'MAX');
    expect(store.archivedGoals.single.localBackup, isTrue);
    expect(store.guardianName, '루온');
  });

  test('extra active goals stay archived until a slot opens', () async {
    final store = await newStore();
    final backup = GrowthBackup(
      goals: List.generate(6, (index) => sample('goal-$index')),
      guardianName: '루온',
      darkTheme: false,
    );
    final result = await store.importBackup(backup);
    expect(store.goals.length, 5);
    expect(store.archivedGoals.length, 1);
    expect(result.archivedCopies, 1);
  });

  test('sync backup with a long title remains importable', () async {
    final store = await newStore();
    final original = sample('long-title')..title = '가' * 160;
    await store.importBackup(
      GrowthBackup(goals: [original], guardianName: '루온', darkTheme: false),
    );
    await store.addSyncBackup(original.toJson());
    final decoded = GrowthBackup.decode(store.createBackup().encode());
    expect(decoded.goals.length, 2);
    expect(store.archivedGoals.single.title, endsWith('(동기화 보관본)'));
  });

  testWidgets('records page opens backup controls on a phone width', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(411, 915);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final store = await newStore();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: GrowthPage(store: store)),
      ),
    );
    await tester.scrollUntilVisible(find.text('기록 백업·가져오기'), 300);
    await tester.tap(find.text('기록 백업·가져오기'));
    await tester.pumpAndSettle();
    expect(find.text('기록을 파일로 옮기기'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('selected backup file is confirmed and imported', (tester) async {
    await newStore();
    final sourceGame = GameStore(SharedPreferencesAsync());
    await sourceGame.chooseStarter('wave_otter');
    final backup = GrowthBackup(
      goals: [sample('from-file')],
      guardianName: '루온',
      darkTheme: false,
      game: sourceGame.exportSnapshot(),
    );
    final previousSelector = FileSelectorPlatform.instance;
    FileSelectorPlatform.instance = TestFileSelector(
      XFile.fromData(
        Uint8List.fromList(utf8.encode(backup.encode())),
        name: 'backup.json',
        mimeType: 'application/json',
      ),
    );
    addTearDown(() => FileSelectorPlatform.instance = previousSelector);
    final store = await newStore();
    final game = GameStore(SharedPreferencesAsync());
    await game.load();
    await tester.pumpWidget(
      MaterialApp(
        home: BackupPage(store: store, gameStore: game),
      ),
    );
    await tester.tap(find.text('백업 파일 가져오기'));
    await tester.pumpAndSettle();
    expect(find.textContaining('백업 목표 1개를 가져옵니다'), findsOneWidget);
    expect(find.textContaining('로컬 게임 포함'), findsOneWidget);
    expect(store.goals, isEmpty);
    await tester.tap(find.text('가져오기'));
    await tester.pumpAndSettle();
    expect(store.goals.single.id, 'from-file');
    expect(game.owned.single.speciesId, 'wave_otter');
    expect(find.textContaining('목표 1개를 가져왔어요'), findsOneWidget);
  });

  testWidgets('invalid selected file leaves existing goals untouched', (
    tester,
  ) async {
    final previousSelector = FileSelectorPlatform.instance;
    FileSelectorPlatform.instance = TestFileSelector(
      XFile.fromData(
        Uint8List.fromList(utf8.encode('{"wrong":"format"}')),
        name: 'invalid.json',
        mimeType: 'application/json',
      ),
    );
    addTearDown(() => FileSelectorPlatform.instance = previousSelector);
    final store = await newStore();
    await store.addGoal(
      title: '기존 목표',
      mini: '2쪽',
      more: '15분',
      max: '40분',
      path: '균형 있게',
      milestones: [],
    );
    final original = store.goals.single.toJson();
    await tester.pumpWidget(MaterialApp(home: BackupPage(store: store)));
    await tester.tap(find.text('백업 파일 가져오기'));
    await tester.pumpAndSettle();
    expect(find.text('전설키우기 백업 형식을 확인해 주세요.'), findsOneWidget);
    expect(find.text('백업 기록 가져오기'), findsNothing);
    expect(store.goals.single.toJson(), original);
  });

  testWidgets('web export starts a backup download', (tester) async {
    if (!kIsWeb) return;
    final store = await newStore();
    await tester.pumpWidget(MaterialApp(home: BackupPage(store: store)));
    await tester.tap(find.text('백업 파일 내보내기'));
    await tester.pumpAndSettle();
    expect(find.textContaining('백업 파일 다운로드를 시작했어요'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('backup choices fit a narrow screen with large text', (
    tester,
  ) async {
    final store = await newStore();
    tester.view.physicalSize = const Size(320, 700);
    tester.view.devicePixelRatio = 1;
    tester.binding.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(
      tester.binding.platformDispatcher.clearTextScaleFactorTestValue,
    );

    await tester.pumpWidget(MaterialApp(home: BackupPage(store: store)));
    expect(find.text('백업 파일 내보내기'), findsOneWidget);
    await tester.ensureVisible(find.text('백업 파일 가져오기'));
    expect(tester.takeException(), isNull);
  });

  testWidgets('backup import confirmation fits large text', (tester) async {
    final backup = GrowthBackup(
      goals: [sample('from-file')],
      guardianName: '루온',
      darkTheme: false,
    );
    final previousSelector = FileSelectorPlatform.instance;
    FileSelectorPlatform.instance = TestFileSelector(
      XFile.fromData(
        Uint8List.fromList(utf8.encode(backup.encode())),
        name: 'backup.json',
        mimeType: 'application/json',
      ),
    );
    addTearDown(() => FileSelectorPlatform.instance = previousSelector);
    tester.view.physicalSize = const Size(320, 700);
    tester.view.devicePixelRatio = 1;
    tester.binding.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(
      tester.binding.platformDispatcher.clearTextScaleFactorTestValue,
    );
    final store = await newStore();
    await tester.pumpWidget(MaterialApp(home: BackupPage(store: store)));
    await tester.ensureVisible(find.text('백업 파일 가져오기'));
    await tester.tap(find.text('백업 파일 가져오기'));
    await tester.pumpAndSettle();
    expect(find.text('백업 기록 가져오기'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
