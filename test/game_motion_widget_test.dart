import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:growup/battle_sprite_effect.dart';
import 'package:growup/enemy_sprite.dart';
import 'package:growup/game_motion_sprite.dart';
import 'package:growup/models/game_creature.dart';

void main() {
  setUp(clearGameMotionImageCache);

  testWidgets('battle effect stops with reduced motion', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(disableAnimations: true),
          child: Scaffold(
            body: SizedBox.square(
              dimension: 56,
              child: BattleSpriteEffect(
                motion: GameSpriteMotion.hit,
                trigger: 1,
                towardBottom: true,
                color: Colors.amber,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.binding.transientCallbackCount, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('enemy reacts to attack and respects reduced motion', (
    tester,
  ) async {
    Widget scene(
      GameSpriteMotion motion,
      int trigger, {
      bool reduced = false,
    }) => MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(disableAnimations: reduced),
        child: Scaffold(
          body: EnemySprite(
            enemyId: 'dawn_sentinel',
            motion: motion,
            motionTrigger: trigger,
          ),
        ),
      ),
    );

    double y() => tester
        .widget<Transform>(find.byKey(const ValueKey('enemy-action-offset')))
        .transform
        .storage[13];

    await tester.pumpWidget(scene(GameSpriteMotion.idle, 0));
    await tester.pumpWidget(scene(GameSpriteMotion.attack, 1));
    await tester.pump(const Duration(milliseconds: 150));
    expect(y(), lessThan(-2));
    await tester.pumpWidget(scene(GameSpriteMotion.hit, 2, reduced: true));
    await tester.pumpAndSettle();
    expect(y(), closeTo(0, .001));
    expect(tester.binding.transientCallbackCount, 0);
  });

  testWidgets('battle action moves a sprite and reduced motion stops it', (
    tester,
  ) async {
    Widget scene(
      GameSpriteMotion motion,
      int trigger, {
      bool reduced = false,
    }) => MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(disableAnimations: reduced),
        child: Scaffold(
          body: GameMotionSprite(
            speciesId: 'pine_fox',
            size: 80,
            motion: motion,
            motionTrigger: trigger,
          ),
        ),
      ),
    );

    double y() => tester
        .widget<Transform>(find.byKey(const ValueKey('sprite-action-offset')))
        .transform
        .storage[13];

    await tester.pumpWidget(scene(GameSpriteMotion.idle, 0));
    await tester.pumpWidget(scene(GameSpriteMotion.attack, 1));
    await tester.pump(const Duration(milliseconds: 150));
    expect(y(), greaterThan(3));
    await tester.pump(const Duration(milliseconds: 500));
    expect(y(), closeTo(0, .001));

    await tester.pumpWidget(scene(GameSpriteMotion.hit, 2, reduced: true));
    await tester.pumpAndSettle();
    expect(y(), closeTo(0, .001));
    expect(tester.binding.transientCallbackCount, 0);
  });

  testWidgets('pebble newt reacts to a hit and respects reduced motion', (
    tester,
  ) async {
    Widget scene(
      GameSpriteMotion motion,
      int trigger, {
      bool reduced = false,
    }) => MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(disableAnimations: reduced),
        child: Scaffold(
          body: GameMotionSprite(
            speciesId: 'pebble_newt',
            size: 80,
            motion: motion,
            motionTrigger: trigger,
          ),
        ),
      ),
    );

    double x() => tester
        .widget<Transform>(find.byKey(const ValueKey('sprite-action-offset')))
        .transform
        .storage[12];

    await tester.pumpWidget(scene(GameSpriteMotion.idle, 0));
    await tester.pumpWidget(scene(GameSpriteMotion.hit, 1));
    await tester.pump(const Duration(milliseconds: 150));
    expect(x().abs(), greaterThan(.4));

    await tester.pumpWidget(scene(GameSpriteMotion.hit, 2, reduced: true));
    await tester.pumpAndSettle();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 300)),
    );
    await tester.pump();
    expect(x(), closeTo(0, .001));
    expect(tester.binding.transientCallbackCount, 0);
  });

  testWidgets('pebble newt switches motion sheets across stages', (
    tester,
  ) async {
    final previewKey = GlobalKey();
    Widget scene(CreatureEvolutionStage stage) => MaterialApp(
      home: MediaQuery(
        data: const MediaQueryData(disableAnimations: true),
        child: Scaffold(
          body: RepaintBoundary(
            key: previewKey,
            child: ColoredBox(
              color: const Color(0xFF303544),
              child: SizedBox.square(
                dimension: 120,
                child: GameMotionSprite(
                  speciesId: 'pebble_newt',
                  evolutionStage: stage,
                  size: 120,
                ),
              ),
            ),
          ),
        ),
      ),
    );

    Future<int> renderedFingerprint() async {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 300)),
      );
      await tester.pump();
      final boundary =
          previewKey.currentContext!.findRenderObject()!
              as RenderRepaintBoundary;
      final image = await boundary.toImage();
      try {
        final pixels = (await tester.runAsync(() async {
          final data = await image.toByteData(
            format: ui.ImageByteFormat.rawRgba,
          );
          return data!.buffer.asUint8List();
        }))!;
        var changedPixels = 0;
        var hash = 2166136261;
        for (var i = 0; i < pixels.length; i += 4) {
          final color = pixels[i] << 16 | pixels[i + 1] << 8 | pixels[i + 2];
          if (color != 0x303544) changedPixels++;
          hash = ((hash ^ color) * 16777619) & 0xFFFFFFFF;
        }
        expect(changedPixels, greaterThan(1000));
        return hash;
      } finally {
        image.dispose();
      }
    }

    await tester.pumpWidget(scene(CreatureEvolutionStage.seed));
    await tester.pumpAndSettle();
    final seedImage = await renderedFingerprint();
    expect(
      find.descendant(
        of: find.byType(GameMotionSprite),
        matching: find.byType(CustomPaint),
      ),
      findsOneWidget,
    );

    await tester.pumpWidget(scene(CreatureEvolutionStage.awakened));
    await tester.pumpAndSettle();
    final awakenedImage = await renderedFingerprint();

    await tester.pumpWidget(scene(CreatureEvolutionStage.transcended));
    await tester.pumpAndSettle();
    final transcendedImage = await renderedFingerprint();
    expect({seedImage, awakenedImage, transcendedImage}, hasLength(3));
    expect(tester.takeException(), isNull);
  });

  testWidgets('game art settles when reduced motion is enabled', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(disableAnimations: true),
          child: Scaffold(
            body: Column(
              children: [
                GameAmbientBackdrop(speciesId: 'pine_fox', size: 100),
                GameMotionSprite(speciesId: 'pine_fox', size: 100),
                SizedBox(width: 200, height: 100, child: GameForestFireflies()),
                SizedBox(width: 200, height: 100, child: GameForestDrift()),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(tester.binding.transientCallbackCount, 0);
  });

  testWidgets('two sprites can share a sheet while one changes species', (
    tester,
  ) async {
    Widget scene(String firstSpecies) => MaterialApp(
      home: MediaQuery(
        data: const MediaQueryData(disableAnimations: true),
        child: Scaffold(
          body: Row(
            children: [
              GameMotionSprite(
                key: const ValueKey('first'),
                speciesId: firstSpecies,
                size: 80,
              ),
              const GameMotionSprite(
                key: ValueKey('second'),
                speciesId: 'pine_fox',
                size: 80,
              ),
            ],
          ),
        ),
      ),
    );

    await tester.pumpWidget(scene('pine_fox'));
    await tester.pumpAndSettle();
    await tester.pumpWidget(scene('star_crow'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('forest background drifts and stops for reduced motion', (
    tester,
  ) async {
    Widget scene(bool reducedMotion) => MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(disableAnimations: reducedMotion),
        child: const Scaffold(
          body: SizedBox(width: 300, height: 116, child: GameForestDrift()),
        ),
      ),
    );

    double drift() => tester
        .widget<Transform>(find.byKey(const ValueKey('forest-drift')))
        .transform
        .storage[12];

    await tester.pumpWidget(scene(false));
    final initial = drift();
    await tester.pump(const Duration(seconds: 2));
    expect((drift() - initial).abs(), greaterThan(1));

    await tester.pumpWidget(scene(true));
    await tester.pumpAndSettle();
    expect(drift(), closeTo(0, 0.001));
    expect(tester.binding.transientCallbackCount, 0);
  });
}
