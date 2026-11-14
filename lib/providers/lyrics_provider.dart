import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/lrclib.dart';
import '../models/lyrics.dart';
import '../models/song.dart';
import 'library_providers.dart';
import 'user_data_providers.dart';

String _key(Song song) => 'lyrics:${song.location}';
String _onlineKey(Song song) => 'lyrics_online:${song.location}';

final lrcLibProvider = Provider<LrcLib>((ref) => LrcLib());

/// A song's lyrics: a file the user picked, else an `.lrc` beside it, else
/// its tags, else lyrics found online earlier. Null when there are none.
final lyricsProvider = FutureProvider.family<Lyrics?, Song>((ref, song) async {
  final db = ref.read(databaseProvider);
  final picked = await db.getValue(_key(song));
  if (picked != null && picked.isNotEmpty) return Lyrics.parse(picked, LyricsSource.picked);
  final found = await ref.read(mediaLibraryProvider).readLyrics(song);
  if (found != null) {
    final lyrics = Lyrics.parse(found.text, found.source == 'file' ? LyricsSource.file : LyricsSource.tags);
    if (lyrics.lines.isNotEmpty) return lyrics;
  }
  final online = await db.getValue(_onlineKey(song));
  if (online != null && online.isNotEmpty) {
    final lyrics = Lyrics.parse(online, LyricsSource.online);
    if (lyrics.lines.isNotEmpty) return lyrics;
  }
  return null;
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

/// Looks [song] up on LRCLIB and keeps what's found. False when nothing
/// matches; throws on network errors.
Future<bool> fetchOnlineLyrics(WidgetRef ref, Song song) async {
  final text = await ref.read(lrcLibProvider).find(
        title: song.title,
        // "Unknown artist" is our placeholder, not a name to search for.
        artist: song.artist == Song.unknownArtist ? null : song.artist,
        album: song.album,
        duration: song.duration,
      );
  if (text == null) return false;
  await ref.read(databaseProvider).setValue(_onlineKey(song), text);
  ref.invalidate(lyricsProvider(song));
  return true;
}

/// Forgets lyrics found online for [song].
Future<void> removeOnlineLyrics(WidgetRef ref, Song song) async {
  await ref.read(databaseProvider).deleteValue(_onlineKey(song));
  ref.invalidate(lyricsProvider(song));
}
