import 'song.dart';

class CueTrack {
  const CueTrack({required this.number, required this.start, this.title, this.performer});

  final int number;

  /// `INDEX 01`: where the track starts in the file.
  final Duration start;
  final String? title;
  final String? performer;
}

/// A `.cue` file: one audio file (`FILE`) split into tracks. Only sheets
/// describing a single file are used (the usual "one-file album" rip).
class CueSheet {
  const CueSheet({
    required this.path,
    required this.file,
    required this.tracks,
    this.title,
    this.performer,
    this.genre,
    this.date,
  });

  /// Where the `.cue` itself is.
  final String path;

  /// The `FILE` it describes, as written (usually a bare file name).
  final String file;
  final List<CueTrack> tracks;
  final String? title;
  final String? performer;
  final String? genre;
  final String? date;

  String get folder => path.substring(0, path.lastIndexOf('/').clamp(0, path.length));

  /// Null for sheets that aren't one file with two or more tracks.
  static CueSheet? parse(String text, String path) {
    final files = <String>[];
    final tracks = <CueTrack>[];
    String? title;
    String? performer;
    String? genre;
    String? date;
    // The track being read.
    int? number;
    String? trackTitle;
    String? trackPerformer;
    Duration? start;
    // Past the first TRACK: TITLE / PERFORMER belong to tracks (even data ones).
    var inTrack = false;

    void endTrack() {
      if ((number, start) case (final n?, final s?)) {
        tracks.add(CueTrack(number: n, start: s, title: trackTitle, performer: trackPerformer));
      }
      number = null;
      start = null;
      trackTitle = null;
      trackPerformer = null;
    }

    for (final raw in text.split(RegExp(r'\r?\n'))) {
      final line = raw.trim().replaceFirst(String.fromCharCode(0xFEFF), '');
      final space = line.indexOf(' ');
      if (space < 0) continue;
      final command = line.substring(0, space).toUpperCase();
      final rest = line.substring(space + 1).trim();
      switch (command) {
        case 'FILE':
          files.add(_unquote(rest.replaceFirst(RegExp(r'\s+\w+$'), '')));
        case 'TRACK':
          endTrack();
          inTrack = true;
          final parts = rest.split(RegExp(r'\s+'));
          // Data tracks (enhanced CDs) aren't audio.
          if (parts.length < 2 || parts[1].toUpperCase() == 'AUDIO') number = int.tryParse(parts.first);
        case 'TITLE':
          if (!inTrack) {
            title = _unquote(rest);
          } else {
            trackTitle = _unquote(rest);
          }
        case 'PERFORMER':
          if (!inTrack) {
            performer = _unquote(rest);
          } else {
            trackPerformer = _unquote(rest);
          }
        case 'INDEX':
          final parts = rest.split(RegExp(r'\s+'));
          if (number != null && parts.length == 2 && int.tryParse(parts[0]) == 1) start = _time(parts[1]);
        case 'REM':
          final rem = rest.indexOf(' ');
          if (rem < 0) break;
          final value = _unquote(rest.substring(rem + 1).trim());
          switch (rest.substring(0, rem).toUpperCase()) {
            case 'GENRE':
              genre = value;
            case 'DATE':
              date = value;
          }
      }
    }
    endTrack();
    if (files.length != 1 || tracks.length < 2) return null;
    tracks.sort((a, b) => a.start.compareTo(b.start));
    return CueSheet(
      path: path,
      file: files.single,
      tracks: tracks,
      title: title,
      performer: performer,
      genre: genre,
      date: date,
    );
  }

  static String _unquote(String s) =>
      s.length >= 2 && s.startsWith('"') && s.endsWith('"') ? s.substring(1, s.length - 1).trim() : s.trim();

  /// `mm:ss:ff`, 75 frames a second (CD sectors).
  static Duration? _time(String s) {
    final p = s.split(':').map(int.tryParse).toList();
    if (p.length != 3 || p.any((x) => x == null)) return null;
    return Duration(microseconds: ((p[0]! * 60 + p[1]!) * 1000000 + p[2]! * 1000000 ~/ 75));
  }

  static String _stem(String name) {
    final slash = name.replaceAll('\\', '/').lastIndexOf('/');
    final base = name.replaceAll('\\', '/').substring(slash + 1);
    final dot = base.lastIndexOf('.');
    return (dot > 0 ? base.substring(0, dot) : base).toLowerCase();
  }

  /// The library song this sheet splits: the named file in the sheet's
  /// folder; else the one with the same name and another extension (sheets
  /// often say `.wav` for what was later compressed to FLAC); else the
  /// audio file named like the sheet.
  Song? audioIn(Iterable<Song> folderSongs) {
    final named = file.replaceAll('\\', '/').split('/').last.toLowerCase();
    Song? byStem;
    Song? bySheet;
    for (final s in folderSongs) {
      final name = (s.path ?? '').split('/').last.toLowerCase();
      if (name == named) return s;
      if (_stem(name) == _stem(named)) byStem ??= s;
      if (_stem(name) == _stem(path)) bySheet ??= s;
    }
    return byStem ?? bySheet;
  }

  /// The tracks of [file] as songs (ids stable per sheet and track).
  List<Song> split(Song file) {
    final artist = performer ?? file.artist;
    final album = title ?? file.album;
    final albumId = -Song.stableId('cue:$path');
    return [
      for (final (i, t) in tracks.indexed)
        if (i + 1 >= tracks.length || tracks[i + 1].start > t.start)
          Song(
            id: -Song.stableId('cue:$path#${t.number}'),
            uri: file.uri,
            path: file.path,
            title: t.title ?? 'Track ${t.number}',
            artist: t.performer ?? artist,
            artistId: -Song.stableId('artist:${t.performer ?? artist}'),
            album: album,
            albumId: albumId,
            duration: (i + 1 < tracks.length ? tracks[i + 1].start : file.duration) - t.start,
            trackNumber: t.number,
            dateAdded: file.dateAdded,
            mimeType: file.mimeType,
            sizeBytes: file.sizeBytes,
            modifiedMs: file.modifiedMs,
            isMusic: file.isMusic,
            clipStart: t.start,
            clipEnd: i + 1 < tracks.length ? tracks[i + 1].start : null,
          ),
    ];
  }

  /// [songs] with every file described by one of [sheets] replaced by its tracks.
  static List<Song> apply(List<Song> songs, List<CueSheet> sheets) {
    if (sheets.isEmpty) return songs;
    final byFolder = <String, List<Song>>{};
    for (final s in songs) {
      if (s.folder case final f?) (byFolder[f] ??= []).add(s);
    }
    final replaced = <int, List<Song>>{};
    for (final sheet in sheets) {
      final file = sheet.audioIn(byFolder[sheet.folder] ?? const []);
      // The file must be long enough for the sheet (not a single track
      // that happens to share the folder).
      if (file == null || replaced.containsKey(file.id) || file.duration <= sheet.tracks.last.start) continue;
      replaced[file.id] = sheet.split(file);
    }
    if (replaced.isEmpty) return songs;
    return [
      for (final s in songs) ...replaced[s.id] ?? [s],
    ];
  }
}
