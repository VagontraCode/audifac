import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:material_color_utilities/material_color_utilities.dart';

/// Colors derived from an album cover, used to tint the player.
@immutable
class ArtworkColors {
  const ArtworkColors({
    required this.tint,
    required this.accent,
    required this.onAccent,
  });

  /// Soft background wash behind the player.
  final Color tint;

  /// Play button / seek bar.
  final Color accent;
  final Color onAccent;

  static ArtworkColors fromSeed(int seed, Brightness brightness) {
    final hct = Hct.fromInt(seed);
    // Keep some colour even for muted covers, but never neon.
    final palette = TonalPalette.of(hct.hue, hct.chroma.clamp(24, 60).toDouble());
    final dark = brightness == Brightness.dark;
    return ArtworkColors(
      tint: Color(palette.get(dark ? 22 : 88)),
      accent: Color(palette.get(dark ? 80 : 35)),
      onAccent: Color(palette.get(dark ? 15 : 100)),
    );
  }
}

/// Dominant "theme-worthy" color of an image, or null for grayscale /
/// unsuitable artwork.
Future<int?> extractSeedColor(Uint8List imageBytes) async {
  final codec = await ui.instantiateImageCodec(imageBytes, targetWidth: 64, targetHeight: 64);
  final frame = await codec.getNextFrame();
  final data = await frame.image.toByteData(format: ui.ImageByteFormat.rawRgba);
  frame.image.dispose();
  codec.dispose();
  if (data == null) return null;

  final pixels = <int>[];
  for (var i = 0; i + 3 < data.lengthInBytes; i += 4) {
    final a = data.getUint8(i + 3);
    if (a < 255) continue;
    final r = data.getUint8(i);
    final g = data.getUint8(i + 1);
    final b = data.getUint8(i + 2);
    pixels.add((a << 24) | (r << 16) | (g << 8) | b);
  }
  if (pixels.isEmpty) return null;

  final result = await QuantizerCelebi().quantize(pixels, 64);
  const none = 0;
  final ranked = Score.score(result.colorToCount, desired: 1, fallbackColorARGB: none);
  return ranked.first == none ? null : ranked.first;
}
