import 'dart:convert';

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

/// A saved resume spot: where, and when it was saved (null for spots saved
/// by older versions, which stored only the position).
typedef ResumeSpot = ({Duration position, DateTime? savedAt});

/// Stored as `position ms|saved at ms` (older versions: `position ms`).
String encodeResumeSpot(Duration position, DateTime savedAt) =>
    '${position.inMilliseconds}|${savedAt.millisecondsSinceEpoch}';

ResumeSpot? decodeResumeSpot(String? value) {
  if (value == null) return null;
  final parts = value.split('|');
  final ms = int.tryParse(parts.first);
  if (ms == null) return null;
  final at = parts.length > 1 ? int.tryParse(parts[1]) : null;
  return (
    position: Duration(milliseconds: ms),
    savedAt: at == null ? null : DateTime.fromMillisecondsSinceEpoch(at),
  );
}

/// A spot marked in a long recording, with an optional note.
class Bookmark {
  const Bookmark(this.position, [this.note = '']);

  final Duration position;
  final String note;

  Map<String, Object> toJson() => {'ms': position.inMilliseconds, if (note.isNotEmpty) 'note': note};

  static Bookmark? fromJson(Object? json) {
    if (json is! Map || json['ms'] is! int) return null;
    return Bookmark(Duration(milliseconds: json['ms'] as int), json['note'] is String ? json['note'] as String : '');
  }

  /// A list, kept in playing order.
  static String encodeAll(List<Bookmark> bookmarks) => jsonEncode([for (final b in bookmarks) b.toJson()]);

  static List<Bookmark> decodeAll(String? value) {
    if (value == null) return const [];
    try {
      final list = jsonDecode(value);
      if (list is! List) return const [];
      return [for (final item in list) ?Bookmark.fromJson(item)]..sort((a, b) => a.position.compareTo(b.position));
    } on FormatException {
      return const [];
    }
  }

  @override
  bool operator ==(Object other) => other is Bookmark && other.position == position && other.note == note;

  @override
  int get hashCode => Object.hash(position, note);
}
