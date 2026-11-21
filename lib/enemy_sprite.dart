import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'game_motion_sprite.dart';

/// Small code-drawn pixel sprites for adventure enemies.
class EnemySprite extends StatefulWidget {
  const EnemySprite({
    super.key,
    required this.enemyId,
    this.size = 46,
    this.motion = GameSpriteMotion.idle,
    this.motionTrigger = 0,
  });

  final String enemyId;
  final double size;
  final GameSpriteMotion motion;
  final int motionTrigger;

  @override
  State<EnemySprite> createState() => _EnemySpriteState();
}

class _EnemySpriteState extends State<EnemySprite>
    with TickerProviderStateMixin {
  late final AnimationController _idleController = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2800),
  )..repeat();
  late final AnimationController _actionController = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 420),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _idleController.stop();
      _actionController.stop();
    } else if (!_idleController.isAnimating) {
      _idleController.repeat();
    }
  }

  @override
  void didUpdateWidget(covariant EnemySprite oldWidget) {
    super.didUpdateWidget(oldWidget);
    if ((oldWidget.motion != widget.motion ||
            oldWidget.motionTrigger != widget.motionTrigger) &&
        widget.motion != GameSpriteMotion.idle &&
        !MediaQuery.disableAnimationsOf(context)) {
      _actionController.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _idleController.dispose();
    _actionController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: widget.size,
    child: AnimatedBuilder(
      animation: Listenable.merge([_idleController, _actionController]),
      builder: (context, _) {
        final reduced = MediaQuery.disableAnimationsOf(context);
        final progress = reduced ? 0.0 : _actionController.value;
        final pulse = math.sin(progress * math.pi);
        final bob = reduced
            ? 0.0
            : math.sin(_idleController.value * math.pi * 2) *
                  widget.size *
                  (widget.enemyId == 'dawn_sentinel' ? .035 : .02);
        final offset = switch (widget.motion) {
          GameSpriteMotion.attack => Offset(0, bob - widget.size * .13 * pulse),
          GameSpriteMotion.hit => Offset(
            widget.size *
                .035 *
                math.sin(progress * math.pi * 6) *
                (1 - progress),
            bob,
          ),
          _ => Offset(0, bob),
        };
        return Transform.translate(
          key: const ValueKey('enemy-action-offset'),
          offset: offset,
          child: Opacity(
            opacity: widget.motion == GameSpriteMotion.defeat ? .45 : 1,
            child: CustomPaint(painter: _EnemySpritePainter(widget.enemyId)),
          ),
        );
      },
    ),
  );
}

class _EnemySpritePainter extends CustomPainter {
  const _EnemySpritePainter(this.enemyId);

  final String enemyId;

  static const _spore = [
    '................',
    '.....DDDDDD.....',
    '...DDGGGGGGDD...',
    '..DGGLLLLLLGGD..',
    '.DGGLLLLLLLLGGD.',
    '.DGLLGLLLLGLLGD.',
    'DGGLLLLLLLLLLGGD',
    'DGGLLLLLLLLLLGGD',
    '.DDGGGGGGGGGGDD.',
    '...DCCCCCCCCD...',
    '...DCCECCECCD...',
    '...DCCCCCCCCD...',
    '....DCPCCPCD....',
    '....DDCCCCDD....',
    '.....DD..DD.....',
    '................',
  ];

  static const _guardian = [
    '..GG........GG..',
    '.GDDG......GDDG.',
    '.GDDDG....GDDDG.',
    '..GDDGGGGDDGG...',
    '...DDGLLLLGDD...',
    '..DDGLLLLLLGDD..',
    '.DDGLLGGGGLLGDD.',
    '.DGLLGLLLLGLLGD.',
    'DDGLLLEEEELLLGDD',
    'DDGLLLEDDEELLGDD',
    '.DGLLLCCCCLLLGD.',
    '.DDGLLCCCCLLGDD.',
    '..DDGCCCCCCGDD..',
    '...DDGCCCCGDD...',
    '....DDG..GDD....',
    '.....DD..DD.....',
  ];

  static const _mushroom = [
    '................',
    '.....MMMMMM.....',
    '...MMVVVVVVMM...',
    '..MVVVVVVVVVVM..',
    '.MVVVYVVVVYVVVM.',
    '.MVVVVVVVVVVVVM.',
    '..MMMMMMMMMMMM..',
    '...MSSSSSSSSM...',
    '.....SSSSSS.....',
    '.....SEESSS.....',
    '.....SSSSSS.....',
    '.....SSSSSS.....',
    '....SSSSSSSS....',
    '...SSSSSSSSSS...',
    '....MMMMMMMM....',
    '................',
  ];

  static const _firefly = [
    '................',
    '.......YY.......',
    '......YYYY......',
    '....TTYYYYTT....',
    '...TTTTYYTTTT...',
    '..TTTTTYYTTTTT..',
    '...TTTYYYYTTT...',
    '....TTYYYYTT....',
    '......YYYY......',
    '.....YKKYY......',
    '.....YYYYYY.....',
    '......YYYY......',
    '.....TT..TT.....',
    '....TT....TT....',
    '...T........T...',
    '................',
  ];

