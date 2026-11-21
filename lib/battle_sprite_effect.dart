import 'package:flutter/material.dart';

import 'game_motion_sprite.dart';
import 'models/battle_engine.dart';

/// Small code-drawn cues that sit above a fighter without changing its sprite.
class BattleSpriteEffect extends StatelessWidget {
  const BattleSpriteEffect({
    super.key,
    required this.motion,
    required this.trigger,
    required this.towardBottom,
    required this.color,
    this.effect = BattleActionEffect.basic,
  });

  final GameSpriteMotion motion;
  final int trigger;
  final bool towardBottom;
  final Color color;
  final BattleActionEffect effect;

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.disableAnimationsOf(context) ||
        (motion != GameSpriteMotion.attack &&
            motion != GameSpriteMotion.hit &&
            motion != GameSpriteMotion.victory)) {
      return const SizedBox.expand();
    }
    return IgnorePointer(
      child: TweenAnimationBuilder<double>(
        key: ValueKey('battle-effect-${motion.name}-${effect.name}-$trigger'),
        tween: Tween(begin: 0, end: 1),
        duration: const Duration(milliseconds: 420),
        builder: (context, progress, _) => CustomPaint(
          painter: _BattleEffectPainter(
            motion: motion,
            progress: progress,
            towardBottom: towardBottom,
            color: color,
            effect: effect,
          ),
        ),
      ),
    );
  }
}

class _BattleEffectPainter extends CustomPainter {
  const _BattleEffectPainter({
    required this.motion,
    required this.progress,
    required this.towardBottom,
    required this.color,
    required this.effect,
  });

  final GameSpriteMotion motion;
  final double progress;
  final bool towardBottom;
  final Color color;
  final BattleActionEffect effect;

  @override
  void paint(Canvas canvas, Size size) {
    final fade = (1 - progress).clamp(0.0, 1.0);
    if (fade == 0) return;
    Offset point(double x, double y) => Offset(x * size.width, y * size.height);
    Paint ink(double alpha, double width) => Paint()
      ..isAntiAlias = false
      ..color = color.withValues(alpha: alpha * fade)
      ..strokeWidth = width
      ..strokeCap = StrokeCap.square;
    void spark(double x, double y, double radius, Paint paint) {
      final center = point(x, y);
      final distance = size.shortestSide * radius;
      canvas.drawLine(
        center.translate(-distance, 0),
        center.translate(distance, 0),
        paint,
      );
      canvas.drawLine(
        center.translate(0, -distance),
        center.translate(0, distance),
        paint,
      );
    }

    switch (motion) {
      case GameSpriteMotion.attack:
        final direction = towardBottom ? 1.0 : -1.0;
        final head = .5 + direction * (.1 + progress * .27);
        switch (effect) {
          case BattleActionEffect.heal:
            for (final (x, y) in [(.24, .36), (.76, .44), (.52, .15)]) {
              spark(x, y - progress * .12, .055, ink(.85, 2));
            }
          case BattleActionEffect.water:
            for (final lane in [-1.0, 1.0]) {
              final x = .5 + lane * .17;
              canvas.drawLine(
                point(x - .09, head - direction * .13),
                point(x, head),
                ink(.85, 2),
              );
              canvas.drawLine(
                point(x, head),
                point(x + .09, head - direction * .13),
                ink(.7, 2),
              );
            }
          case BattleActionEffect.star:
            spark(.28, head, .07, ink(.9, 2));
            spark(.72, head - direction * .1, .055, ink(.8, 2));
          case BattleActionEffect.wind:
            for (final lane in [-1.0, 0.0, 1.0]) {
              final x = .5 + lane * .16;
              canvas.drawLine(
                point(x - .11, head - direction * .18),
                point(x + .06, head),
                ink(.8, 2),
              );
            }
          case BattleActionEffect.dawn:
            spark(.5, head - direction * .1, .11, ink(.9, 3));
            for (final lane in [-1.0, 1.0]) {
              canvas.drawLine(
                point(.5 + lane * .14, head - direction * .19),
                point(.5 + lane * .22, head),
                ink(.7, 2),
              );
            }
          case BattleActionEffect.basic:
            for (final lane in [-1.0, 0.0, 1.0]) {
              final x = .5 + lane * .19;
              canvas.drawLine(
                point(x, head - direction * .18),
                point(x + lane * .04, head),
                ink(lane == 0 ? .9 : .55, lane == 0 ? 3 : 2),
              );
            }
        }
        break;
      case GameSpriteMotion.hit:
        final reach = .12 + progress * .13;
        canvas.drawLine(
          point(.5 - reach, .5 - reach),
          point(.5 + reach, .5 + reach),
          ink(.95, 3),
        );
        canvas.drawLine(
          point(.57 - reach * .55, .4 + reach * .55),
          point(.57 + reach * .55, .4 - reach * .55),
          ink(.7, 2),
        );
        break;
      case GameSpriteMotion.victory:
        for (final (x, y) in [(.2, .32), (.78, .25), (.63, .08)]) {
          final center = point(x, y - progress * .17);
          final radius = size.shortestSide * (.045 + progress * .025);
          final paint = ink(.9, 2);
          canvas.drawLine(
            center.translate(-radius, 0),
            center.translate(radius, 0),
            paint,
          );
          canvas.drawLine(
            center.translate(0, -radius),
            center.translate(0, radius),
            paint,
          );
        }
        break;
      default:
        break;
    }
  }

  @override
  bool shouldRepaint(covariant _BattleEffectPainter oldDelegate) =>
      oldDelegate.motion != motion ||
      oldDelegate.progress != progress ||
      oldDelegate.towardBottom != towardBottom ||
      oldDelegate.color != color ||
      oldDelegate.effect != effect;
}
