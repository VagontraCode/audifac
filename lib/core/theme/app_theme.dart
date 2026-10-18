import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_colors.dart';

abstract final class AppTheme {
  static ThemeData light() => _build(Brightness.light, AppPalette.light);
  static ThemeData dark() => _build(Brightness.dark, AppPalette.dark);

  static ThemeData _build(Brightness brightness, AppPalette p) {
    final isDark = brightness == Brightness.dark;
    final scheme = ColorScheme(
      brightness: brightness,
      primary: p.ink,
      onPrimary: p.onInk,
      secondary: p.inkSoft,
      onSecondary: p.onInk,
      error: const Color(0xFFD70015),
      onError: Colors.white,
      surface: p.background,
      onSurface: p.ink,
      onSurfaceVariant: p.inkMuted,
      surfaceContainerLowest: p.surface,
      surfaceContainerLow: p.surface,
      surfaceContainer: p.surface,
      surfaceContainerHigh: p.surface,
      surfaceContainerHighest: p.surface,
      outline: p.inkMuted,
      outlineVariant: p.line,
    );

    final base = ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: p.background,
      splashFactory: InkSparkle.splashFactory,
      extensions: [p],
    );

    final text = base.textTheme.apply(bodyColor: p.ink, displayColor: p.ink);

    return base.copyWith(
      textTheme: text.copyWith(
        headlineLarge: text.headlineLarge?.copyWith(
          fontWeight: FontWeight.w800,
          letterSpacing: -0.5,
        ),
        headlineSmall: text.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
        titleMedium: text.titleMedium?.copyWith(fontWeight: FontWeight.w600),
        bodyMedium: text.bodyMedium?.copyWith(color: p.inkMuted),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: p.background,
        foregroundColor: p.ink,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        systemOverlayStyle: isDark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
      ),
      tabBarTheme: TabBarThemeData(
        labelColor: p.ink,
        unselectedLabelColor: p.inkMuted,
        indicatorColor: p.ink,
        indicatorSize: TabBarIndicatorSize.label,
        dividerColor: Colors.transparent,
        labelStyle: const TextStyle(fontWeight: FontWeight.w700, letterSpacing: 0.4),
        tabAlignment: TabAlignment.start,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: p.surface,
        surfaceTintColor: Colors.transparent,
        indicatorColor: p.background,
        height: 64,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysHide,
      ),
      sliderTheme: SliderThemeData(
        activeTrackColor: p.ink,
        inactiveTrackColor: p.line,
        thumbColor: p.ink,
        overlayColor: p.ink.withValues(alpha: 0.12),
        trackHeight: 4,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: p.surface,
        hintStyle: TextStyle(color: p.inkMuted),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: p.surface,
        surfaceTintColor: Colors.transparent,
        showDragHandle: true,
        dragHandleColor: p.line,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: p.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: p.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      listTileTheme: ListTileThemeData(iconColor: p.ink, textColor: p.ink),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: p.elevated,
        contentTextStyle: TextStyle(color: p.onElevated),
        actionTextColor: p.onElevated,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(color: p.ink),
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: PredictiveBackPageTransitionsBuilder(),
        },
      ),
    );
  }
}
