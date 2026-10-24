import 'song.dart';

/// One line of a playlist file: where the song was, plus `#EXTINF` details.
class M3uEntry {
  const M3uEntry({required this.location, this.title, this.artist, this.seconds});

  final String location;
  final String? title;
  final String? artist;
  final int? seconds;
}

/// M3U / M3U8 playlists (the format every player reads). Imported entries are
/// matched to the library by path — absolute, relative, a PC's or another
/// phone's — then by `#EXTINF` artist and title.
class M3u {
  /// The `#PLAYLIST:` name, if any.
  static String? name(String text) {
    for (final line in text.split(RegExp(r'\r?\n'))) {
      final l = line.trim();
      if (l.startsWith('#PLAYLIST:')) return l.substring(10).trim();
    }
    return null;
  }

  static List<M3uEntry> parse(String text) {
    final out = <M3uEntry>[];
    String? title;
    String? artist;
    int? seconds;
    for (final raw in text.split(RegExp(r'\r?\n'))) {
      final line = raw.trim().replaceFirst('\uFEFF', '');
      if (line.isEmpty) continue;
      if (line.startsWith('#EXTINF:')) {
        // #EXTINF:215,Artist - Title (attributes like tvg-id="" may sit before the comma).
        final body = line.substring(8);
        final comma = body.indexOf(',');
        seconds = int.tryParse((comma < 0 ? body : body.substring(0, comma)).trim().split(' ').first);
        final info = comma < 0 ? '' : body.substring(comma + 1).trim();
        final dash = info.indexOf(' - ');
        artist = dash > 0 ? info.substring(0, dash).trim() : null;
        title = (dash > 0 ? info.substring(dash + 3) : info).trim();
        if (title.isEmpty) title = null;
        continue;
      }
      if (line.startsWith('#')) continue;
      out.add(M3uEntry(location: line, title: title, artist: artist, seconds: seconds));
      title = artist = null;
      seconds = null;
    }
    return out;
  }

  /// `file:///storage/…%20x.flac`, `C:\Music\x.flac`, `../x.flac` →
  /// lowercase path components (`storage`, `…`, `x.flac`); null for streams.
  static List<String>? components(String location) {
    var s = location;
    if (RegExp(r'^[a-z][a-z0-9+.-]*://', caseSensitive: false).hasMatch(s)) {
      if (!s.toLowerCase().startsWith('file://')) return null; // http, content…
      s = Uri.decodeFull(s.substring(7));
    }
    final parts = s
        .replaceAll('\\', '/')
        .split('/')
        .where((p) => p.isNotEmpty && p != '.' && p != '..' && !RegExp(r'^[a-zA-Z]:$').hasMatch(p))
        .map((p) => p.toLowerCase())
        .toList();
    return parts.isEmpty ? null : parts;
  }

  static String _key(String s) => s.toLowerCase().replaceAll(RegExp(r'[^\p{L}\p{N}]+', unicode: true), '');

  /// The library song for each entry (null when not found), in order.
  static List<Song?> match(List<M3uEntry> entries, List<Song> library) {
    final byFile = <String, List<(Song, List<String>)>>{};
    final byTags = <String, Song>{};
    for (final s in library) {
      final parts = components(s.path ?? s.location);
      if (parts != null) (byFile[parts.last] ??= []).add((s, parts));
      byTags.putIfAbsent('${_key(s.artist)}|${_key(s.title)}', () => s);
      byTags.putIfAbsent('|${_key(s.title)}', () => s);
    }
    Song? find(M3uEntry e) {
      final parts = components(e.location);
      if (parts != null) {
        // Most trailing folders in common wins: "Album/01.flac" picks the
        // right "01.flac" among several.
        Song? best;
        var bestScore = 0;
        for (final (song, path) in byFile[parts.last] ?? const <(Song, List<String>)>[]) {
          var score = 1;
          while (score < parts.length && score < path.length && parts[parts.length - 1 - score] == path[path.length - 1 - score]) {
            score++;
          }
          if (score > bestScore) {
            best = song;
            bestScore = score;
          }
        }
        if (best != null) return best;
      }
      if (e.title == null) return null;
      return byTags['${_key(e.artist ?? '')}|${_key(e.title!)}'] ?? (e.artist == null ? byTags['|${_key(e.title!)}'] : null);
    }

    return [for (final e in entries) find(e)];
  }

  /// An extended M3U8 (UTF-8) with absolute paths, which Android players open.
  static String write(String name, List<Song> songs) {
    final b = StringBuffer('#EXTM3U\n#PLAYLIST:${name.replaceAll('\n', ' ')}\n');
    for (final s in songs) {
      final artist = s.artist == Song.unknownArtist ? '' : '${s.artist} - ';
      b
        ..write('#EXTINF:${s.duration.inSeconds},$artist${s.title}\n')
        ..write('${s.path ?? s.location}\n');
    }
    return b.toString();
  }
}
