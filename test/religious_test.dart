import 'package:audifac/models/religious.dart';
import 'package:audifac/models/song.dart';
import 'package:flutter_test/flutter_test.dart';

Song _song(int id, String title, {String artist = 'Someone', String album = 'Album', int albumId = 0}) => Song(
      id: id,
      uri: 'content://media/external/audio/media/$id',
      path: '/storage/emulated/0/Music/$id.mp3',
      title: title,
      artist: artist,
      artistId: artist.hashCode,
      album: album,
      albumId: albumId == 0 ? id : albumId,
      duration: const Duration(minutes: 4),
      dateAdded: DateTime(2024),
    );

void main() {
  test('fold drops case, accents and punctuation', () {
    expect(fold('Gloire à Dieu !'), 'gloire a dieu');
    expect(fold('Jésus-Christ'), 'jesus christ');
    expect(fold('  ÉGLISE  '), 'eglise');
  });

  test('genre tags', () {
    expect(religiousMatchOf(_song(1, 'Song'), genre: 'Gospel')?.reason, ReligiousReason.genre);
    expect(religiousMatchOf(_song(1, 'Song'), genre: 'Musique Chrétienne')?.reason, ReligiousReason.genre);
    expect(religiousMatchOf(_song(1, 'Song'), genre: 'Louange / Adoration')?.why, 'Louange / Adoration');
    expect(religiousMatchOf(_song(1, 'Song'), genre: 'Praise & Worship'), isNotNull);
    expect(religiousMatchOf(_song(1, 'Song'), genre: 'Afrobeats'), isNull);
    expect(religiousMatchOf(_song(1, 'Song'), genre: 'Coupé-décalé'), isNull);
  });

  test('words in title, album or artist', () {
    expect(religiousMatchOf(_song(1, 'Yesu Azali Awa'))?.why, 'yesu');
    expect(religiousMatchOf(_song(1, 'Merci Seigneur'))?.why, 'seigneur');
    expect(religiousMatchOf(_song(1, 'Nzambe Na Bomoyi')), isNotNull);
    expect(religiousMatchOf(_song(1, 'Alléluia'))?.why, 'alleluia');
    expect(religiousMatchOf(_song(1, 'Track 3', album: 'Psaumes de David')), isNotNull);
    expect(religiousMatchOf(_song(1, 'Track 3', artist: 'Chorale Saint Joseph')), isNotNull);
    expect(religiousMatchOf(_song(1, 'Gloire à Dieu'))?.why, 'gloire a dieu');
    expect(religiousMatchOf(_song(1, 'Viens Saint-Esprit'))?.why, 'saint esprit');
  });

  test('party songs that mention God stay in', () {
    for (final title in ['Oluwa Lo Ni', "God's Plan", 'Baba God', 'Dieu merci', 'Mon Dieu', 'Lord of the Dance', 'Christmas Party', 'Jesuslove']) {
      expect(religiousMatchOf(_song(1, title)), isNull, reason: title);
    }
    expect(religiousMatchOf(_song(1, 'Last Last', artist: 'Burna Boy')), isNull);
  });

  test("a gospel artist's or album's other songs come along", () {
    final songs = [
      _song(1, 'Yesu Azali Awa', artist: 'Mama Dena', album: 'Live', albumId: 50),
      _song(2, 'Nzambe Monene', artist: 'Mama Dena', album: 'Live', albumId: 50),
      _song(3, 'Mwana', artist: 'Mama Dena', album: 'Live', albumId: 50),
      // One match out of three: not the whole artist.
      _song(4, 'Amen', artist: 'Party Band', albumId: 60),
      _song(5, 'Dance', artist: 'Party Band', albumId: 60),
      _song(6, 'Floor', artist: 'Party Band', albumId: 60),
    ];
    final found = religiousSongs(songs);
    expect(found[songs[2].key]?.reason, ReligiousReason.artist);
    expect(found.containsKey(songs[3].key), isTrue);
    expect(found.containsKey(songs[4].key), isFalse);
    expect(found.containsKey(songs[5].key), isFalse);
  });

  test('marked songs count, and the filter survives a save', () {
    final song = _song(1, 'Some Song');
    expect(religiousSongs([song], marked: {song.key})[song.key]?.reason, ReligiousReason.marked);
    final f = ReligiousFilter.fromJson(const ReligiousFilter(on: true, keep: {'a'}, marked: {'b'}).toJson());
    expect(f.on, isTrue);
    expect(f.keep, {'a'});
    expect(f.marked, {'b'});
  });
}
