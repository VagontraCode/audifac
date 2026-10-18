import 'package:audifac/models/audio_info.dart';
import 'package:audifac/models/play_stats.dart';
import 'package:audifac/models/smart_playlist.dart';
import 'package:audifac/models/song.dart';
import 'package:flutter_test/flutter_test.dart';

final _now = DateTime(2026, 10, 18);

Song _song(int id, {String artist = 'A', String folder = 'Music', int addedDaysAgo = 100, int minutes = 4}) => Song(
      id: id,
      uri: 'content://media/external/audio/media/$id',
      path: '/storage/emulated/0/$folder/$id.flac',
      title: 'Song $id',
      artist: artist,
      artistId: 1,
      album: 'Album',
      albumId: 1,
      duration: Duration(minutes: minutes),
      dateAdded: _now.subtract(Duration(days: addedDaysAgo)),
    );

void main() {
  final songs = [
    _song(1, artist: 'Miles Davis'),
    _song(2, artist: 'Burna Boy', folder: 'Download', addedDaysAgo: 2),
    _song(3, artist: 'Miles Davis', minutes: 12),
    _song(4, artist: 'Asake', addedDaysAgo: 5),
  ];
  final infos = {
    1: const AudioInfo(codec: 'FLAC', sampleRate: 96000, bitDepth: 24, genre: 'Jazz', year: '1959'),
    2: const AudioInfo(codec: 'MP3', bitrate: 320000, genre: 'Afrobeats', year: '2022'),
    3: const AudioInfo(codec: 'FLAC', sampleRate: 44100, bitDepth: 16, genre: 'Jazz', year: '1970'),
    4: const AudioInfo(codec: 'AAC', genre: 'Afrobeats', year: '2023'),
  };
  final ctx = SmartContext(
    info: (s) => infos[s.id]!,
    stats: {
      1: SongStats(plays: 9, lastPlayed: _now.subtract(const Duration(days: 60))),
      2: SongStats(plays: 3, lastPlayed: _now.subtract(const Duration(days: 1))),
      4: const SongStats(plays: 0, listened: Duration(seconds: 30)),
    },
    favorites: {3},
    now: _now,
  );
  List<int> ids(SmartPlaylist l) => [for (final s in l.songsFrom(songs, ctx)) s.id];
  SmartPlaylist builtIn(String id) => SmartPlaylist.builtIns.firstWhere((l) => l.id == id);

  test('built-ins', () {
    expect(ids(builtIn('b_lossless')), unorderedEquals([1, 3]), reason: 'lossless includes Hi-Res');
    expect(ids(builtIn('b_hires')), [1]);
    expect(ids(builtIn('b_most')), [1, 2]);
    expect(ids(builtIn('b_forgotten')), [1]);
    expect(ids(builtIn('b_new')), [2, 4]);
    expect(ids(builtIn('b_never')), unorderedEquals([3, 4]), reason: 'a 30 s listen is not a play');
  });

  test('text, number and flag rules; all vs any', () {
    const jazzLong = SmartPlaylist(id: 'x', name: 'x', rules: [
      SmartRule(SmartField.genre, SmartOp.equals, 'jazz'),
      SmartRule(SmartField.duration, SmartOp.atLeast, '10'),
    ]);
    expect(ids(jazzLong), [3]);
    expect(ids(jazzLong.copyWith(matchAll: false)).toSet(), {1, 3});
    expect(ids(const SmartPlaylist(id: 'x', name: 'x', rules: [SmartRule(SmartField.artist, SmartOp.notContains, 'miles')]))
        .toSet(), {2, 4});
    expect(ids(const SmartPlaylist(id: 'x', name: 'x', rules: [SmartRule(SmartField.favorite, SmartOp.yes)])), [3]);
    expect(ids(const SmartPlaylist(id: 'x', name: 'x', rules: [SmartRule(SmartField.year, SmartOp.atMost, '1969')])), [1]);
    expect(ids(const SmartPlaylist(id: 'x', name: 'x', rules: [SmartRule(SmartField.source, SmartOp.equals, 'downloads')])),
        [2]);
    expect(ids(const SmartPlaylist(id: 'x', name: 'x', rules: [SmartRule(SmartField.codec, SmartOp.notEquals, 'FLAC')]))
        .toSet(), {2, 4});
  });

  test('sort and limit', () {
    const l = SmartPlaylist(id: 'x', name: 'x', sort: SmartSort.title, limit: 2);
    expect(ids(l), [1, 2]);
    expect(ids(l.copyWith(sort: SmartSort.recentlyAdded, limit: () => null)), [2, 4, 1, 3]);
    final random = ids(l.copyWith(sort: SmartSort.random, limit: () => null));
    expect(random.toSet(), {1, 2, 3, 4});
    expect(ids(l.copyWith(sort: SmartSort.random, limit: () => null)), random, reason: 'stable within a day');
  });

  test('JSON round-trip drops unknown rules', () {
    const l = SmartPlaylist(
      id: 's_1',
      name: 'Mine',
      rules: [SmartRule(SmartField.plays, SmartOp.atLeast, '5')],
      matchAll: false,
      sort: SmartSort.artist,
      limit: 25,
    );
    final back = SmartPlaylist.decodeAll(SmartPlaylist.encodeAll([l])).single;
    expect(back.name, 'Mine');
    expect(back.rules.single.describe(), 'Play count at least 5');
    expect(back.matchAll, isFalse);
    expect(back.limit, 25);
    final junk = SmartPlaylist.decodeAll('[{"id":"a","name":"b","rules":[{"field":"mood","op":"is"}]}]').single;
    expect(junk.rules, isEmpty);
    expect(SmartPlaylist.decodeAll('nope'), isEmpty);
  });
}
