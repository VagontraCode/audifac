import 'package:audifac/models/song.dart';
import 'package:audifac/models/spoken.dart';
import 'package:flutter_test/flutter_test.dart';

Song _song(String path, {int minutes = 4, bool podcast = false}) => Song(
      id: 1,
      uri: 'content://media/external/audio/media/1',
      path: path,
      title: 't',
      artist: 'a',
      artistId: 1,
      album: 'b',
      albumId: 1,
      duration: Duration(minutes: minutes),
      dateAdded: DateTime(2024),
      isPodcast: podcast,
    );

void main() {
  test('what counts as long-form', () {
    expect(isLongForm(_song('/storage/emulated/0/Music/song.mp3')), isFalse);
    expect(isLongForm(_song('/storage/emulated/0/Music/book.m4b')), isTrue);
    expect(isLongForm(_song('/storage/emulated/0/Audiobooks/Dune/01.mp3')), isTrue);
    expect(isLongForm(_song('/storage/emulated/0/Music/x.mp3', podcast: true)), isTrue);
    expect(isLongForm(_song('/storage/emulated/0/Music/mix.mp3', minutes: 45)), isTrue);
    expect(mayHaveChapters(_song('/x/book.m4b')), isTrue);
    expect(mayHaveChapters(_song('/x/song.flac')), isFalse);
  });

  test('resume point', () {
    const hour = Duration(hours: 1);
    expect(resumePoint(null, hour), isNull);
    expect(resumePoint(const Duration(seconds: 8), hour), isNull, reason: 'barely started');
    expect(resumePoint(const Duration(minutes: 59, seconds: 45), hour), isNull, reason: 'finished');
    expect(resumePoint(const Duration(minutes: 20), hour), const Duration(minutes: 19, seconds: 57));
  });

  test('current chapter', () {
    const chapters = [Chapter(Duration.zero, 'A'), Chapter(Duration(minutes: 5), 'B'), Chapter(Duration(minutes: 9), 'C')];
    expect(chapterAt(chapters, Duration.zero), 0);
    expect(chapterAt(chapters, const Duration(minutes: 6)), 1);
    expect(chapterAt(chapters, const Duration(hours: 1)), 2);
  });
}
