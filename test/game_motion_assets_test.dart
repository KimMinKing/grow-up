import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final species in [
    'pine-fox',
    'star-crow',
    'wave-otter',
    'pebble-newt-seed',
    'pebble-newt-awakened',
    'pebble-newt-transcended',
  ]) {
    test('$species motion frames have transparent seams', () async {
      final bytes = await File('assets/game/$species-motion.png').readAsBytes();
      final codec = await ui.instantiateImageCodec(bytes);
      final image = (await codec.getNextFrame()).image;
      codec.dispose();
      try {
        expect(image.width, inInclusiveRange(2171, 2172));
        expect(image.height, 724);
        final pixels = await image.toByteData(
          format: ui.ImageByteFormat.rawRgba,
        );
        expect(pixels, isNotNull);
        final data = pixels!.buffer.asUint8List();
        final frameWidth = image.width / 4;
        for (var seam = 1; seam < 4; seam++) {
          final center = (seam * frameWidth).round();
          var maxAlpha = 0;
          for (var x = center - 12; x <= center + 12; x++) {
            for (var y = 0; y < image.height; y++) {
              final alpha = data[(y * image.width + x) * 4 + 3];
              if (alpha > maxAlpha) maxAlpha = alpha;
            }
          }
          expect(
            maxAlpha,
            lessThanOrEqualTo(10),
            reason: '$species frame $seam bleeds into its neighbor',
          );
        }
      } finally {
        image.dispose();
      }
    });
  }

  for (final stage in ['seed', 'awakened', 'transcended']) {
    test(
      'pebble newt $stage visible poses keep one size and baseline',
      () async {
        final bytes = await File('assets/game/pebble-newt-$stage-motion.png')
            .readAsBytes();
        final codec = await ui.instantiateImageCodec(bytes);
        final image = (await codec.getNextFrame()).image;
        codec.dispose();
        try {
          expect(image.width, 2172);
          expect(image.height, 724);
          final pixels = (await image.toByteData(
            format: ui.ImageByteFormat.rawRgba,
          ))!.buffer.asUint8List();
          final boxes = <({int left, int top, int right, int bottom})>[];
          for (var frame = 0; frame < 4; frame++) {
            var left = image.width;
            var top = image.height;
            var right = 0;
            var bottom = 0;
            for (var y = 0; y < image.height; y++) {
              for (var x = frame * 543; x < (frame + 1) * 543; x++) {
                if (pixels[(y * image.width + x) * 4 + 3] < 16) continue;
                if (x < left) left = x;
                if (x > right) right = x;
                if (y < top) top = y;
                if (y > bottom) bottom = y;
              }
            }
            boxes.add((
              left: left - frame * 543,
              top: top,
              right: right - frame * 543,
              bottom: bottom,
            ));
          }
          for (final frame in [0, 1, 3]) {
            expect(
              (boxes[frame].bottom - boxes[0].bottom).abs(),
              lessThanOrEqualTo(2),
            );
            expect(
              (boxes[frame].right -
                      boxes[frame].left -
                      (boxes[0].right - boxes[0].left))
                  .abs(),
              lessThanOrEqualTo(4),
            );
          }
          expect(boxes[2].bottom, lessThan(boxes[0].bottom - 10));
          final crop = switch (stage) {
            'seed' => (left: 90, top: 230, right: 450, bottom: 490),
            'awakened' => (left: 120, top: 260, right: 420, bottom: 460),
            _ => (left: 20, top: 220, right: 520, bottom: 530),
          };
          for (final box in boxes) {
            expect(box.left, greaterThanOrEqualTo(crop.left));
            expect(box.right, lessThan(crop.right));
            expect(box.top, greaterThanOrEqualTo(crop.top));
            expect(box.bottom, lessThan(crop.bottom));
          }
        } finally {
          image.dispose();
        }
      },
    );
  }
}
