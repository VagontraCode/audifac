import 'dart:async';
import 'dart:math';

import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';
import 'package:just_audio/just_audio.dart';

import '../../models/song.dart';
import 'browse_tree.dart';
import 'queue_logic.dart';

/// Starts the background audio service. Call once, before `runApp`.
Future<AudifacAudioHandler> initAudioHandler() {
  return AudioService.init(
    builder: AudifacAudioHandler.new,
    config: const AudioServiceConfig(
      androidNotificationChannelId: 'com.gtongfa.audifac.playback',
      androidNotificationChannelName: 'Playback',
      androidNotificationOngoing: true,
      androidStopForegroundOnPause: true,
      artDownscaleWidth: 512,
      artDownscaleHeight: 512,
    ),
  );
}

/// The single source of truth for playback.
///
/// The UI, the media notification, the lock screen and headset/Bluetooth
/// buttons all go through this handler. It wraps `just_audio` so the engine
/// can be swapped without touching the UI.
class AudifacAudioHandler extends BaseAudioHandler with QueueHandler, SeekHandler {
  AudifacAudioHandler() {
    _init();
  }

  final _player = AudioPlayer();
  final _subscriptions = <StreamSubscription<dynamic>>[];
  final _errors = StreamController<String>.broadcast();
  var _shuffleOrder = QueueShuffleOrder();

  Stream<Duration> get positionStream => _player.positionStream;
  Duration get position => _player.position;

  /// Current item's length, when known.
  Duration? get duration => _player.duration;

  /// Index of the current item in the source order.
  int? get currentIndex => _player.currentIndex;

  /// Playback speed (pitch kept).
  @override
  Future<void> setSpeed(double speed) => _player.setSpeed(speed.clamp(0.5, 3.0).toDouble());

  double get speed => _player.speed;

  /// Player volume (0–1), used for fades; the DSP gain is separate.
  Future<void> setVolume(double volume) => _player.setVolume(volume.clamp(0, 1).toDouble());

  /// Human-readable messages about tracks that could not be played.
  Stream<String> get errors => _errors.stream;

  /// Sequence indices in the order they will play.
  List<int> get playOrder => _player.shuffleModeEnabled
      ? List.of(_player.shuffleIndices)
      : List.generate(queue.value.length, (i) => i);

  Future<void> _init() async {
    final session = await AudioSession.instance;
    // Music profile: pauses on calls, ducks for notifications, and just_audio
    // pauses automatically when headphones are unplugged.
    await session.configure(const AudioSessionConfiguration.music());

    _subscriptions.addAll([
      _player.playbackEventStream.listen((_) => _broadcastState(), onError: (_) {}),
      _player.playingStream.listen((_) => _broadcastState()),
      _player.shuffleModeEnabledStream.listen((_) => _broadcastState()),
      _player.shuffleIndicesStream.listen((_) => _broadcastState()),
      _player.loopModeStream.listen((_) => _broadcastState()),
      _player.speedStream.listen((_) => _broadcastState()),
      _player.currentIndexStream.listen(_onCurrentIndexChanged),
      _player.processingStateStream.listen(_onProcessingState),
      _player.playingStream.listen((playing) {
        if (playing) _idleStop?.cancel();
      }),
      _player.durationStream.listen(_onDurationChanged),
      _player.errorStream.listen(_onError),
    ]);
  }

  // ---------------------------------------------------------------------------
  // Public API used by the UI

  /// Replaces the queue with [songs] and starts playing.
  Future<void> playSongs(
    List<Song> songs, {
    int startIndex = 0,
    bool shuffle = false,
    bool albumShuffle = false,
  }) async {
    if (songs.isEmpty) return;
    var start = shuffle ? Random().nextInt(songs.length) : startIndex;
    if (shuffle && (albumShuffle || _keepAlbumsTogether)) {
      // Albums start from their first track.
      start = songs.indexWhere((s) => s.albumId == songs[start].albumId);
    }
    await _load(songs, index: start, shuffle: shuffle, albumShuffle: albumShuffle);
    _queueStarts.add(songs[_player.currentIndex ?? start]);
    unawaited(_player.play());
  }

  final _queueStarts = StreamController<Song>.broadcast();

  /// The first song each time the user starts a new queue (not restores,
  /// not "play next"). Used to offer an EQ preset choice.
  Stream<Song> get queueStarts => _queueStarts.stream;

  /// Loads a previously saved queue without starting playback.
  Future<void> restoreSession(
    List<Song> songs, {
    required int index,
    required Duration position,
    required bool shuffle,
    required AudioServiceRepeatMode repeat,
  }) async {
    if (songs.isEmpty) return;
    await _load(songs, index: index, position: position, shuffle: shuffle);
    await setRepeatMode(repeat);
  }

