import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'models/game_creature.dart';

// Motion sheets stay decoded once; each widget owns a lightweight clone.
final Map<String, Future<ui.Image>> _spriteImageCache = {};

@visibleForTesting
void clearGameMotionImageCache() {
  final images = _spriteImageCache.values.toList();
  _spriteImageCache.clear();
  for (final image in images) {
    image.then((value) => value.dispose(), onError: (Object _) {});
  }
}

enum GameSpriteMotion { idle, attack, hit, victory, defeat }

class GameMotionSprite extends StatefulWidget {
  const GameMotionSprite({
    super.key,
    required this.speciesId,
    required this.size,
    this.motion = GameSpriteMotion.idle,
    this.motionTrigger = 0,
    this.evolutionStage = CreatureEvolutionStage.seed,
  });

  final String speciesId;
  final double size;
  final GameSpriteMotion motion;
  final int motionTrigger;
  final CreatureEvolutionStage evolutionStage;

  @override
  State<GameMotionSprite> createState() => _GameMotionSpriteState();
}

class GameAmbientBackdrop extends StatefulWidget {
  const GameAmbientBackdrop({
    super.key,
    required this.speciesId,
    required this.size,
    this.evolutionStage = CreatureEvolutionStage.seed,
  });

  final String speciesId;
  final double size;
  final CreatureEvolutionStage evolutionStage;

  @override
  State<GameAmbientBackdrop> createState() => _GameAmbientBackdropState();
}

class GameForestFireflies extends StatefulWidget {
  const GameForestFireflies({super.key});

  @override
  State<GameForestFireflies> createState() => _GameForestFirefliesState();
}

class GameForestDrift extends StatefulWidget {
  const GameForestDrift({
    super.key,
    this.assetPath = 'assets/game/pine-forest-bg.png',
  });

  final String assetPath;

  @override
  State<GameForestDrift> createState() => _GameForestDriftState();
}

class _GameForestDriftState extends State<GameForestDrift>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 18),
  )..repeat();

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _controller.stop();
    } else if (!_controller.isAnimating) {
      _controller.repeat();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: RepaintBoundary(
      child: AnimatedBuilder(
        animation: _controller,
        child: Image.asset(
          widget.assetPath,
          fit: BoxFit.cover,
          filterQuality: FilterQuality.none,
          excludeFromSemantics: true,
        ),
        builder: (context, child) {
          final phase = MediaQuery.disableAnimationsOf(context)
              ? 0.0
              : _controller.value;
          return Transform.translate(
            key: const ValueKey('forest-drift'),
            offset: Offset(math.sin(phase * math.pi * 2) * 6, 0),
            child: Transform.scale(scale: 1.12, child: child),
          );
        },
      ),
    ),
  );
}

class _GameForestFirefliesState extends State<GameForestFireflies>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 8),
  )..repeat();

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _controller.stop();
    } else if (!_controller.isAnimating) {
      _controller.repeat();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: RepaintBoundary(
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) => CustomPaint(
          painter: _ForestFirefliesPainter(
            phase: MediaQuery.disableAnimationsOf(context)
                ? 0
                : _controller.value,
          ),
        ),
      ),
    ),
  );
}

class _ForestFirefliesPainter extends CustomPainter {
  const _ForestFirefliesPainter({required this.phase});

  final double phase;

  @override
  void paint(Canvas canvas, Size size) {
    for (var i = 0; i < 12; i++) {
      final cycle = phase * math.pi * 2 + i * 2.17;
      final x =
          size.width * (.08 + ((i * 37) % 83) / 100) +
          math.sin(cycle) * size.width * .012;
      final y =
          size.height * (.28 + ((i * 29) % 58) / 100) +
          math.cos(cycle * .8) * size.height * .035;
      final brightness = .35 + .25 * (1 + math.sin(cycle * 1.3)) / 2;
      final color = i.isEven
          ? const Color(0xFFA4F2B5)
          : const Color(0xFFB9E8DD);
      final point = Offset(x, y);
      canvas.drawCircle(
        point,
        i % 4 == 0 ? 5 : 3.5,
        Paint()..color = color.withValues(alpha: brightness * .16),
      );
      canvas.drawCircle(
        point,
        i % 4 == 0 ? 1.4 : .9,
        Paint()..color = color.withValues(alpha: brightness),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _ForestFirefliesPainter oldDelegate) =>
      oldDelegate.phase != phase;
}

class _GameAmbientBackdropState extends State<GameAmbientBackdrop>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 7),
  )..repeat();

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _controller.stop();
    } else if (!_controller.isAnimating) {
      _controller.repeat();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: widget.size,
    child: AnimatedBuilder(
      animation: _controller,
      builder: (context, _) => CustomPaint(
        painter: _AmbientPainter(
          phase: MediaQuery.disableAnimationsOf(context)
              ? 0
              : _controller.value,
          color: switch (widget.speciesId) {
            'pine_fox' => const Color(0xFF91DBA3),
            'wave_otter' => const Color(0xFF8ADAF4),
            _ => const Color(0xFFD3BAFF),
          },
          evolutionStage: widget.evolutionStage,
        ),
      ),
    ),
  );
}

