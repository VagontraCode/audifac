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
    expect(LrcLib.pickBest(results, const Duration(seconds: 300)), isNull);
  });

  test('pickBest: unknown song length accepts any result', () {
    expect(LrcLib.pickBest([{'duration': 999, 'plainLyrics': 'x'}], Duration.zero), 'x');
  });
}
