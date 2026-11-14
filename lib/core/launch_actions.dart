import 'package:flutter/services.dart';

/// What a launcher shortcut asks for (`android/.../res/xml/shortcuts.xml`).
enum LaunchAction { shuffle, favorites, soiree, search }

/// Receives launcher shortcuts from `MainActivity` (channel `audifac/launch`).
///
/// A shortcut either arrives while the app runs (pushed) or started the app
/// (taken once at start-up); each carries an id so it's handled only once.
class LaunchActions {
  LaunchActions(this._onAction);

  static const _channel = MethodChannel('audifac/launch');

  final void Function(LaunchAction action) _onAction;
  final _handled = <int>{};

  /// Starts listening and handles a shortcut that launched the app.
  Future<void> start() async {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'action') _handle(call.arguments);
      return true;
    });
    try {
      _handle(await _channel.invokeMethod<Object?>('take'));
    } on MissingPluginException {
      // Not on Android (tests, iOS).
    } on PlatformException {
      // Same.
    }
  }

  void stop() => _channel.setMethodCallHandler(null);

  void _handle(Object? launch) {
    if (launch is! Map) return;
    final id = launch['id'];
    final action = LaunchAction.values.asNameMap()[launch['action']];
    if (id is! int || action == null || !_handled.add(id)) return;
    _onAction(action);
  }
}
