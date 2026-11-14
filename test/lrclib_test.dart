import 'package:audifac/data/lrclib.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('lyricsOf: synced first, plain next, nothing for instrumentals', () {
    expect(LrcLib.lyricsOf({'syncedLyrics': '[00:01.00] hi', 'plainLyrics': 'hi'}), '[00:01.00] hi');
    expect(LrcLib.lyricsOf({'syncedLyrics': null, 'plainLyrics': 'hi'}), 'hi');
    expect(LrcLib.lyricsOf({'syncedLyrics': '  ', 'plainLyrics': ''}), isNull);
    expect(LrcLib.lyricsOf({'instrumental': true, 'plainLyrics': 'x'}), isNull);
  });

  test('pickBest: right length only, synced before plain, closest length', () {
    final results = [
      {'duration': 200.0, 'plainLyrics': 'plain close'},
      {'duration': 202.5, 'syncedLyrics': '[00:01.00] synced'},
      {'duration': 201.0, 'syncedLyrics': '[00:01.00] synced closer'},
      {'duration': 260.0, 'syncedLyrics': '[00:01.00] other version'},
      'garbage',
    ];
    expect(LrcLib.pickBest(results, const Duration(seconds: 200)), '[00:01.00] synced closer');
    expect(LrcLib.pickBest(results, const Duration(seconds: 400)), isNull);
  });

  test('search variants: tags first, then cleaned-up titles', () {
    expect(LrcLib.searchVariants('Never Enough WMA', 'Loren Allred'), [
      (title: 'Never Enough WMA', artist: 'Loren Allred'),
      (title: 'Never Enough', artist: 'Loren Allred'),
    ]);
    // No artist in the file: it's in the title.
    expect(LrcLib.searchVariants('Joeboy - Show Me (Official Video)(256k)', null), [
      (title: 'Joeboy - Show Me (Official Video)(256k)', artist: null),
      (title: 'Joeboy - Show Me', artist: null),
      (title: 'Show Me', artist: 'Joeboy'),
    ]);
    // A clean title gives one variant; real brackets stay.
    expect(LrcLib.searchVariants('Bohemian Rhapsody', 'Queen'), [(title: 'Bohemian Rhapsody', artist: 'Queen')]);
    expect(LrcLib.searchVariants('Shallow (feat. Bradley Cooper)', 'Lady Gaga').first.title, 'Shallow (feat. Bradley Cooper)');
    expect(LrcLib.searchVariants('Song [Lyric Video] [HD]', 'X').last.title, 'Song');
    // A dash with a known, different artist is part of the title.
    expect(LrcLib.searchVariants('Love - Live', 'Band').map((v) => v.title), ['Love - Live']);
  });

  test('pickBest: another length gives the words without timing', () {
    final results = [
      {'duration': 208.0, 'syncedLyrics': "[00:01.00] I'm trying to hold my breath", 'plainLyrics': null},
    ];
    // A 3:45 video against a 3:28 track: plain words, no stamps.
    expect(LrcLib.pickBest(results, const Duration(seconds: 225)), "I'm trying to hold my breath");
    expect(LrcLib.pickBest(results, const Duration(minutes: 6)), isNull);
  });

  test('free-text results: only the same artist, then by length', () {
    final results = [
      {'artistName': 'Loren Allred', 'trackName': 'Never Enough', 'duration': 208.0, 'syncedLyrics': '[00:01.00] full'},
      {'artistName': 'loren allred', 'trackName': 'Never Enough (Reprise)', 'duration': 80.0, 'syncedLyrics': '[00:01.00] reprise'},
      {'artistName': 'Someone Else', 'trackName': 'Never Enough', 'duration': 80.0, 'syncedLyrics': '[00:01.00] wrong'},
    ];
    final mine = LrcLib.sameArtist(results, 'Loren Allred');
    expect(mine, hasLength(2));
    expect(LrcLib.pickBest(mine, const Duration(seconds: 80)), '[00:01.00] reprise');
  });

  test('pickBest: unknown song length accepts any result', () {
    expect(LrcLib.pickBest([{'duration': 999, 'plainLyrics': 'x'}], Duration.zero), 'x');
  });
}
