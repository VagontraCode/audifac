import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/lyrics.dart';
import '../models/song.dart';
import 'library_providers.dart';
import 'user_data_providers.dart';

String _key(Song song) => 'lyrics:${song.location}';

/// A song's lyrics: a file the user picked, else an `.lrc` beside it, else
/// its tags. Null when there are none.
final lyricsProvider = FutureProvider.family<Lyrics?, Song>((ref, song) async {
  final picked = await ref.read(databaseProvider).getValue(_key(song));
  if (picked != null && picked.isNotEmpty) return Lyrics.parse(picked, LyricsSource.picked);
  final found = await ref.read(mediaLibraryProvider).readLyrics(song);
  if (found == null) return null;
  final lyrics = Lyrics.parse(found.text, found.source == 'file' ? LyricsSource.file : LyricsSource.tags);
  return lyrics.lines.isEmpty ? null : lyrics;
});

/// Attach an `.lrc` / `.txt` file to [song] (for files Android won't let us
/// read beside it); null removes the attachment.
Future<void> setPickedLyrics(WidgetRef ref, Song song, String? text) async {
  final db = ref.read(databaseProvider);
  if (text == null) {
    await db.deleteValue(_key(song));
  } else {
    await db.setValue(_key(song), text);
  }
  ref.invalidate(lyricsProvider(song));
}

