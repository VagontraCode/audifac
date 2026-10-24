import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// Scrolling spectrogram: the newest column on the right, low frequencies at
/// the bottom, loudness as colour (dark → purple → orange → pale yellow).
class SpectrogramBuffer {
  SpectrogramBuffer({this.width = 160, this.height = 96}) : _pixels = Uint8List(width * height * 4) {
    for (var i = 3; i < _pixels.length; i += 4) {
      _pixels[i] = 255;
    }
  }

  final int width;
  final int height;
  final Uint8List _pixels;

  /// Where the next column goes; the image is drawn from here (oldest) on.
  int column = 0;
  ui.Image? image;
  bool _decoding = false;

  /// 256 RGB entries of a magma-like colour map.
  static final Uint8List palette = () {
    const stops = [
      (0.0, 0x000004),
      (0.25, 0x3B0F70),
      (0.5, 0x8C2981),
      (0.7, 0xDE4968),
      (0.85, 0xFE9F6D),
      (1.0, 0xFCFDBF),
    ];
    final out = Uint8List(256 * 3);
    for (var i = 0; i < 256; i++) {
      final t = i / 255;
      var s = 0;
      while (s < stops.length - 2 && t > stops[s + 1].$1) {
        s++;
      }
      final (t0, c0) = stops[s];
      final (t1, c1) = stops[s + 1];
      final k = ((t - t0) / (t1 - t0)).clamp(0.0, 1.0);
      for (var ch = 0; ch < 3; ch++) {
        final shift = 16 - 8 * ch;
        final a = (c0 >> shift) & 0xFF;
        final b = (c1 >> shift) & 0xFF;
        out[i * 3 + ch] = (a + (b - a) * k).round();
      }
    }
    return out;
  }();

  /// Adds one column of [levels] (low band first) and decodes a new image.
  void add(Uint8List levels, VoidCallback onImage) {
    if (levels.isEmpty) return;
    for (var y = 0; y < height; y++) {
      // Row 0 is the top: the highest band.
      final band = (height - 1 - y) * levels.length ~/ height;
      final v = levels[band];
      final p = (y * width + column) * 4;
      _pixels[p] = palette[v * 3];
      _pixels[p + 1] = palette[v * 3 + 1];
      _pixels[p + 2] = palette[v * 3 + 2];
    }
    column = (column + 1) % width;
    // One decode at a time: a slow phone skips images, not columns.
    if (_decoding) return;
    _decoding = true;
    ui.decodeImageFromPixels(Uint8List.fromList(_pixels), width, height, ui.PixelFormat.rgba8888, (img) {
      _decoding = false;
      image?.dispose();
      image = img;
      onImage();
    });
  }

  void dispose() {
    image?.dispose();
    image = null;
  }
}

class SpectrogramPainter extends CustomPainter {
  SpectrogramPainter(this.buffer, {required this.background}) : _column = buffer.column, _image = buffer.image;

  final SpectrogramBuffer buffer;
  final Color background;
  final int _column;
  final ui.Image? _image;

  @override
  void paint(Canvas canvas, Size size) {
    final rrect = RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(10));
    canvas.save();
    canvas.clipRRect(rrect);
    canvas.drawRect(Offset.zero & size, Paint()..color = background);
    final img = _image;
    if (img != null) {
      // Oldest columns ([column, width)) first, then [0, column).
      final w = img.width.toDouble();
      final h = img.height.toDouble();
      final split = _column.toDouble();
      final paint = Paint()..filterQuality = FilterQuality.low;
      final leftWidth = (w - split) / w * size.width;
      canvas.drawImageRect(img, Rect.fromLTWH(split, 0, w - split, h), Rect.fromLTWH(0, 0, leftWidth, size.height), paint);
      if (split > 0) {
        canvas.drawImageRect(img, Rect.fromLTWH(0, 0, split, h), Rect.fromLTWH(leftWidth, 0, size.width - leftWidth, size.height), paint);
      }
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(SpectrogramPainter old) => old._image != _image || old._column != _column;
}

/// Stereo image: each (L, R) pair as a dot, rotated 45° so mono stands
/// upright (M = L + R up, S = R − L across); the last few frames fade out.
class GoniometerPainter extends CustomPainter {
  GoniometerPainter({required this.frames, required this.color, required this.grid});

  /// Newest last.
  final List<Float32List> frames;
  final Color color;
  final Color grid;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = math.min(size.width, size.height) / 2;
    final line = Paint()
      ..color = grid
      ..strokeWidth = 1;
    // Axes: mono (vertical), left and right channels (diagonals).
    canvas.drawLine(Offset(c.dx, c.dy - r), Offset(c.dx, c.dy + r), line);
    canvas.drawLine(Offset(c.dx - r * 0.7, c.dy - r * 0.7), Offset(c.dx + r * 0.7, c.dy + r * 0.7), line);
    canvas.drawLine(Offset(c.dx + r * 0.7, c.dy - r * 0.7), Offset(c.dx - r * 0.7, c.dy + r * 0.7), line);
    canvas.drawCircle(c, r, line..style = PaintingStyle.stroke);

    for (final (i, pts) in frames.indexed) {
      final age = (i + 1) / frames.length;
      final paint = Paint()
        ..color = color.withValues(alpha: 0.15 + 0.6 * age)
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round;
      final points = <Offset>[];
      for (var p = 0; p + 1 < pts.length; p += 2) {
        final l = pts[p];
        final rr = pts[p + 1];
        // Full scale (|M| or |S| = 1) at the rim; a square root lifts quiet music.
        final m = (l + rr) / math.sqrt2;
        final s = (rr - l) / math.sqrt2;
        final mag = math.sqrt(m * m + s * s);
        if (mag < 1e-6) {
          points.add(c);
          continue;
        }
        final k = math.sqrt(math.min(1, mag)) / mag * r;
        points.add(Offset(c.dx + s * k, c.dy - m * k));
      }
      canvas.drawPoints(ui.PointMode.points, points, paint);
    }
  }

  @override
  bool shouldRepaint(GoniometerPainter old) => true;
}

/// −1 … +1 bar with a marker: green near mono, amber when wide, red when out
/// of phase.
class CorrelationMeter extends StatelessWidget {
  const CorrelationMeter({super.key, required this.value, required this.track, required this.label});

  final double value;
  final Color track;
  final String label;

  @override
  Widget build(BuildContext context) {
    final v = value.clamp(-1.0, 1.0);
    final color = v < 0 ? const Color(0xFFD70015) : (v < 0.3 ? const Color(0xFFF5A524) : const Color(0xFF34C759));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: 10,
          child: LayoutBuilder(
            builder: (context, box) => Stack(
              children: [
                Positioned.fill(
                  child: DecoratedBox(decoration: BoxDecoration(color: track, borderRadius: BorderRadius.circular(5))),
                ),
                Positioned(left: box.maxWidth / 2 - 0.5, top: 0, bottom: 0, child: Container(width: 1, color: Colors.black26)),
                Positioned(
                  left: (v + 1) / 2 * (box.maxWidth - 10),
                  top: 0,
                  bottom: 0,
                  child: Container(width: 10, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            const Text('−1'),
            Expanded(child: Text(label, textAlign: TextAlign.center)),
            const Text('+1'),
          ],
        ),
      ],
    );
  }
}

/// Keeps the last [length] goniometer frames.
class ScopeTrail {
  ScopeTrail({this.length = 4});

  final int length;
  final frames = <Float32List>[];

  void add(Float32List points) {
    if (points.isEmpty) return;
    frames.add(points);
    if (frames.length > length) frames.removeAt(0);
  }
}