  /// Inserts [songs] right after the current track.
  Future<void> playNext(List<Song> songs) => _insert(songs, InsertPlacement.afterCurrent);

  /// Appends [songs] to the end of the queue.
  Future<void> addToQueue(List<Song> songs) => _insert(songs, InsertPlacement.end);

  Future<void> removeFromQueue(int index) async {
    final items = queue.value;
    if (index < 0 || index >= items.length || index == _player.currentIndex) return;
    await _player.removeAudioSourceAt(index);
    queue.add([...items]..removeAt(index));
  }

  /// Moves a queue item; [to] is the index after removal (as given by
  /// `ReorderableListView.onReorderItem`).
  Future<void> moveInQueue(int from, int to) async {
    final items = queue.value;
    if (from == to || from < 0 || from >= items.length) return;
    final target = to.clamp(0, items.length - 1);
    await _player.moveAudioSource(from, target);
    queue.add(moveItem(items, from, target));
  }

  Future<void> togglePlayPause() => _player.playing ? pause() : play();

  Future<void> toggleShuffle() => setShuffleMode(
        _player.shuffleModeEnabled ? AudioServiceShuffleMode.none : AudioServiceShuffleMode.all,
      );

  Future<void> cycleRepeat() =>
      setRepeatMode(nextRepeatMode(playbackState.value.repeatMode));

  // ---------------------------------------------------------------------------
  // BaseAudioHandler overrides (also triggered by notification & headset)

  @override
  Future<void> play() => _player.play();

  @override
  Future<void> pause() => _player.pause();

  @override
  Future<void> stop() async {
    await _player.stop();
    await super.stop();
  }

  @override
  Future<void> seek(Duration position) => _player.seek(position);

  @override
  Future<void> skipToNext() => _player.seekToNext();

  /// Restarts the current track if more than 3 s in, like most players.
  @override
  Future<void> skipToPrevious() async {
    if (_player.position > const Duration(seconds: 3) || !_player.hasPrevious) {
      await _player.seek(Duration.zero);
    } else {
      await _player.seekToPrevious();
    }
  }

  /// Goes to [index] / [position] without starting playback (casting keeps
  /// the local queue in step with the TV this way).
  Future<void> moveTo(int index, [Duration position = Duration.zero]) async {
    if (index < 0 || index >= queue.value.length) return;
    await _player.seek(position, index: index);
  }

  @override
  Future<void> skipToQueueItem(int index) async {
    if (index < 0 || index >= queue.value.length) return;
    await _player.seek(Duration.zero, index: index);
    if (!_player.playing) unawaited(_player.play());
  }

  @override
  Future<void> setShuffleMode(AudioServiceShuffleMode shuffleMode) async {
    final enabled = shuffleMode != AudioServiceShuffleMode.none;
    if (enabled) await _player.shuffle();
    await _player.setShuffleModeEnabled(enabled);
  }

  @override
  Future<void> setRepeatMode(AudioServiceRepeatMode repeatMode) {
    return _player.setLoopMode(switch (repeatMode) {
      AudioServiceRepeatMode.none => LoopMode.off,
      AudioServiceRepeatMode.one => LoopMode.one,
      AudioServiceRepeatMode.all || AudioServiceRepeatMode.group => LoopMode.all,
    });
  }

  @override
  Future<void> onTaskRemoved() async {
    if (!_player.playing) await stop();
  }

  /// Stops and forgets the queue: the mini player and the notification go
  /// away (swipe the mini player down).
  Future<void> dismiss() async {
    _idleStop?.cancel();
    await stop();
    queue.add(const []);
    mediaItem.add(null);
  }

  /// Fires when the last song of the queue has finished (not with repeat on:
  /// then the queue never ends).
  Stream<void> get queueEnded => _queueEnded.stream;
  final _queueEnded = StreamController<void>.broadcast();

  /// How long the notification stays after the queue ended, if nothing plays.
  static const idleStopAfter = Duration(minutes: 10);
  Timer? _idleStop;

  void _onProcessingState(ProcessingState state) {
    if (state != ProcessingState.completed) return;
    // Back to the start of the last song, paused: one tap replays it.
    unawaited(() async {
      await _player.pause();
      await _player.seek(Duration.zero);
    }());
    _queueEnded.add(null);
    _idleStop?.cancel();
    _idleStop = Timer(idleStopAfter, () {
      if (!_player.playing) unawaited(stop());
    });
  }

  // ---------------------------------------------------------------------------
  // Internals

