import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:growup/battle_page.dart';
import 'package:growup/battle_sprite_effect.dart';
import 'package:growup/enemy_sprite.dart';
import 'package:growup/game_motion_sprite.dart';
import 'package:growup/models/adventure_stage.dart';
import 'package:growup/models/battle_engine.dart';
import 'package:growup/models/game_creature.dart';
import 'package:growup/models/reward_grant.dart';
import 'package:growup/state/game_store.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

void main() {
  test('river guard shield absorbs eight damage before health falls', () {
    final result = BattleEngine.simulate(
      riverStages.first,
      const ['fox', null, null, null, null],
      const [CreatureInstance(id: 'fox', speciesId: 'pine_fox', level: 6)],
    );
    final firstHit = result.frames.firstWhere(
      (frame) => frame.message.contains('물안개 보호막'),
    );
    expect(firstHit.message, contains('8 흡수'));
    expect(firstHit.enemies.single.hp, 72 - (27 + 3 - 8));
    expect(result.won, isTrue);
  });

  test('river crossing attacks the rear and ferry boss renews its shield', () {
    const owned = [
      CreatureInstance(id: 'fox', speciesId: 'pine_fox', level: 5),
      CreatureInstance(id: 'crow', speciesId: 'star_crow', level: 5),
    ];
    const squad = ['fox', null, null, null, 'crow'];
    final crossing = BattleEngine.simulate(riverStages[1], squad, owned);
    expect(
      crossing.frames.any((frame) => frame.message.contains('갈대 기습 → 별까마귀')),
      isTrue,
    );
    final ferry = BattleEngine.simulate(riverStages.last, squad, owned);
    expect(
      ferry.frames.any((frame) => frame.message.contains('달빛 장막 8을 둘렀어요')),
      isTrue,
    );
    expect(
      ferry.frames.any((frame) => frame.message.contains('달빛 장막 14 흡수')),
      isTrue,
    );
    expect(ferry.won, isTrue);
  });

  test('pebble newt protects itself on every third attack', () {
    final result = BattleEngine.simulate(
      riverStages.last,
      const ['newt', null, null, null, null],
      const [CreatureInstance(id: 'newt', speciesId: 'pebble_newt', level: 5)],
    );
    expect(
      result.frames.any(
        (frame) => frame.message.contains('자갈 갑옷 · 다음 피해 6 흡수'),
      ),
      isTrue,
    );
    expect(
      result.frames.any(
        (frame) =>
            frame.message.contains('자갈 갑옷') && frame.message.contains('흡수'),
      ),
      isTrue,
    );
  });

  test(
    'combat growth reaches awakening and transcendence at level milestones',
    () {
      const seed = CreatureInstance(
        id: 'fox',
        speciesId: 'pine_fox',
        level: 2,
        battleExperience: 2,
      );
      final awakened = seed.earnBattleExperience(1);
      expect(seed.evolutionStage, CreatureEvolutionStage.seed);
      expect(seed.experienceToNextEvolution, 1);
      expect(awakened.level, 3);
      expect(awakened.evolutionStage, CreatureEvolutionStage.awakened);
      expect(awakened.experienceToNextEvolution, 6);
      expect(BattleEngine.allyStatsFor(awakened), (
        hp: 74,
        attack: 20,
        speed: 10,
      ));
      expect(
        BattleEngine.estimatedPower(['fox'], [awakened]),
        74 + 20 * 3 + 10,
      );
      final transcended = awakened.earnBattleExperience(6);
      expect(transcended.level, 5);
      expect(transcended.evolutionStage, CreatureEvolutionStage.transcended);
      expect(transcended.nextEvolutionStage, isNull);
      expect(BattleEngine.allyStatsFor(transcended), (
        hp: 90,
        attack: 25,
        speed: 10,
      ));
    },
  );

  test('battle log records visual effects for named actions', () {
    final owned = [
      const CreatureInstance(id: 'fox', speciesId: 'pine_fox', level: 2),
      const CreatureInstance(id: 'otter', speciesId: 'wave_otter', level: 2),
      const CreatureInstance(id: 'crow', speciesId: 'star_crow', level: 2),
    ];
    final frames = <BattleFrame>[
      for (final creature in owned)
        ...BattleEngine.simulate(
          firstForestStages.first,
          [creature.id, null, null, null, null],
          [creature],
        ).frames,
      for (final creature in owned)
        ...BattleEngine.simulate(
          firstForestStages.last,
          [creature.id, null, null, null, null],
          [creature],
        ).frames,
      ...BattleEngine.simulate(firstForestStages.last, [
        'fox',
        'otter',
        'crow',
        null,
        null,
      ], owned).frames,
    ];
    final expected = {
      '숲의 숨결': BattleActionEffect.heal,
      '물결 베기': BattleActionEffect.water,
      '별빛 표식': BattleActionEffect.star,
      '돌풍 베기': BattleActionEffect.wind,
      '새벽의 일격': BattleActionEffect.dawn,
    };
    for (final entry in expected.entries) {
      final matching = frames.where(
        (frame) => frame.message.contains(entry.key),
      );
      expect(matching, isNotEmpty, reason: entry.key);
      expect(matching.every((frame) => frame.effect == entry.value), isTrue);
    }
  });

  test('battle log identifies the acting squad slot for duplicate species', () {
    final result = BattleEngine.simulate(
      firstForestStages.first,
      ['fox-a', 'fox-b', null, null, null],
      [
        const CreatureInstance(id: 'fox-a', speciesId: 'pine_fox', level: 1),
        const CreatureInstance(id: 'fox-b', speciesId: 'pine_fox', level: 1),
      ],
    );
    final actingSlots = result.frames
        .where((frame) => frame.actorIsAlly == true)
        .map((frame) => frame.actorSlot)
        .toSet();
    expect(actingSlots, containsAll([0, 1]));
  });

  testWidgets('only the acting duplicate companion attacks', (tester) async {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    const front = BattleFighterState('솔여우', 50, 50, 0, 'pine_fox', false);
    const hurtFront = BattleFighterState('솔여우', 42, 50, 0, 'pine_fox', false);
    const rear = BattleFighterState('솔여우', 50, 50, 1, 'pine_fox', false);
    const enemy = BattleFighterState('이끼 포자', 22, 22, 0, 'moss_spore', false);
    const result = BattleResult(
      [
        BattleFrame(
          wave: 1,
          round: 0,
          message: '전투 시작',
          allies: [front, rear],
          enemies: [enemy],
        ),
        BattleFrame(
          wave: 1,
          round: 1,
          message: '솔여우의 기본 공격 → 이끼 포자 8 피해',
          allies: [front, rear],
          enemies: [enemy],
          actorSlot: 1,
          actorIsAlly: true,
        ),
        BattleFrame(
          wave: 1,
          round: 1,
          message: '이끼 포자의 기본 공격 → 솔여우 8 피해',
          allies: [hurtFront, rear],
          enemies: [enemy],
          actorSlot: 0,
          actorIsAlly: false,
        ),
      ],
      false,
      1,
      0,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: BattlePlaybackPage(
          store: GameStore(SharedPreferencesAsync()),
          stage: firstForestStages.first,
          result: result,
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 1100));
    final sprites = tester
        .widgetList<GameMotionSprite>(find.byType(GameMotionSprite))
        .toList();
    expect(sprites.map((sprite) => sprite.motion), [
      GameSpriteMotion.idle,
      GameSpriteMotion.attack,
    ]);
    await tester.pump(const Duration(milliseconds: 1100));
    expect(
      tester.widget<EnemySprite>(find.byType(EnemySprite)).motion,
      GameSpriteMotion.attack,
    );
  });

  testWidgets('battle frames select attack hit and victory motion', (
    tester,
  ) async {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    const ally = BattleFighterState('솔여우', 50, 50, 0, 'pine_fox', false);
    const hurtAlly = BattleFighterState('솔여우', 42, 50, 0, 'pine_fox', false);
    const enemy = BattleFighterState('이끼 포자', 22, 22, 0, 'moss_spore', false);
    const hurtEnemy = BattleFighterState(
      '이끼 포자',
      14,
      22,
      0,
      'moss_spore',
      false,
    );
    const result = BattleResult(
      [
        BattleFrame(
          wave: 1,
          round: 0,
          message: '전투 시작',
          allies: [ally],
          enemies: [enemy],
        ),
        BattleFrame(
          wave: 1,
          round: 1,
          message: '솔여우의 기본 공격 → 이끼 포자 8 피해',
          allies: [ally],
          enemies: [hurtEnemy],
        ),
        BattleFrame(
          wave: 1,
          round: 1,
          message: '이끼 포자의 기본 공격 → 솔여우 8 피해',
          allies: [hurtAlly],
          enemies: [hurtEnemy],
        ),
        BattleFrame(
          wave: 1,
          round: 2,
          message: '승리 · 별 2개',
          allies: [hurtAlly],
          enemies: [],
        ),
      ],
      true,
      2,
      2,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: BattlePlaybackPage(
          store: GameStore(SharedPreferencesAsync()),
          stage: firstForestStages.first,
          result: result,
        ),
      ),
    );
    GameSpriteMotion motion() =>
        tester.widget<GameMotionSprite>(find.byType(GameMotionSprite)).motion;
    expect(motion(), GameSpriteMotion.idle);
    await tester.pump(const Duration(milliseconds: 1100));
    expect(motion(), GameSpriteMotion.attack);
    expect(
      tester
          .widgetList<BattleSpriteEffect>(find.byType(BattleSpriteEffect))
          .where((effect) => effect.motion == GameSpriteMotion.attack)
          .length,
      1,
    );
    await tester.pump(const Duration(milliseconds: 1100));
    expect(motion(), GameSpriteMotion.hit);
    await tester.pump(const Duration(milliseconds: 1100));
    expect(motion(), GameSpriteMotion.victory);
    await tester.ensureVisible(find.text('승리 · 별 2/3 · 2턴'));
    expect(find.byIcon(Icons.star_rounded), findsNWidgets(2));
    expect(find.byIcon(Icons.star_outline_rounded), findsOneWidget);
    expect(
      tester
          .widgetList<BattleSpriteEffect>(find.byType(BattleSpriteEffect))
          .where((effect) => effect.motion == GameSpriteMotion.victory)
          .length,
      1,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('healing particles appear on the healed companion', (
    tester,
  ) async {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    const fox = BattleFighterState('솔여우', 50, 58, 0, 'pine_fox', false);
    const otter = BattleFighterState('파도수달', 36, 52, 1, 'wave_otter', false);
    const healed = BattleFighterState('파도수달', 44, 52, 1, 'wave_otter', false);
    const enemy = BattleFighterState('이끼 포자', 22, 22, 0, 'moss_spore', false);
    const result = BattleResult(
      [
        BattleFrame(
          wave: 1,
          round: 0,
          message: '전투 시작',
          allies: [fox, otter],
          enemies: [enemy],
        ),
        BattleFrame(
          wave: 1,
          round: 1,
          message: '솔여우의 숲의 숨결 · 파도수달 체력 +8',
          allies: [fox, healed],
          enemies: [enemy],
          actorSlot: 0,
          actorIsAlly: true,
          effect: BattleActionEffect.heal,
        ),
      ],
      false,
      1,
      0,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: BattlePlaybackPage(
          store: GameStore(SharedPreferencesAsync()),
          stage: firstForestStages.first,
          result: result,
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 1100));
    final healingEffects = tester
        .widgetList<BattleSpriteEffect>(find.byType(BattleSpriteEffect))
        .where(
          (effect) =>
              effect.effect == BattleActionEffect.heal &&
              effect.motion == GameSpriteMotion.attack,
        );
    expect(healingEffects.length, 2);
    expect(tester.takeException(), isNull);
  });

  testWidgets('battle effects can be reduced during playback', (tester) async {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    const ally = BattleFighterState('솔여우', 50, 58, 0, 'pine_fox', false);
    const enemy = BattleFighterState('이끼 포자', 22, 22, 0, 'moss_spore', false);
    const result = BattleResult(
      [
        BattleFrame(
          wave: 1,
          round: 0,
          message: '전투 시작',
          allies: [ally],
          enemies: [enemy],
        ),
      ],
      false,
      0,
      0,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: BattlePlaybackPage(
          store: GameStore(SharedPreferencesAsync()),
          stage: firstForestStages.first,
          result: result,
        ),
      ),
    );
    expect(
      MediaQuery.disableAnimationsOf(tester.element(find.byType(EnemySprite))),
      isFalse,
    );
    await tester.tap(find.text('효과 줄이기'));
    await tester.pump();
    expect(find.text('일반 효과'), findsOneWidget);
    expect(
      MediaQuery.disableAnimationsOf(tester.element(find.byType(EnemySprite))),
      isTrue,
    );
    await tester.tap(find.text('일반 효과'));
    await tester.pump();
    expect(find.text('효과 줄이기'), findsOneWidget);
    expect(
      MediaQuery.disableAnimationsOf(tester.element(find.byType(EnemySprite))),
      isFalse,
    );
  });

  test(
    'battle effect preference survives restart and clears with device data',
    () async {
      SharedPreferencesAsyncPlatform.instance =
          InMemorySharedPreferencesAsync.empty();
      final first = GameStore(SharedPreferencesAsync());
      await first.setReduceBattleEffects(true);
      await first.setBattleHaptics(true);
      final second = GameStore(SharedPreferencesAsync());
      await second.load();
      expect(second.reduceBattleEffects, isTrue);
      expect(second.battleHaptics, isTrue);
      await second.clearLocalData();
      final third = GameStore(SharedPreferencesAsync());
      await third.load();
      expect(third.reduceBattleEffects, isFalse);
      expect(third.battleHaptics, isFalse);
    },
  );

  testWidgets('battle vibration runs only after opting in', (tester) async {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    final calls = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'HapticFeedback.vibrate') {
          calls.add(call.arguments as String);
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    const ally = BattleFighterState('솔여우', 50, 58, 0, 'pine_fox', false);
    const enemy = BattleFighterState('이끼 포자', 22, 22, 0, 'moss_spore', false);
    const result = BattleResult(
      [
        BattleFrame(
          wave: 1,
          round: 0,
          message: '시작',
          allies: [ally],
          enemies: [enemy],
        ),
        BattleFrame(
          wave: 1,
          round: 1,
          message: '공격',
          allies: [ally],
          enemies: [enemy],
          actorSlot: 0,
          actorIsAlly: true,
        ),
        BattleFrame(
          wave: 1,
          round: 2,
          message: '공격',
          allies: [ally],
          enemies: [enemy],
          actorSlot: 0,
          actorIsAlly: true,
        ),
        BattleFrame(
          wave: 1,
          round: 2,
          message: '승리',
          allies: [ally],
          enemies: [],
        ),
      ],
      true,
      2,
      2,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: BattlePlaybackPage(
          store: GameStore(SharedPreferencesAsync()),
          stage: firstForestStages.first,
          result: result,
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 1100));
    expect(calls, isEmpty);
    await tester.tap(find.text('진동 켜기'));
    await tester.pump();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump(const Duration(milliseconds: 1100));
    expect(calls, isEmpty);
    expect(find.textContaining('1턴'), findsOneWidget);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump(const Duration(milliseconds: 1100));
    await tester.pump(const Duration(milliseconds: 1100));
    expect(calls, [
      'HapticFeedbackType.selectionClick',
      'HapticFeedbackType.mediumImpact',
    ]);
    calls.clear();
    final reducedStore = GameStore(SharedPreferencesAsync());
    await reducedStore.setBattleHaptics(true);
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: BattlePlaybackPage(
            key: const ValueKey('reduced-battle'),
            store: reducedStore,
            stage: firstForestStages.first,
            result: result,
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 1100));
    expect(calls, isEmpty);
  });

  test('each starter can clear the first two-wave stage alone', () {
    for (final species in starterSpecies) {
      final creature = CreatureInstance(
        id: 'starter-1',
        speciesId: species.id,
        level: 1,
      );
      final result = BattleEngine.simulate(
        firstForestStages.first,
        ['starter-1', null, null, null, null],
        [creature],
      );
      expect(result.won, isTrue, reason: species.id);
      expect(result.frames.map((frame) => frame.wave).toSet(), {1, 2});
      expect(result.frames.last.message, startsWith('승리'));
      expect(result.stars, inInclusiveRange(1, 3));
    }
  });

  test('each first-win companion pair can clear the second stage', () {
    const companionByStarter = {
      'pine_fox': 'wave_otter',
      'wave_otter': 'star_crow',
      'star_crow': 'pine_fox',
    };
    for (final entry in companionByStarter.entries) {
      final owned = [
        CreatureInstance(id: 'starter', speciesId: entry.key, level: 1),
        CreatureInstance(id: 'gift', speciesId: entry.value, level: 1),
      ];
      final solo = BattleEngine.simulate(firstForestStages[1], [
        'starter',
        null,
        null,
        null,
        null,
      ], owned);
      final together = BattleEngine.simulate(firstForestStages[1], [
        'starter',
        'gift',
        null,
        null,
        null,
      ], owned);
      expect(solo.won, isFalse, reason: entry.key);
      expect(together.won, isTrue, reason: entry.key);
    }
  });

  test('formation changes damage received and empty squad cannot enter', () {
    const creature = CreatureInstance(
      id: 'starter-1',
      speciesId: 'wave_otter',
      level: 1,
    );
    final front = BattleEngine.simulate(
      firstForestStages.first,
      ['starter-1', null, null, null, null],
      [creature],
    );
    final rear = BattleEngine.simulate(
      firstForestStages.first,
      [null, null, 'starter-1', null, null],
      [creature],
    );
    expect(
      front.frames.last.allies.single.hp,
      greaterThan(rear.frames.last.allies.single.hp),
    );
    expect(
      front.frames.map((frame) => frame.message),
      isNot(equals(rear.frames.map((frame) => frame.message))),
    );
    expect(
      BattleEngine.simulate(firstForestStages.first, List.filled(5, null), [
        creature,
      ]).won,
      isFalse,
    );
  });

  test('front creature choice can change victory against the dawn boss', () {
    const owned = [
      CreatureInstance(id: 'otter', speciesId: 'wave_otter', level: 2),
      CreatureInstance(id: 'crow', speciesId: 'star_crow', level: 2),
    ];
    final otterFirst = BattleEngine.simulate(firstForestStages[2], [
      'otter',
      'crow',
      null,
      null,
      null,
    ], owned);
    final crowFirst = BattleEngine.simulate(firstForestStages[2], [
      'crow',
      'otter',
      null,
      null,
      null,
    ], owned);
    expect(otterFirst.won, isTrue);
    expect(crowFirst.won, isFalse);
    expect(crowFirst.frames.last.message, contains('패배'));
  });

  test('every first-win pair has a level-four dawn boss victory path', () {
    const pairs = [
      ('pine_fox', 'wave_otter', false),
      ('wave_otter', 'star_crow', true),
      ('star_crow', 'pine_fox', true),
    ];
    for (final (starter, gift, starterFirst) in pairs) {
      final owned = [
        CreatureInstance(id: 'starter', speciesId: starter, level: 4),
        CreatureInstance(id: 'gift', speciesId: gift, level: 4),
      ];
      final result = BattleEngine.simulate(firstForestStages[2], [
        if (starterFirst) 'starter' else 'gift',
        if (starterFirst) 'gift' else 'starter',
        null,
        null,
        null,
      ], owned);
      expect(result.won, isTrue, reason: '$starter + $gift');
    }
  });

  test('skills and bounded action logs appear in battle', () {
    const creature = CreatureInstance(
      id: 'starter-1',
      speciesId: 'pine_fox',
      level: 1,
    );
    final result = BattleEngine.simulate(
      firstForestStages.first,
      ['starter-1', null, null, null, null],
      [creature],
    );
    expect(
      result.frames.any((frame) => frame.message.contains('숲의 숨결')),
      isTrue,
    );
    expect(result.turns, lessThanOrEqualTo(30));
    expect(result.frames, hasLength(lessThan(150)));
  });

  test('element triangle and first boss are defined', () {
    expect(BattleEngine.elementBonus('star_crow', 'moss_guard'), 3);
    expect(BattleEngine.elementBonus('wave_otter', 'moss_guard'), -2);
    expect(BattleEngine.elementBonus('pine_fox', 'night_mushroom'), 3);
    expect(firstForestStages.first.waves.last.enemies.single.boss, isTrue);
  });

  testWidgets('single starter can enter and replay battle at 320dp 200% text', (
    tester,
  ) async {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    tester.view.physicalSize = const Size(320, 700);
    tester.view.devicePixelRatio = 1;
    tester.binding.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(
      tester.binding.platformDispatcher.clearTextScaleFactorTestValue,
    );
    final game = GameStore(SharedPreferencesAsync());
    await game.chooseStarter('pine_fox');
    await game.creditCompletedTasks(['task-a', 'task-b']);
    await game.startTraining(now: DateTime.utc(2026, 11, 3));
    await game.finishTraining(now: DateTime.utc(2026, 11, 3, 0, 1));
    await tester.pumpWidget(
      MaterialApp(
        home: BattlePreparationPage(
          store: game,
          stage: firstForestStages.first,
        ),
      ),
    );
    expect(find.text('전투 시작').hitTestable(), findsOneWidget);
    expect(find.textContaining('우리 전투력'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('전열 1'), 200);
    expect(find.text('전열 1'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.scrollUntilVisible(find.text('전투 시작'), 250);
    await tester.ensureVisible(find.text('전투 시작'));
    await tester.pump();
    await tester.tap(find.text('전투 시작'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.byType(BattlePlaybackPage), findsOneWidget);
    expect(game.adventureClears, 1);
    await tester.drag(
      find.descendant(
        of: find.byType(BattlePlaybackPage),
        matching: find.byType(ListView),
      ),
      const Offset(0, -180),
    );
    await tester.pump();
    await tester.tap(find.text('결과까지 보기'));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.textContaining('승리 · 별'), findsWidgets);
    final retry = find.widgetWithText(OutlinedButton, '편성을 바꿔 다시 도전');
    await tester.scrollUntilVisible(retry, 200);
    await tester.ensureVisible(retry);
    await tester.pump();
    await tester.tap(retry);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byType(BattlePreparationPage), findsOneWidget);
    expect(game.trainingPasses, 2);
    expect(tester.takeException(), isNull);
  });

  testWidgets('second stage defeat shows how to bring the earned companion', (
    tester,
  ) async {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    tester.view.physicalSize = const Size(320, 700);
    tester.view.devicePixelRatio = 1;
    tester.binding.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(
      tester.binding.platformDispatcher.clearTextScaleFactorTestValue,
    );
    final game = GameStore(SharedPreferencesAsync());
    await game.chooseStarter('pine_fox');
    await game.creditCompletedTasks(['task-a', 'task-b', 'task-c']);
    for (var index = 0; index < 3; index++) {
      final departed = DateTime.utc(2026, 11, 3, index * 2);
      await game.startTraining(now: departed);
      await game.finishTraining(now: departed.add(const Duration(minutes: 1)));
    }
    expect((await game.runFirstBattle())?.won, isTrue);
    await tester.pumpWidget(
      MaterialApp(
        home: BattlePreparationPage(store: game, stage: firstForestStages[1]),
      ),
    );
    expect(find.textContaining('첫 승리 동료를 빈칸에 편성'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('전투 시작'), 250);
    await tester.tap(find.text('전투 시작'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.byType(BattlePlaybackPage), findsOneWidget);
    final skip = find.descendant(
      of: find.byType(BattlePlaybackPage),
      matching: find.text('결과까지 보기'),
    );
    final playbackScroll = find.descendant(
      of: find.byType(BattlePlaybackPage),
      matching: find.byType(Scrollable),
    );
    await tester.scrollUntilVisible(
      skip,
      250,
      scrollable: playbackScroll.first,
    );
    await tester.tap(skip.last);
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.textContaining('패배 · 동료가 모두 쓰러졌어요'), findsWidgets);
    await tester.scrollUntilVisible(
      find.textContaining('첫 장소에서 합류한 신수를'),
      250,
      scrollable: playbackScroll.first,
    );
    expect(find.textContaining('첫 장소에서 합류한 신수를'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('second stage victory opens the ready boss preparation', (
    tester,
  ) async {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    final game = GameStore(SharedPreferencesAsync());
    await game.chooseStarter('star_crow');
    await game.creditCompletedTasks(List.generate(5, (index) => 'task-$index'));
    for (var index = 0; index < 7; index++) {
      final departed = DateTime.utc(2026, 11, 3, index * 2);
      await game.startTraining(now: departed);
      await game.finishTraining(now: departed.add(const Duration(minutes: 1)));
    }
    expect((await game.runFirstBattle())?.won, isTrue);
    await game.moveCreatureToSlot(GameStore.firstForestCompanionId, 1);
    final result = await game.runForestBattle(firstForestStages[1].id);
    expect(result?.won, isTrue);
    await tester.pumpWidget(
      MaterialApp(
        home: BattlePlaybackPage(
          store: game,
          stage: firstForestStages[1],
          result: result!,
        ),
      ),
    );
    final scroll = find.descendant(
      of: find.byType(BattlePlaybackPage),
      matching: find.byType(Scrollable),
    );
    final skip = find.text('결과까지 보기');
    await tester.scrollUntilVisible(skip, 250, scrollable: scroll.first);
    await tester.ensureVisible(skip.last);
    await tester.pump();
    await tester.tap(skip.last);
    await tester.pump(const Duration(milliseconds: 500));
    final prepare = find.text('보스 전투 준비');
    await tester.scrollUntilVisible(prepare, 250, scrollable: scroll.first);
    expect(find.textContaining('보스전이 열렸어요'), findsOneWidget);
    await tester.ensureVisible(prepare);
    await tester.tap(prepare);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byType(BattlePreparationPage), findsOneWidget);
    expect(find.text('숲의 새벽'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('dawn boss victory fits a narrow screen with large text', (
    tester,
  ) async {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    tester.view.physicalSize = const Size(320, 700);
    tester.view.devicePixelRatio = 1;
    tester.binding.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(
      tester.binding.platformDispatcher.clearTextScaleFactorTestValue,
    );
    final game = GameStore(SharedPreferencesAsync());
    await game.chooseStarter('star_crow');
    await game.creditCompletedTasks(List.generate(5, (index) => 'task-$index'));
    final today = DateTime.now();
    final day =
        '${today.year.toString().padLeft(4, '0')}-'
        '${today.month.toString().padLeft(2, '0')}-'
        '${today.day.toString().padLeft(2, '0')}';
    await game.creditRewards([
      for (var index = 0; index < 4; index++)
        (
          sourceId: 'mini-$index',
          kind: 'mini',
          trainingPasses: RewardRules.expectedForKind('mini').passes,
          experience: RewardRules.expectedForKind('mini').xp,
          activityDay: day,
        ),
    ]);
    for (var index = 0; index < 7; index++) {
      final departed = DateTime.utc(2026, 11, 3, index * 2);
      await game.startTraining(now: departed);
      await game.finishTraining(now: departed.add(const Duration(minutes: 1)));
    }
    expect((await game.runFirstBattle())?.won, isTrue);
    await game.moveCreatureToSlot(GameStore.firstForestCompanionId, 1);
    for (var index = 0; index < 5; index++) {
      expect(
        (await game.runForestBattle(firstForestStages[1].id))?.won,
        isTrue,
      );
    }
    await tester.pumpWidget(
      MaterialApp(
        home: BattlePreparationPage(store: game, stage: firstForestStages[2]),
      ),
    );
    expect(find.text('숲의 새벽'), findsOneWidget);
    expect(find.textContaining('동료를 키우고 전열 순서를'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.scrollUntilVisible(find.text('전투 시작'), 250);
    await tester.ensureVisible(find.text('전투 시작'));
    await tester.pump();
    await tester.tap(find.text('전투 시작'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.byType(BattlePlaybackPage), findsOneWidget);
    final skip = find.descendant(
      of: find.byType(BattlePlaybackPage),
      matching: find.text('결과까지 보기'),
    );
    final scroll = find.descendant(
      of: find.byType(BattlePlaybackPage),
      matching: find.byType(Scrollable),
    );
    await tester.scrollUntilVisible(skip, 250, scrollable: scroll.first);
    await tester.ensureVisible(skip.last);
    await tester.pump();
    await tester.tap(skip.last);
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.textContaining('승리 · 별'), findsWidgets);
    expect(find.text('첫 숲길 완주'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('전투 기록 칭호 · 숲의 새벽'),
      250,
      scrollable: scroll.first,
    );
    expect(find.text('전투 기록 칭호 · 숲의 새벽'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.textContaining('첫 숲길의 세 전투를 마쳤어요'),
      250,
      scrollable: scroll.first,
    );
    expect(find.textContaining('안개 강가의 강가 입구가 열렸어요'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('dawn boss defeat points to a concrete growth route', (
    tester,
  ) async {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    tester.view.physicalSize = const Size(320, 700);
    tester.view.devicePixelRatio = 1;
    tester.binding.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(
      tester.binding.platformDispatcher.clearTextScaleFactorTestValue,
    );
    final game = GameStore(SharedPreferencesAsync());
    await game.chooseStarter('pine_fox');
    await game.creditCompletedTasks(['task-a']);
    final departed = DateTime.utc(2026, 11, 3);
    await game.startTraining(now: departed);
    await game.finishTraining(now: departed.add(const Duration(minutes: 1)));
    expect((await game.runFirstBattle())?.won, isTrue);
    await game.moveCreatureToSlot(GameStore.firstForestCompanionId, 1);
    final result = BattleEngine.simulate(
      firstForestStages[2],
      game.squad,
      game.owned,
    );
    expect(result.won, isFalse);
    await tester.pumpWidget(
      MaterialApp(
        home: BattlePlaybackPage(
          store: game,
          stage: firstForestStages[2],
          result: result,
        ),
      ),
    );
    final scroll = find.descendant(
      of: find.byType(BattlePlaybackPage),
      matching: find.byType(Scrollable),
    );
    await tester.scrollUntilVisible(
      find.text('결과까지 보기'),
      250,
      scrollable: scroll.first,
    );
    await tester.tap(find.text('결과까지 보기'));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.scrollUntilVisible(
      find.text('오솔길 전투로 성장'),
      250,
      scrollable: scroll.first,
    );
    await tester.ensureVisible(find.text('오솔길 전투로 성장'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.textContaining('약 5번 더 이겨야'), findsOneWidget);
    expect(find.textContaining('훈련권이 없다면'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('오솔길 전투로 성장'));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byType(BattlePreparationPage), findsOneWidget);
    expect(find.text(firstForestStages[1].title), findsOneWidget);
  });

  testWidgets('battle highlights damage and healing at large text size', (
    tester,
  ) async {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    tester.view.physicalSize = const Size(320, 700);
    tester.view.devicePixelRatio = 1;
    tester.binding.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(
      tester.binding.platformDispatcher.clearTextScaleFactorTestValue,
    );
    const enemy = BattleFighterState('이끼 포자', 22, 22, 0, 'moss_spore', false);
    const hurtEnemy = BattleFighterState(
      '이끼 포자',
      14,
      22,
      0,
      'moss_spore',
      false,
    );
    const ally = BattleFighterState('솔여우', 50, 58, 0, 'pine_fox', false);
    const healedAlly = BattleFighterState('솔여우', 54, 58, 0, 'pine_fox', false);
    const result = BattleResult(
      [
        BattleFrame(
          wave: 1,
          round: 0,
          message: '전투 시작',
          allies: [ally],
          enemies: [enemy],
        ),
        BattleFrame(
          wave: 1,
          round: 1,
          message: '이끼 포자에게 8 피해',
          allies: [ally],
          enemies: [hurtEnemy],
        ),
        BattleFrame(
          wave: 1,
          round: 1,
          message: '솔여우 체력 +4',
          allies: [healedAlly],
          enemies: [hurtEnemy],
        ),
      ],
      false,
      1,
      0,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: BattlePlaybackPage(
          store: GameStore(SharedPreferencesAsync()),
          stage: firstForestStages.first,
          result: result,
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 1100));
    expect(find.text('-8'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 1100));
    expect(find.text('+4'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
