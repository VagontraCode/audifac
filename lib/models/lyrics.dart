/// One lyric line; [time] is null for unsynced lyrics.
class LyricLine {
  const LyricLine(this.time, this.text);

  final Duration? time;
  final String text;
}

enum LyricsSource { file, tags, picked }

/// A song's lyrics, parsed from LRC (`[mm:ss.xx] text`) or plain text.
class Lyrics {
  const Lyrics({required this.lines, required this.source});

  final List<LyricLine> lines;
  final LyricsSource source;

  bool get synced => lines.isNotEmpty && lines.first.time != null;

  static final _stamp = RegExp(r'\[(\d{1,3}):(\d{1,2})(?:[.:](\d{1,3}))?\]');
  static final _offset = RegExp(r'^\[offset:\s*([+-]?\d+)\]', caseSensitive: false);
  static final _metaTag = RegExp(r'^\[[a-zA-Z]+:.*\]$');

  /// Parses LRC; lines with several stamps (`[00:12][01:30] chorus`) repeat.
  /// Text without any stamps comes back unsynced, line by line.
  static Lyrics parse(String text, LyricsSource source) {
    final timed = <LyricLine>[];
    final plain = <LyricLine>[];
    var offsetMs = 0;
    for (final raw in text.replaceAll('\r\n', '\n').replaceAll('\r', '\n').split('\n')) {
      final line = raw.trimRight();
      final offset = _offset.firstMatch(line.trim());
      if (offset != null) {
        offsetMs = int.tryParse(offset.group(1)!) ?? 0;
        continue;
      }
      final stamps = _stamp.allMatches(line).toList();
      if (stamps.isEmpty) {
        // [ar:Artist], [ti:Title]… are LRC metadata, not lyrics.
        if (!_metaTag.hasMatch(line.trim())) plain.add(LyricLine(null, line.trim()));
        continue;
      }
      final words = line.substring(stamps.last.end).trim();
      for (final m in stamps) {
        final frac = m.group(3) ?? '0';
        final ms = int.parse(frac.padRight(3, '0').substring(0, 3));
        timed.add(LyricLine(
          Duration(minutes: int.parse(m.group(1)!), seconds: int.parse(m.group(2)!), milliseconds: ms),
          words,
        ));
      }
    }
    if (timed.isNotEmpty) {
      // LRC offset: positive = lyrics come earlier.
      final shifted = [
        for (final l in timed)
          LyricLine(Duration(milliseconds: (l.time!.inMilliseconds - offsetMs).clamp(0, 1 << 31)), l.text),
      ]..sort((a, b) => a.time!.compareTo(b.time!));
      return Lyrics(lines: shifted, source: source);
    }
    // Trim leading / trailing blank lines of plain lyrics.
    while (plain.isNotEmpty && plain.first.text.isEmpty) {
      plain.removeAt(0);
    }
    while (plain.isNotEmpty && plain.last.text.isEmpty) {
      plain.removeLast();
    }
    return Lyrics(lines: plain, source: source);
  }

  /// Index of the line being sung at [position] (−1 before the first).
  int indexAt(Duration position) {
    if (!synced) return -1;
    var lo = 0, hi = lines.length - 1, found = -1;
    while (lo <= hi) {
      final mid = (lo + hi) >> 1;
      if (lines[mid].time! <= position) {
        found = mid;
        lo = mid + 1;
      } else {
        hi = mid - 1;
      }
    }
    return found;
  }
}
