import 'package:flutter/material.dart';

/// Design tokens, one set per brightness. Widgets read them with
/// `context.palette` and never hardcode colors.
@immutable
class AppPalette extends ThemeExtension<AppPalette> {
  const AppPalette({
    required this.background,
    required this.surface,
    required this.ink,
    required this.inkSoft,
    required this.inkMuted,
    required this.line,
    required this.artwork,
    required this.onInk,
    required this.elevated,
    required this.onElevated,
    required this.lossless,
    required this.hiRes,
  });

  /// Page background.
  final Color background;

  /// Cards, sheets, nav bar.
  final Color surface;

  /// Primary text / icons, and the fill of prominent buttons.
  final Color ink;
  final Color inkSoft;

  /// Secondary text.
  final Color inkMuted;

  /// Dividers and outlines.
  final Color line;

  /// Artwork placeholder.
  final Color artwork;

  /// Content drawn on top of [ink] fills.
  final Color onInk;

  /// Floating dark surfaces (mini player, snackbars).
  final Color elevated;
  final Color onElevated;

  /// Quality labels: lossless files and Hi-Res files stand out.
  final Color lossless;
  final Color hiRes;

  static const light = AppPalette(
    background: Color(0xFFF5F5F7),
    surface: Color(0xFFFFFFFF),
    ink: Color(0xFF1C1C1E),
    inkSoft: Color(0xFF3A3A3C),
    inkMuted: Color(0xFF6E6E73),
    line: Color(0xFFE5E5EA),
    artwork: Color(0xFF2C2C2E),
    onInk: Color(0xFFFFFFFF),
    elevated: Color(0xFF1C1C1E),
    onElevated: Color(0xFFFFFFFF),
    lossless: Color(0xFF00805A),
    hiRes: Color(0xFFA86A00),
  );

  static const dark = AppPalette(
    background: Color(0xFF0B0B0D),
    surface: Color(0xFF1A1A1D),
    ink: Color(0xFFF5F5F7),
    inkSoft: Color(0xFFD1D1D6),
    inkMuted: Color(0xFF98989F),
    line: Color(0xFF2C2C30),
    artwork: Color(0xFF2C2C2E),
    onInk: Color(0xFF1C1C1E),
    elevated: Color(0xFF26262A),
    onElevated: Color(0xFFFFFFFF),
    lossless: Color(0xFF4CD9A0),
    hiRes: Color(0xFFF5C451),
  );

  @override
  AppPalette copyWith({
    Color? background,
    Color? surface,
    Color? ink,
    Color? inkSoft,
    Color? inkMuted,
    Color? line,
    Color? artwork,
    Color? onInk,
    Color? elevated,
    Color? onElevated,
    Color? lossless,
    Color? hiRes,
  }) {
    return AppPalette(
      background: background ?? this.background,
      surface: surface ?? this.surface,
      ink: ink ?? this.ink,
      inkSoft: inkSoft ?? this.inkSoft,
      inkMuted: inkMuted ?? this.inkMuted,
      line: line ?? this.line,
      artwork: artwork ?? this.artwork,
      onInk: onInk ?? this.onInk,
      elevated: elevated ?? this.elevated,
      onElevated: onElevated ?? this.onElevated,
      lossless: lossless ?? this.lossless,
      hiRes: hiRes ?? this.hiRes,
    );
  }

  @override
  AppPalette lerp(AppPalette? other, double t) {
    if (other == null) return this;
    return AppPalette(
      background: Color.lerp(background, other.background, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      ink: Color.lerp(ink, other.ink, t)!,
      inkSoft: Color.lerp(inkSoft, other.inkSoft, t)!,
      inkMuted: Color.lerp(inkMuted, other.inkMuted, t)!,
      line: Color.lerp(line, other.line, t)!,
      artwork: Color.lerp(artwork, other.artwork, t)!,
      onInk: Color.lerp(onInk, other.onInk, t)!,
      elevated: Color.lerp(elevated, other.elevated, t)!,
      onElevated: Color.lerp(onElevated, other.onElevated, t)!,
      lossless: Color.lerp(lossless, other.lossless, t)!,
      hiRes: Color.lerp(hiRes, other.hiRes, t)!,
    );
  }
}

extension PaletteContext on BuildContext {
  AppPalette get palette => Theme.of(this).extension<AppPalette>() ?? AppPalette.light;
}
