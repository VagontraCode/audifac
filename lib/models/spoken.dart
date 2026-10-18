import 'song.dart';
import 'song_source.dart';

/// Audiobooks, podcasts and other long recordings: they resume where you
/// left them, play at the spoken-word speed and get skip buttons.
bool isLongForm(Song song) {
  final ext = (song.path ?? song.uri).split('.').last.toLowerCase();
  if (ext == 'm4b' || song.isPodcast) return true;
  final category = SongSource.of(song).category;
  if (category == SourceCategory.audiobooks || category == SourceCategory.podcasts) return true;
  return song.duration >= const Duration(minutes: 30);
}

/// Worth asking the native side for MP4 chapters?
bool mayHaveChapters(Song song) {
  final ext = (song.path ?? song.uri).split('.').last.toLowerCase();
  final mime = song.mimeType ?? '';
  return const {'m4b', 'm4a', 'mp4', 'aac'}.contains(ext) || mime.contains('mp4') || mime.contains('m4a');
}

class Chapter {
  const Chapter(this.start, this.title);

  final Duration start;
  final String title;
}

/// Index of the chapter playing at [position] (0 before the first starts).
int chapterAt(List<Chapter> chapters, Duration position) {
  var found = 0;
  for (var i = 0; i < chapters.length; i++) {
    if (chapters[i].start <= position) found = i;
  }
  return found;
}

/// Where to resume a long recording: null to start over (no saved spot,
/// barely started, or practically finished).
Duration? resumePoint(Duration? saved, Duration length) {
  if (saved == null || saved < const Duration(seconds: 10)) return null;
  if (length > Duration.zero && saved > length - const Duration(seconds: 30)) return null;
  // Back up a few seconds to pick the thread up again.
  final back = saved - const Duration(seconds: 3);
  return back < Duration.zero ? Duration.zero : back;
}
