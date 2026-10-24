import 'dart:convert';

import 'loudness.dart';
import 'song.dart';

/// What to remember for an album or an artist: a playback speed (an
/// audiobook at 1.4×, a podcast at 1.25×) and a volume matching mode (a live
/// album always with album gain). Null fields follow the app's settings.
class PlaybackMemory {
  const PlaybackMemory({this.speed, this.volume});

  final double? speed;
  final VolumeMode? volume;

  bool get isEmpty => speed == null && volume == null;

  PlaybackMemory copyWith({double? Function()? speed, VolumeMode? Function()? volume}) => PlaybackMemory(
        speed: speed == null ? this.speed : speed(),
        volume: volume == null ? this.volume : volume(),
      );

  Map<String, Object?> toJson() => {'speed': ?speed, 'volume': ?volume?.name};

  factory PlaybackMemory.fromJson(Map<String, dynamic> j) => PlaybackMemory(
        speed: (j['speed'] as num?)?.toDouble().clamp(0.5, 3.0),
        volume: VolumeMode.values.asNameMap()[j['volume']],
      );

  @override
  bool operator ==(Object other) => other is PlaybackMemory && other.speed == speed && other.volume == volume;

  @override
  int get hashCode => Object.hash(speed, volume);
}

/// Every album's and artist's [PlaybackMemory]. An album's beats its artist's.
class PlaybackMemories {
  const PlaybackMemories({this.albums = const {}, this.artists = const {}});

  /// By album id.
  final Map<int, PlaybackMemory> albums;

  /// By artist name, lowercase.
  final Map<String, PlaybackMemory> artists;

  static String artistKey(String name) => name.trim().toLowerCase();

  PlaybackMemory album(int albumId) => albums[albumId] ?? const PlaybackMemory();

  PlaybackMemory artist(String name) => artists[artistKey(name)] ?? const PlaybackMemory();

  /// What applies to [song]: its album's, else its artist's, field by field.
  PlaybackMemory forSong(Song song) {
    final a = albums[song.albumId];
    final b = artists[artistKey(song.artist)];
    return PlaybackMemory(speed: a?.speed ?? b?.speed, volume: a?.volume ?? b?.volume);
  }

  PlaybackMemories withAlbum(int albumId, PlaybackMemory memory) =>
      PlaybackMemories(albums: _put(albums, albumId, memory), artists: artists);

  PlaybackMemories withArtist(String name, PlaybackMemory memory) =>
      PlaybackMemories(albums: albums, artists: _put(artists, artistKey(name), memory));

  static Map<K, PlaybackMemory> _put<K>(Map<K, PlaybackMemory> map, K key, PlaybackMemory memory) =>
      memory.isEmpty ? ({...map}..remove(key)) : {...map, key: memory};

  String encode() => jsonEncode({
        'albums': {for (final e in albums.entries) '${e.key}': e.value.toJson()},
        'artists': {for (final e in artists.entries) e.key: e.value.toJson()},
      });

  static PlaybackMemories decode(String? s) {
    if (s == null) return const PlaybackMemories();
    try {
      final j = jsonDecode(s) as Map<String, dynamic>;
      Map<String, dynamic> map(String k) => (j[k] as Map?)?.cast<String, dynamic>() ?? const {};
      return PlaybackMemories(
        albums: {
          for (final e in map('albums').entries)
            if (int.tryParse(e.key) case final id?) id: PlaybackMemory.fromJson((e.value as Map).cast<String, dynamic>()),
        },
        artists: {
          for (final e in map('artists').entries) e.key: PlaybackMemory.fromJson((e.value as Map).cast<String, dynamic>()),
        },
      );
    } catch (_) {
      return const PlaybackMemories();
    }
  }
}