  static const _windShadow = [
    '................',
    '.....BBBBBB.....',
    '...BBWWWWWWBB...',
    '..BWWWWWWWWWWB..',
    '.BWWKWWWWKWWWWB.',
    '.BWWWWWWWWWWWWB.',
    '..BWWWWGGWWWWB..',
    '...BWWWGGWWWB...',
    '....BWWWWWWB....',
    '...BBWWWWWWBB...',
    '..BWWWB..BWWWB..',
    '.BWWWB....BWWWB.',
    '..BBB......BBB..',
    '....B......B....',
    '................',
    '................',
  ];

  static const _dawnSentinel = [
    '......YY........',
    '.....YYYY.......',
    '....YGYYGY......',
    '...YGGYYGGY.....',
    '..YGGGGGGGGY....',
    '.YGGEGGGGEGGY...',
    '.YGGEGGGGEGGY...',
    '.YGGGGMMGGGGY...',
    '..YGGMMMMGGY....',
    '...YGGMMGGY.....',
    '..YYGGGGGGYY....',
    '.YGGYGGGGYGGY...',
    '.YGGY....YGGY...',
    '..YYY....YYY....',
    '...Y......Y.....',
    '................',
  ];

  static const _riverGuard = [
    '................',
    '.....TTTTTT.....',
    '...TTSSSSSSTT...',
    '..TSSWWWWWWST...',
    '.TSSWWWWWWSSST..',
    '.TSWWEWWEWWST...',
    'TSSWWWWWWWWSSST.',
    'TSSWWTTTTWWSSST.',
    '.TSSWWTTWWSSST..',
    '..TSSWWWWSSST...',
    '..TTSSSSSSTT....',
    '.TTTTSSSSTTTT...',
    '.TT..TSSST..TT..',
    '.....TSSST......',
    '.....TT.TT......',
    '................',
  ];

  static const _stoneCrab = [
    '................',
    '................',
    '.TT..........TT.',
    'TSSST......TSSST',
    '.TTSTTTTTTTSTT..',
    '...TBBBBBBT.....',
    '..TBBWWWWBBT....',
    '.TBBWWEEWWBBT...',
    '.TBBWWWWWWBBT...',
    '..TBBBBBBBBT....',
    '..TTTTTTTTTT....',
    '.TT..T..T..TT...',
    'TT...T..T...TT..',
    '.....T..T.......',
    '................',
    '................',
  ];

  static const _reedStalker = [
    '................',
    '.....G..G.......',
    '....GG..GG......',
    '...GGGTTGGG.....',
    '..GGTTTTTTGG....',
    '..GTTWWWWTTG....',
    '.GTTWEEWETTG....',
    '.GTTWWWWWWTG....',
    '..GTTTTTTTG.....',
    '...GGTTTTGG.....',
    '...GTTTTTTG.....',
    '..GTT.GG.TTG....',
    '.GGG..GG..GGG...',
    '.GG...GG...GG...',
    '......GG........',
    '................',
  ];

  static const _moonFerryman = [
    '......YY........',
    '.....YYYY.......',
    '....YTTTTY......',
    '...YTTWWTTY.....',
    '..YTTWEEWTTY....',
    '.YTTTWWWWTTTY...',
    '.YTTTBBBBTTTY...',
    '..YTTBBBBTTY....',
    '..YTTBBBBTTY....',
    '.YTTTBBBBTTTY...',
    'YTTTTBBBBTTTTY..',
    '.YYTTBBBBTTYY...',
    '..YTTBBBBTTY....',
    '...YTTTTTTY.....',
    '....YYYYYY......',
    '................',
  ];

  static const _colors = <String, Color>{
    'D': Color(0xFF253D38),
    'G': Color(0xFF427E5A),
    'L': Color(0xFF91C96E),
    'C': Color(0xFFD6C48C),
    'E': Color(0xFFFFE293),
    'P': Color(0xFFC78984),
    'M': Color(0xFF3C3154),
    'V': Color(0xFF9472B0),
    'Y': Color(0xFFFAD678),
    'S': Color(0xFFD8CBB5),
    'T': Color(0xFF58BDAF),
    'K': Color(0xFF273642),
    'B': Color(0xFF2B394F),
    'W': Color(0xFF7D93B1),
  };

  @override
  void paint(Canvas canvas, Size size) {
    final rows = switch (enemyId) {
      'moss_guard' => _guardian,
      'night_mushroom' => _mushroom,
      'firefly_wisp' => _firefly,
      'wind_shadow' => _windShadow,
      'dawn_sentinel' => _dawnSentinel,
      'river_mist_guard' => _riverGuard,
      'river_stone_crab' => _stoneCrab,
      'river_reed_stalker' => _reedStalker,
      'river_moon_ferryman' => _moonFerryman,
      _ => _spore,
    };
    final pixel = size.width / 16;
    for (var y = 0; y < rows.length; y++) {
      for (var x = 0; x < rows[y].length && x < 16; x++) {
        final color = _colors[rows[y][x]];
        if (color == null) continue;
        canvas.drawRect(
          Rect.fromLTWH(x * pixel, y * pixel, pixel + 0.15, pixel + 0.15),
          Paint()..color = color,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _EnemySpritePainter oldDelegate) =>
      oldDelegate.enemyId != enemyId;
}
