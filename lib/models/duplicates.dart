import 'audio_info.dart';
import 'loudness.dart';
import 'song.dart';

/// The same recording in several files (formats, rips, copies): songs with
/// the same artist and title (ignoring case, punctuation and "feat." credits)
/// whose lengths differ by at most [toleranceSeconds]. [songs] is best first.
class DuplicateGroup {
  const DuplicateGroup(this.songs);

  final List<Song> songs;

  Song get best => songs.first;
}

class Duplicates {
  static const toleranceSeconds = 3;

  /// "Song Title (feat. X)!" → "song title".
  static String normalize(String s) => s
      .toLowerCase()
      .replaceAll(RegExp(r'[\(\[]?\s*\b(feat|ft|featuring)\b\.?.*$'), '')
      .replaceAll(RegExp(r'[^\p{L}\p{N}]+', unicode: true), ' ')
      .trim();

  /// How good a copy is: lossless before lossy (a lossless file cut like an
  /// MP3 counts as lossy), then bit depth and sample rate, then bitrate, then
  /// dynamic range (a less compressed master).
  static List<num> rank(AudioInfo info, LoudnessInfo? loudness) {
    final fake = info.quality.isLossless && (loudness?.lossyCutoff ?? false);
    final tier = switch (info.quality) {
      AudioQuality.hiRes when !fake => 3,
      AudioQuality.lossless when !fake => 2,
      AudioQuality.unknown => 0,
      _ => 1,
    };
    // A fake lossless file's resolution says nothing: the original MP3 wins.
    if (fake) return [tier, 0, 0, 0, loudness?.dr ?? 0];
    return [tier, info.bitDepth ?? 0, info.sampleRate ?? 0, info.kbpsOrNull ?? 0, loudness?.dr ?? 0];
  }

  static int _compare(List<num> a, List<num> b) {
    for (var i = 0; i < a.length; i++) {
      final c = b[i].compareTo(a[i]);
      if (c != 0) return c;
    }
    return 0;
  }

  /// Groups of two or more copies, largest first.
  static List<DuplicateGroup> find(
    List<Song> songs,
    AudioInfo Function(Song) info,
    LoudnessInfo? Function(Song) loudness,
  ) {
    final byName = <String, List<Song>>{};
    for (final s in songs) {
      final title = normalize(s.title);
      if (title.isEmpty) continue;
      final artist = s.artist == Song.unknownArtist ? '' : normalize(s.artist);
      (byName['$artist\u0000$title'] ??= []).add(s);
    }
    final groups = <DuplicateGroup>[];
    for (final same in byName.values) {
      if (same.length < 2) continue;
      // Split by length: a live take or a remix isn't a copy.
      same.sort((a, b) => a.duration.compareTo(b.duration));
      var run = <Song>[same.first];
      void close() {
        if (run.length < 2) return;
        final ranks = {for (final s in run) s.id: rank(info(s), loudness(s))};
        groups.add(DuplicateGroup(run..sort((a, b) => _compare(ranks[a.id]!, ranks[b.id]!))));
      }

      for (final s in same.skip(1)) {
        if ((s.duration - run.last.duration).inSeconds.abs() > toleranceSeconds) {
          close();
          run = [s];
        } else {
          run.add(s);
        }
      }
      close();
    }
    groups.sort((a, b) {
      final c = b.songs.length.compareTo(a.songs.length);
      return c != 0 ? c : a.best.title.toLowerCase().compareTo(b.best.title.toLowerCase());
    });
    return groups;
  }
}
