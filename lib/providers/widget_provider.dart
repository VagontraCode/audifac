import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'player_providers.dart';

/// Keeps the home-screen widget (`PlayerWidget.kt`) showing what's playing.
final homeWidgetSyncProvider = Provider<void>((ref) {
  const channel = MethodChannel('audifac/widget');
  final item = ref.watch(mediaItemProvider).value;
  final playing = ref.watch(isPlayingProvider);
  final art = item?.artUri;
  channel.invokeMethod('update', {
    'title': item?.title,
    'artist': item?.artist,
    'playing': playing,
    'art': art != null && art.isScheme('file') ? art.toFilePath() : null,
  }).catchError((_) => null); // Not on Android / no widget code (tests).
});

/// Asks the launcher to add the widget; false when it can't (then the user
/// adds it from the launcher's widget list).
Future<bool> pinHomeWidget() async {
  try {
    return await const MethodChannel('audifac/widget').invokeMethod<bool>('pin') ?? false;
  } catch (_) {
    return false;
  }
}
