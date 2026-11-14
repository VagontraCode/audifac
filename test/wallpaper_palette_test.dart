import 'package:audifac/core/theme/app_colors.dart';
import 'package:audifac/models/app_settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

double contrast(Color a, Color b) {
  final la = a.computeLuminance(), lb = b.computeLuminance();
  final (hi, lo) = la > lb ? (la, lb) : (lb, la);
  return (hi + 0.05) / (lo + 0.05);
}

void main() {
  // Saturated and pale wallpapers of several hues.
  const seeds = [0xFFE53935, 0xFF1E88E5, 0xFF43A047, 0xFFFDD835, 0xFF8E24AA, 0xFFB0BEC5, 0xFF795548];

  for (final brightness in Brightness.values) {
    test('$brightness: wallpaper palettes stay readable', () {
      for (final seed in seeds) {
        final p = AppPalette.fromSeed(seed, brightness);
        expect(contrast(p.ink, p.background), greaterThanOrEqualTo(7), reason: 'ink on background, seed ${seed.toRadixString(16)}');
        expect(contrast(p.ink, p.surface), greaterThanOrEqualTo(7), reason: 'ink on surface');
        expect(contrast(p.onInk, p.ink), greaterThanOrEqualTo(7), reason: 'button text');
        expect(contrast(p.inkMuted, p.background), greaterThanOrEqualTo(4.5), reason: 'secondary text');
        expect(contrast(p.onElevated, p.elevated), greaterThanOrEqualTo(7), reason: 'snackbars / mini player');
      }
    });
  }

  test('the setting is off by default and saved', () {
    expect(const AppSettings().wallpaperColors, isFalse);
    final on = const AppSettings().copyWith(wallpaperColors: true);
    expect(AppSettings.fromKeyValues(on.toKeyValues()).wallpaperColors, isTrue);
    expect(AppSettings.fromKeyValues(const {}).wallpaperColors, isFalse);
  });
}