  Future<void> _load(
    List<Song> songs, {
    required int index,
    Duration position = Duration.zero,
    bool shuffle = false,
    bool albumShuffle = false,
  }) async {
    final items = songs.map(_toMediaItem).toList();
    queue.add(items);
    _shuffleOrder = QueueShuffleOrder();
    _applyAlbumShuffle(force: albumShuffle);

    await _player.setShuffleModeEnabled(false);
    await _player.setAudioSources(
      [for (final item in items) AudioSource.uri(Uri.parse(item.id), tag: item)],
      initialIndex: index.clamp(0, items.length - 1),
      initialPosition: position,
      shuffleOrder: _shuffleOrder,
    );
    if (shuffle) {
      await _player.shuffle();
      await _player.setShuffleModeEnabled(true);
    }
  }

  // ---------------------------------------------------------------------------
  // Media browsing (Android Auto, Assistant, other media apps)

  /// Set by the app whenever the library changes.
  BrowseTree? browseTree;

  @override
  Future<List<MediaItem>> getChildren(String parentMediaId, [Map<String, dynamic>? options]) async =>
      browseTree?.children(parentMediaId) ?? const [];

  @override
  Future<MediaItem?> getMediaItem(String mediaId) async {
    final hit = browseTree?.playable(mediaId);
    return hit == null ? null : _toMediaItem(hit.songs[hit.index]);
  }

  @override
  Future<void> playFromMediaId(String mediaId, [Map<String, dynamic>? extras]) async {
    final hit = browseTree?.playable(mediaId);
    if (hit == null) return;
    await playSongs(hit.songs, startIndex: hit.index, shuffle: hit.shuffle);
  }

  @override
  Future<void> playFromSearch(String query, [Map<String, dynamic>? extras]) async {
    final tree = browseTree;
    if (tree == null) return;
    // "Play music" with nothing specific: shuffle everything.
    final hits = query.trim().isEmpty ? tree.all : tree.search(query);
    if (hits.isEmpty) return;
    await playSongs(hits, shuffle: query.trim().isEmpty);
  }

  @override
  Future<List<MediaItem>> search(String query, [Map<String, dynamic>? extras]) async => [
        for (final s in browseTree?.search(query).take(BrowseTree.maxItems) ?? const <Song>[])
          MediaItem(id: '${BrowseTree.shuffleId}|song:${s.id}', title: s.title, artist: s.artist, album: s.album, playable: true),
      ];

  /// Shuffle keeps each album's tracks together and in order.
  bool get keepAlbumsTogether => _keepAlbumsTogether;
  bool _keepAlbumsTogether = false;
  set keepAlbumsTogether(bool value) {
    _keepAlbumsTogether = value;
    _applyAlbumShuffle();
  }

  void _applyAlbumShuffle({bool force = false}) {
    Object? albumOf(int i) {
      final items = queue.value;
      if (i >= items.length) return null;
      return items[i].extras?['albumId'];
    }

    _shuffleOrder.albumOf = (force || _keepAlbumsTogether) ? albumOf : null;
  }

  Future<void> _insert(List<Song> songs, InsertPlacement placement) async {
    if (songs.isEmpty) return;
    final items = queue.value;
    final current = _player.currentIndex;
    if (items.isEmpty || current == null) return playSongs(songs);

    final newItems = songs.map(_toMediaItem).toList();
    final at = placement == InsertPlacement.afterCurrent ? current + 1 : items.length;
    _shuffleOrder
      ..placement = placement
      ..currentIndex = current;
    await _player.insertAudioSources(
      at,
      [for (final item in newItems) AudioSource.uri(Uri.parse(item.id), tag: item)],
    );
    queue.add([...items]..insertAll(at, newItems));
  }

  MediaItem _toMediaItem(Song song) => MediaItem(
        id: song.uri,
        title: song.title,
        artist: song.artist,
        album: song.album,
        duration: song.duration == Duration.zero ? null : song.duration,
        // The notification loads embedded artwork straight from an indexed
        // song's content:// URI via ContentResolver.loadThumbnail. Files
        // outside MediaStore have no such URI, so they get no notification art.
        artUri: song.isFile ? null : Uri.parse(song.uri),
        extras: {
          'songId': song.id,
          'albumId': song.albumId,
          if (!song.isFile) 'loadThumbnailUri': true,
        },
      );

  void _onCurrentIndexChanged(int? index) {
    final items = queue.value;
    if (index == null || index >= items.length) return;
    final item = items[index];
    final cached = _artFiles[item.extras?['songId']];
    // Prefetched artwork: the song's details go out once, complete.
    mediaItem.add(cached == null ? item : _withArt(item, cached));
    _songStartedAt = DateTime.now();
    if (cached == null) unawaited(_attachArtworkFile(item));
    unawaited(_prefetchNextArtwork(index));
  }

  /// Artwork files resolved so far, by song id.
  final _artFiles = <int, Uri>{};
  DateTime _songStartedAt = DateTime.now();

