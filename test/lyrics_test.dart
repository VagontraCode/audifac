import 'package:audifac/models/lyrics.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('LRC: stamps, repeats, metadata tags, ordering', () {
    final l = Lyrics.parse('''
[ar:Someone]
[ti:Song]
[00:12.50]First line
[00:05.1]Intro
[00:20.00][01:02.003]Chorus
[00:30]
''', LyricsSource.tags);
    expect(l.synced, isTrue);
    expect([for (final x in l.lines) x.text], ['Intro', 'First line', 'Chorus', '', 'Chorus']);
    expect(l.lines[0].time, const Duration(seconds: 5, milliseconds: 100));
    expect(l.lines[1].time, const Duration(seconds: 12, milliseconds: 500));
    expect(l.lines[4].time, const Duration(minutes: 1, seconds: 2, milliseconds: 3));
  });

  test('LRC offset shifts lyrics earlier', () {
    final l = Lyrics.parse('[offset:+500]\n[00:10.00]Hi', LyricsSource.file);
    expect(l.lines.single.time, const Duration(milliseconds: 9500));
  });

  test('current line lookup', () {
    final l = Lyrics.parse('[00:01]a\n[00:05]b\n[00:09]c', LyricsSource.tags);
    expect(l.indexAt(Duration.zero), -1);
    expect(l.indexAt(const Duration(seconds: 5)), 1);
    expect(l.indexAt(const Duration(seconds: 7)), 1);
    expect(l.indexAt(const Duration(minutes: 3)), 2);
  });

  test('plain lyrics stay unsynced, blank edges trimmed', () {
    final l = Lyrics.parse('\n\nVerse one\r\n\r\nVerse two\n\n', LyricsSource.tags);
    expect(l.synced, isFalse);
    expect([for (final x in l.lines) x.text], ['Verse one', '', 'Verse two']);
    expect(l.indexAt(const Duration(seconds: 3)), -1);
  });
}
