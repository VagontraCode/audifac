import 'package:audifac/core/format.dart';
import 'package:audifac/models/song.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Song.fromMap', () {
    test('parses MediaStore fields', () {
      final song = Song.fromMap({
        'id': 42,
        'uri': 'content://media/external/audio/media/42',
        'title': 'Unsayable',
        'artist': 'Brambles',
        'artistId': 7,
        'album': 'Charcoal',
        'albumId': 3,
        'durationMs': 261000,
        'track': 1001,
        'dateAdded': 1700000000,
        'mimeType': 'audio/flac',
      });

      expect(song.id, 42);
      expect(song.title, 'Unsayable');
      expect(song.duration, const Duration(minutes: 4, seconds: 21));
      expect(song.trackNumber % 1000, 1);
      expect(song.dateAdded, DateTime.fromMillisecondsSinceEpoch(1700000000 * 1000));
    });

    test('replaces missing and <unknown> tags with fallbacks', () {
      final song = Song.fromMap({
        'id': 1,
        'uri': 'content://x/1',
        'title': '  ',
        'artist': '<unknown>',
        'album': null,
      });

      expect(song.title, 'Untitled');
      expect(song.artist, Song.unknownArtist);
      expect(song.album, Song.unknownAlbum);
      expect(song.duration, Duration.zero);
    });
  });

  group('formatDuration', () {
    test('formats minutes and seconds', () {
      expect(formatDuration(const Duration(seconds: 5)), '0:05');
      expect(formatDuration(const Duration(minutes: 4, seconds: 21)), '4:21');
    });

    test('formats hours', () {
      expect(formatDuration(const Duration(hours: 1, minutes: 2, seconds: 3)), '1:02:03');
    });
  });

  test('formatTotalDuration', () {
    expect(formatTotalDuration(const Duration(minutes: 42)), '42 min');
    expect(formatTotalDuration(const Duration(hours: 1, minutes: 12)), '1 h 12 min');
  });

  test('pluralize', () {
    expect(pluralize(1, 'song'), '1 song');
    expect(pluralize(3, 'song'), '3 songs');
  });
}