  /// Media session updates reach Bluetooth headphones (AVRCP metadata and
  /// cover art) over the same link as the audio, and on many of them a
  /// mid-song update is heard as a short dropout: late artwork is kept for
  /// next time instead of being sent after this.
  static const _lateArtwork = Duration(seconds: 2);

  MediaItem _withArt(MediaItem item, Uri art) => item.copyWith(
        artUri: art,
        extras: {...?item.extras}..remove('loadThumbnailUri'),
      );

  /// Supplies a `file://` artwork image for the notification. Set by the app;
  /// covers songs whose artwork Android won't thumbnail (e.g. in Download) and
  /// files outside MediaStore.
  Future<Uri?> Function(int songId, int albumId)? artworkFileResolver;

  /// Resolves (and caches) a `file://` artwork image for [item].
  Future<Uri?> _resolveArtwork(MediaItem item) async {
    final resolver = artworkFileResolver;
    final songId = item.extras?['songId'] as int?;
    final albumId = item.extras?['albumId'] as int?;
    if (resolver == null || songId == null || albumId == null) return null;
    if (item.artUri?.scheme == 'file') return item.artUri;
    if (_artFiles[songId] case final cached?) return cached;
    final art = await resolver(songId, albumId);
    if (art != null) _artFiles[songId] = art;
    return art;
  }

  /// The current song's artwork, if it arrives early enough (see [_lateArtwork]).
  Future<void> _attachArtworkFile(MediaItem item) async {
    final art = await _resolveArtwork(item);
    if (art == null || mediaItem.value?.id != item.id) return;
    if (DateTime.now().difference(_songStartedAt) > _lateArtwork) return;
    mediaItem.add(_withArt(mediaItem.value!, art));
  }

  /// Gets the next song's artwork ready while this one plays.
  Future<void> _prefetchNextArtwork(int index) async {
    final order = playOrder;
    final pos = order.indexOf(index);
    if (pos < 0 || pos + 1 >= order.length) return;
    final next = order[pos + 1];
    final items = queue.value;
    if (next < items.length) await _resolveArtwork(items[next]);
  }

  /// MediaStore durations are sometimes missing/wrong; trust the decoder.
  void _onDurationChanged(Duration? duration) {
    final index = _player.currentIndex;
    final items = queue.value;
    if (duration == null || index == null || index >= items.length) return;
    if (items[index].duration == duration) return;

    final updated = items[index].copyWith(duration: duration);
    queue.add([...items]..[index] = updated);
    mediaItem.add(updated);
  }

  /// Unplayable/corrupt file: report it and skip instead of getting stuck.
  void _onError(PlayerException error) {
    final title = mediaItem.value?.title;
    // The title (empty when unknown); the UI words the message.
    _errors.add(title ?? '');
    if (_player.hasNext) {
      unawaited(_player.seekToNext().then((_) => _player.play()));
    } else {
      unawaited(_player.pause());
    }
  }

  void _broadcastState() {
    final playing = _player.playing;
    playbackState.add(
      playbackState.value.copyWith(
        controls: [
          MediaControl.skipToPrevious,
          if (playing) MediaControl.pause else MediaControl.play,
          MediaControl.skipToNext,
        ],
        systemActions: const {
          MediaAction.seek,
          MediaAction.seekForward,
          MediaAction.seekBackward,
          MediaAction.skipToQueueItem,
          MediaAction.setShuffleMode,
          MediaAction.setRepeatMode,
        },
        androidCompactActionIndices: const [0, 1, 2],
        processingState: switch (_player.processingState) {
          ProcessingState.idle => AudioProcessingState.idle,
          ProcessingState.loading => AudioProcessingState.loading,
          ProcessingState.buffering => AudioProcessingState.buffering,
          ProcessingState.ready => AudioProcessingState.ready,
          ProcessingState.completed => AudioProcessingState.completed,
        },
        playing: playing,
        updatePosition: _player.position,
        bufferedPosition: _player.bufferedPosition,
        speed: _player.speed,
        queueIndex: _player.currentIndex,
        shuffleMode: _player.shuffleModeEnabled
            ? AudioServiceShuffleMode.all
            : AudioServiceShuffleMode.none,
        repeatMode: switch (_player.loopMode) {
          LoopMode.off => AudioServiceRepeatMode.none,
          LoopMode.one => AudioServiceRepeatMode.one,
          LoopMode.all => AudioServiceRepeatMode.all,
        },
      ),
    );
  }

  Future<void> dispose() async {
    for (final s in _subscriptions) {
      await s.cancel();
    }
    await _errors.close();
    _idleStop?.cancel();
    await _queueEnded.close();
    await _player.dispose();
  }
}
