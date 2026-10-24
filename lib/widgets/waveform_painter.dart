import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/widgets.dart';

/// A song's loudness over time as rounded bars (one every [pitch] px, each
/// the loudest of the levels it covers), [played] up to [progress].
class WaveformPainter extends CustomPainter {
  const WaveformPainter({
    required this.levels,
    required this.progress,
    required this.played,
    required this.rest,
    this.pitch = 4,
  });

  final Uint8List levels;

  /// 0…1.
  final double progress;
  final Color played;
  final Color rest;
  final double pitch;

  /// [levels] pooled into [bars] values of 0…1 (loudest of each group).
  static List<double> pool(Uint8List levels, int bars) {
    if (levels.isEmpty || bars <= 0) return const [];
    return [
      for (var b = 0; b < bars; b++)
        () {
          final from = b * levels.length ~/ bars;
          final to = math.max(from + 1, (b + 1) * levels.length ~/ bars);
          var top = 0;
          for (var i = from; i < to && i < levels.length; i++) {
            top = math.max(top, levels[i]);
          }
          return top / 255;
        }(),
    ];
  }

  @override
  void paint(Canvas canvas, Size size) {
    final bars = pool(levels, (size.width / pitch).floor());
    if (bars.isEmpty) return;
    final step = size.width / bars.length;
    final width = math.max(1.5, step * 0.6);
    final paint = Paint();
    for (final (i, v) in bars.indexed) {
      final h = math.max(width, v * size.height);
      final x = i * step + (step - width) / 2;
      paint.color = (i + 0.5) / bars.length <= progress ? played : rest;
      canvas.drawRRect(
        RRect.fromRectAndRadius(Rect.fromLTWH(x, (size.height - h) / 2, width, h), Radius.circular(width / 2)),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(WaveformPainter old) =>
      old.levels != levels || old.progress != progress || old.played != played || old.rest != rest;
}
