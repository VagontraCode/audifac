import 'package:audifac/models/app_settings.dart';
import 'package:audifac/models/song.dart';
import 'package:audifac/providers/library_providers.dart';
import 'package:flutter_test/flutter_test.dart';

Song _song({
  int id = 1,
  String? path = '/storage/emulated/0/Music/a.mp3',
  Duration duration = const Duration(minutes: 3),
  bool isMusic = true,
  bool isSystemSound = false,
  bool isRecording = false,
}) =>
    Song(
      id: id,
      uri: 'content://media/external/audio/media/$id',
      path: path,
      title: 't',
      artist: 'a',
      artistId: 1,
      album: 'b',
      albumId: 1,
      duration: duration,
      dateAdded: DateTime(2024),
      isMusic: isMusic,
      isSystemSound: isSystemSound,
      isRecording: isRecording,
    );

void main() {
  group('Song.fromFile', () {
    test('uses tags when present', () {
      final s = Song.fromFile(
        path: '/storage/emulated/0/WhatsApp/Media/Audio/song.opus',
        modifiedMs: 1700000000000,
        title: 'Real title',
        artist: 'Artist',
        album: 'Album',
        durationMs: 200000,
      );
      expect(s.isFile, isTrue);
      expect(s.id, isNegative);
      expect(s.uri, 'file:///storage/emulated/0/WhatsApp/Media/Audio/song.opus');
      expect(s.title, 'Real title');
      expect(s.folder, '/storage/emulated/0/WhatsApp/Media/Audio');
      expect(s.duration, const Duration(seconds: 200));
    });

    test('falls back to the file name and groups untagged files by folder', () {
      final a = Song.fromFile(path: '/sd/Mixes/My_Mix_01.mp3', modifiedMs: 0);
      final b = Song.fromFile(path: '/sd/Mixes/Other.mp3', modifiedMs: 0);
      final c = Song.fromFile(path: '/sd/Elsewhere/Other.mp3', modifiedMs: 0);
      expect(a.title, 'My Mix 01');
      expect(a.artist, Song.unknownArtist);
      expect(a.albumId, b.albumId);
      expect(a.albumId, isNot(c.albumId));
    });

    test('files from a picked folder open through their content URI', () {
      const doc = 'content://com.android.externalstorage.documents/tree/primary%3AVoice/document/primary%3AVoice%2Fa.opus';
      final s = Song.fromFile(path: '/storage/emulated/0/Voice/a.opus', location: doc, modifiedMs: 0);
      expect(s.uri, doc);
      expect(s.location, doc);
      expect(s.folder, '/storage/emulated/0/Voice');
      expect(s.id, Song.fromFile(path: '/storage/emulated/0/Voice/a.opus', modifiedMs: 0).id);
    });

    test('ids are stable across runs and distinct per path', () {
      final first = Song.fromFile(path: '/x/a.mp3', modifiedMs: 0).id;
      final again = Song.fromFile(path: '/x/a.mp3', modifiedMs: 5).id;
      final other = Song.fromFile(path: '/x/b.mp3', modifiedMs: 0).id;
      expect(first, again);
      expect(first, isNot(other));
      expect(Song.stableId('/x/a.mp3'), lessThan(1 << 52));
    });
  });

  test('file-name titles are tidied, real titles are kept', () {
    expect(Song.tidyTitle('Joeboy_-_Show_Me_(Official_Video)'), 'Joeboy - Show Me (Official Video)');
    expect(Song.tidyTitle('Rock_n Roll'), 'Rock_n Roll');
    expect(Song.tidyTitle('Lonely'), 'Lonely');
  });

  test('recordings are recognised by folder', () {
    expect(Song.looksLikeRecording('/storage/emulated/0/Recordings/r1.m4a'), isTrue);
    expect(
      Song.looksLikeRecording('/storage/emulated/0/Android/media/com.whatsapp/WhatsApp/Media/WhatsApp Voice Notes/202410/PTT.opus'),
      isTrue,
    );
    expect(Song.looksLikeRecording('/storage/emulated/0/Download/song.mp3'), isFalse);
  });

  group('isVisibleSong', () {
    const defaults = AppSettings();

    test('shows normal music anywhere on the device', () {
      expect(isVisibleSong(_song(path: '/storage/emulated/0/Download/x.mp3'), defaults), isTrue);
    });

    test('hides ringtones / notification sounds that are not music', () {
      expect(isVisibleSong(_song(isMusic: false, isSystemSound: true), defaults), isFalse);
      expect(isVisibleSong(_song(isMusic: true, isSystemSound: true), defaults), isTrue);
    });

    test('hides recordings unless enabled', () {
      final rec = _song(isRecording: true);
      expect(isVisibleSong(rec, defaults), isFalse);
      expect(isVisibleSong(rec, defaults.copyWith(includeRecordings: true)), isTrue);
    });

    test('applies the minimum length, but keeps unknown durations', () {
      final short = _song(duration: const Duration(seconds: 10));
      expect(isVisibleSong(short, defaults), isFalse);
      expect(isVisibleSong(short, defaults.copyWith(minDurationSeconds: 0)), isTrue);
      expect(isVisibleSong(_song(duration: Duration.zero), defaults), isTrue);
    });

    test('hides excluded folders and their subfolders only', () {
      final settings = defaults.copyWith(excludedFolders: {'/storage/emulated/0/Podcasts'});
      expect(isVisibleSong(_song(path: '/storage/emulated/0/Podcasts/ep.mp3'), settings), isFalse);
      expect(isVisibleSong(_song(path: '/storage/emulated/0/Podcasts/Show/ep.mp3'), settings), isFalse);
      expect(isVisibleSong(_song(path: '/storage/emulated/0/PodcastsOld/ep.mp3'), settings), isTrue);
    });
  });

  test('library settings round-trip through key/values', () {
    const settings = AppSettings(
      minDurationSeconds: 60,
      includeRecordings: true,
      excludedFolders: {'/a', '/b/c'},
    );
    final restored = AppSettings.fromKeyValues(settings.toKeyValues());
    expect(restored.minDurationSeconds, 60);
    expect(restored.includeRecordings, isTrue);
    expect(restored.excludedFolders, {'/a', '/b/c'});
    expect(AppSettings.fromKeyValues({'excludedFolders': 'garbage'}).excludedFolders, isEmpty);
  });
}
