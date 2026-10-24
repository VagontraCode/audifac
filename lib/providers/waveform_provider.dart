import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/song.dart';
import 'eq_providers.dart';
import 'user_data_providers.dart';

const _version = 2;

/// The seek bar's waveform for [song]: from the cache, else decoded once in
/// the background and kept. Null while unknown or when it can't be made.
final waveformProvider = FutureProvider.autoDispose.family<Uint8List?, Song>((ref, song) async {
  if (song.duration <= Duration.zero) return null;
  final db = ref.read(databaseProvider);
  // The version changes with the native levels' scale, so older ones are remade.
  final key = '${song.key}#w$_version';
  final cached = await db.waveform(key, size: song.sizeBytes, modified: song.modifiedMs);
  if (cached != null) return cached;
  final levels = await ref.read(dspChannelProvider).waveform(song);
  if (levels == null || levels.isEmpty) return null;
  await db.putWaveform(key, size: song.sizeBytes, modified: song.modifiedMs, levels: levels);
  return levels;
});