class _AmbientPainter extends CustomPainter {
  const _AmbientPainter({
    required this.phase,
    required this.color,
    required this.evolutionStage,
  });

  final double phase;
  final Color color;
  final CreatureEvolutionStage evolutionStage;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final halo = Paint()
      ..shader = RadialGradient(
        colors: [
          color.withValues(
            alpha: switch (evolutionStage) {
              CreatureEvolutionStage.seed => .24,
              CreatureEvolutionStage.awakened => .32,
              CreatureEvolutionStage.transcended => .40,
            },
          ),
          color.withValues(alpha: .02),
        ],
      ).createShader(Rect.fromCircle(center: center, radius: size.width * .52));
    canvas.drawCircle(center, size.width * .52, halo);
    if (evolutionStage != CreatureEvolutionStage.seed) {
      canvas.drawCircle(
        center,
        size.width * .43,
        Paint()
          ..color = color.withValues(alpha: .28)
          ..style = PaintingStyle.stroke
          ..strokeWidth = evolutionStage == CreatureEvolutionStage.transcended
              ? 2
              : 1.2,
      );
    }
    if (evolutionStage == CreatureEvolutionStage.transcended) {
      canvas.drawCircle(
        center,
        size.width * .49,
        Paint()
          ..color = const Color(0xFFFFD991).withValues(alpha: .28)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1,
      );
    }
    final points = switch (evolutionStage) {
      CreatureEvolutionStage.seed => 9,
      CreatureEvolutionStage.awakened => 12,
      CreatureEvolutionStage.transcended => 16,
    };
    for (var i = 0; i < points; i++) {
      final angle = i * math.pi * 2 / points + phase * math.pi * .18;
      final radius = size.width * (.30 + (i % 3) * .055);
      final drift =
          math.sin(phase * math.pi * 2 + i * 1.7) * size.height * .025;
      final point = Offset(
        center.dx + math.cos(angle) * radius,
        center.dy + math.sin(angle) * radius + drift,
      );
      final opacity = .30 + .35 * (1 + math.sin(phase * math.pi * 2 + i)) / 2;
      canvas.drawCircle(
        point,
        i % 3 == 0 ? 2 : 1.2,
        Paint()..color = color.withValues(alpha: opacity),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _AmbientPainter oldDelegate) =>
      oldDelegate.phase != phase ||
      oldDelegate.color != color ||
      oldDelegate.evolutionStage != evolutionStage;
}

class _GameMotionSpriteState extends State<GameMotionSprite>
    with TickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 3600),
  )..repeat();
  late final AnimationController _actionController = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 420),
  );
  ui.Image? _image;
  int _loadGeneration = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _controller.stop();
      _actionController.stop();
    } else if (!_controller.isAnimating) {
      _controller.repeat();
    }
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant GameMotionSprite oldWidget) {
    super.didUpdateWidget(oldWidget);
    if ((oldWidget.motion != widget.motion ||
            oldWidget.motionTrigger != widget.motionTrigger) &&
        widget.motion != GameSpriteMotion.idle &&
        !MediaQuery.disableAnimationsOf(context)) {
      _actionController.forward(from: 0);
    }
    if (oldWidget.speciesId != widget.speciesId ||
        (widget.speciesId == 'pebble_newt' &&
            oldWidget.evolutionStage != widget.evolutionStage)) {
      _loadGeneration++;
      _image?.dispose();
      _image = null;
      _load();
    }
  }

  Future<void> _load() async {
    final speciesId = widget.speciesId;
    final asset = _motionAsset;
    final generation = _loadGeneration;
    ui.Image? image;
    try {
      final shared = await _spriteImageCache.putIfAbsent(asset, () async {
        try {
          final bytes = await rootBundle.load(asset);
          final codec = await ui.instantiateImageCodec(
            bytes.buffer.asUint8List(),
          );
          try {
            return (await codec.getNextFrame()).image;
          } finally {
            codec.dispose();
          }
        } catch (_) {
          _spriteImageCache.remove(asset);
          rethrow;
        }
      });
      image = shared.clone();
    } catch (_) {
      return;
    }
    if (!mounted ||
        widget.speciesId != speciesId ||
        _motionAsset != asset ||
        generation != _loadGeneration) {
      image.dispose();
      return;
    }
    setState(() => _image = image);
  }

  String get _motionAsset {
    if (widget.speciesId == 'pebble_newt') {
      final stage = switch (widget.evolutionStage) {
        CreatureEvolutionStage.seed => 'seed',
        CreatureEvolutionStage.awakened => 'awakened',
        CreatureEvolutionStage.transcended => 'transcended',
      };
      return 'assets/game/pebble-newt-$stage-motion.png';
    }
    return 'assets/game/${_assetName(widget.speciesId)}-motion.png';
  }

  String _assetName(String id) => switch (id) {
    'pine_fox' => 'pine-fox',
    'wave_otter' => 'wave-otter',
    _ => 'star-crow',
  };

  @override
  void dispose() {
    _controller.dispose();
    _actionController.dispose();
    _image?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: widget.size,
      child: AnimatedBuilder(
        animation: Listenable.merge([_controller, _actionController]),
        builder: (context, _) {
          final reduced = MediaQuery.disableAnimationsOf(context);
          final progress = reduced ? 0.0 : _actionController.value;
          final pulse = math.sin(progress * math.pi);
          final motion = widget.motion;
          final offset = switch (motion) {
            GameSpriteMotion.attack => Offset(0, widget.size * .13 * pulse),
            GameSpriteMotion.hit => Offset(
              widget.size *
                  .035 *
                  math.sin(progress * math.pi * 6) *
                  (1 - progress),
              0,
            ),
            GameSpriteMotion.victory => Offset(0, -widget.size * .08 * pulse),
            _ => Offset.zero,
          };
          return Transform.translate(
            key: const ValueKey('sprite-action-offset'),
            offset: offset,
            child: Opacity(
              opacity: motion == GameSpriteMotion.defeat ? .5 : 1,
              child: CustomPaint(
                painter: _SpritePainter(
                  image: _image,
                  phase: reduced ? 0 : _controller.value,
                  newtStage: widget.speciesId == 'pebble_newt'
                      ? widget.evolutionStage
                      : null,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _SpritePainter extends CustomPainter {
  const _SpritePainter({
    required this.image,
    required this.phase,
    required this.newtStage,
  });

  final ui.Image? image;
  final double phase;
  final CreatureEvolutionStage? newtStage;

  @override
  void paint(Canvas canvas, Size size) {
    final sprite = image;
    if (sprite == null) return;
    final frame = phase < 0.52
        ? 0
        : phase < 0.67
        ? 1
        : phase < 0.82
        ? 0
        : phase < 0.91
        ? 2
        : 3;
    final frameLeft = (frame * sprite.width / 4).round();
    final frameRight = ((frame + 1) * sprite.width / 4).round();
    final frameWidth = (frameRight - frameLeft).toDouble();
    final source = switch (newtStage) {
      CreatureEvolutionStage.seed => Rect.fromLTWH(
        frameLeft + 90,
        230,
        360,
        260,
      ),
      CreatureEvolutionStage.awakened => Rect.fromLTWH(
        frameLeft + 120,
        260,
        300,
        200,
      ),
      CreatureEvolutionStage.transcended => Rect.fromLTWH(
        frameLeft + 20,
        220,
        500,
        310,
      ),
      null => Rect.fromLTWH(
        frameLeft.toDouble(),
        0,
        frameWidth,
        sprite.height.toDouble(),
      ),
    };
    final hop = frame == 2 ? size.height * 0.07 : 0.0;
    final breathe = 1 + 0.018 * (phase < 0.82 ? phase / 0.82 : 0);
    final frameRatio = source.width / source.height;
    final height = newtStage != null
        ? math.min(size.height - hop, size.width / frameRatio) * breathe
        : (size.height - hop) * breathe;
    final width = height * frameRatio;
    final target = Rect.fromLTWH(
      (size.width - width) / 2,
      size.height - height - hop,
      width,
      height,
    );
    canvas.drawImageRect(
      sprite,
      source,
      target,
      Paint()..filterQuality = FilterQuality.none,
    );
  }

  @override
  bool shouldRepaint(covariant _SpritePainter oldDelegate) =>
      oldDelegate.image != image ||
      oldDelegate.phase != phase ||
      oldDelegate.newtStage != newtStage;
}
