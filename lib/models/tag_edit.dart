import 'dart:convert';

import 'audio_info.dart';
import 'song.dart';

/// Tags the user corrected in the app, by file location. Stored in the app's
/// database only: the music file itself is never written. A null field keeps
/// the file's own tag.
class TagEdit {
  const TagEdit({this.title, this.artist, this.album, this.albumArtist, this.genre, this.year, this.track});

  final String? title;
  final String? artist;
  final String? album;
  final String? albumArtist;
  final String? genre;
  final String? year;

  /// Track number as MediaStore stores it (disc × 1000 + track).
  final int? track;

  /// What the user typed, against the file's own tags ([file], [fileInfo]):
  /// only fields that differ are kept; a blank field means the file's tag.
  /// [track] is the track within its disc (the disc is kept).
  factory TagEdit.diff({
    required Song file,
    required AudioInfo fileInfo,
    required String title,
    required String artist,
    required String album,
    required String albumArtist,
    required String genre,
    required String year,
    required String track,
  }) {
    String? changed(String typed, String? original) {
      final t = typed.trim();
      return t.isEmpty || t == (original ?? '').trim() ? null : t;
    }

    final disc = file.trackNumber ~/ 1000;
    final number = int.tryParse(track.trim());
    return TagEdit(
      title: changed(title, file.title),
      artist: changed(artist, file.artist),
      album: changed(album, file.album),
      albumArtist: changed(albumArtist, fileInfo.albumArtist),
      genre: changed(genre, fileInfo.genre),
      year: changed(year, fileInfo.year),
      track: number == null || number == file.trackNumber % 1000 ? null : disc * 1000 + number,
    );
  }

  bool get isEmpty =>
      title == null &&
      artist == null &&
      album == null &&
      albumArtist == null &&
      genre == null &&
      year == null &&
      track == null;

  /// [song] with these tags. A new album or album artist moves the song to
  /// another album (songs edited alike end up together); a new artist only
  /// changes the artist it's listed under.
  Song apply(Song song) {
    if (isEmpty) return song;
    final albumMoved = album != null || albumArtist != null;
    return Song(
      id: song.id,
      uri: song.uri,
      path: song.path,
      title: title ?? song.title,
      artist: artist ?? song.artist,
      artistId: artist == null ? song.artistId : -Song.stableId('artist:$artist'),
      album: album ?? song.album,
      albumId: albumMoved
          ? -Song.stableId('album:edit:${albumArtist ?? ''}/${album ?? song.album}')
          : song.albumId,
      duration: song.duration,
      trackNumber: track ?? song.trackNumber,
      dateAdded: song.dateAdded,
      mimeType: song.mimeType,
      sizeBytes: song.sizeBytes,
      modifiedMs: song.modifiedMs,
      isMusic: song.isMusic,
      isSystemSound: song.isSystemSound,
      isRecording: song.isRecording,
      isPodcast: song.isPodcast,
    );
  }

  /// [info] with the edited genre / year / album artist.
  AudioInfo applyInfo(AudioInfo info) => (genre == null && year == null && albumArtist == null)
      ? info
      : info.copyWith(genre: genre, year: year, albumArtist: albumArtist);

  Map<String, Object?> toJson() => {
        'title': ?title,
        'artist': ?artist,
        'album': ?album,
        'albumArtist': ?albumArtist,
        'genre': ?genre,
        'year': ?year,
        'track': ?track,
      };

  factory TagEdit.fromJson(Map<String, dynamic> j) => TagEdit(
        title: j['title'] as String?,
        artist: j['artist'] as String?,
        album: j['album'] as String?,
        albumArtist: j['albumArtist'] as String?,
        genre: j['genre'] as String?,
        year: j['year'] as String?,
        track: (j['track'] as num?)?.toInt(),
      );

  String encode() => jsonEncode(toJson());

  static TagEdit decode(String s) => TagEdit.fromJson(jsonDecode(s) as Map<String, dynamic>);

  @override
  bool operator ==(Object other) =>
      other is TagEdit &&
      other.title == title &&
      other.artist == artist &&
      other.album == album &&
      other.albumArtist == albumArtist &&
      other.genre == genre &&
      other.year == year &&
      other.track == track;

  @override
  int get hashCode => Object.hash(title, artist, album, albumArtist, genre, year, track);
}
