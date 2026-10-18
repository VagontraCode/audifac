import 'package:flutter/widgets.dart';

/// Whether the app is on screen. UI-only work (position ticks, animations)
/// skips itself when it isn't, so playback in the background doesn't keep
/// the UI thread waking up for nothing.
abstract final class AppVisibility {
  static bool _visible = true;
  static AppLifecycleListener? _listener;

  static bool get visible {
    _listener ??= AppLifecycleListener(
      // "inactive" is still visible (notification shade, split screen).
      onStateChange: (s) => _visible = s == AppLifecycleState.resumed || s == AppLifecycleState.inactive,
    );
    return _visible;
  }
}
