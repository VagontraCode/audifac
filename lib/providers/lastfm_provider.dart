import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/lastfm.dart';
import '../models/play_stats.dart';
import '../models/song.dart';
import 'library_providers.dart';
import 'player_providers.dart';
import 'stats_providers.dart';
import 'user_data_providers.dart';

class LastFmState {
  const LastFmState({this.account, this.enabled = true, this.pending = 0, this.error, this.busy = false});

  final LastFmAccount? account;
  final bool enabled;

  /// Scrobbles waiting to be sent (offline, or Last.fm unreachable).
  final int pending;
  final String? error;
  final bool busy;

  bool get active => enabled && (account?.connected ?? false);

  LastFmState copyWith({LastFmAccount? Function()? account, bool? enabled, int? pending, String? Function()? error, bool? busy}) =>
      LastFmState(
        account: account == null ? this.account : account(),
        enabled: enabled ?? this.enabled,
        pending: pending ?? this.pending,
        error: error == null ? this.error : error(),
        busy: busy ?? this.busy,
      );
}

final lastFmProvider = NotifierProvider<LastFmNotifier, LastFmState>(LastFmNotifier.new);

class LastFmNotifier extends Notifier<LastFmState> {
  static const accountKey = 'lastfm';
  static const queueKey = 'lastfm_queue';
  static const enabledKey = 'lastfm_enabled';

  /// Last.fm refuses scrobbles older than two weeks.
  static const maxAge = Duration(days: 14);

  /// For tests: replaces the network.
  LastFmTransport? transport;

  final _queue = <Scrobble>[];
  bool _flushing = false;

  @override
  LastFmState build() {
    final values = ref.read(bootstrapProvider).values;
    LastFmAccount? account;
    try {
      account = LastFmAccount.fromJson(jsonDecode(values[accountKey] ?? 'null') as Map<String, dynamic>?);
    } catch (_) {}
    try {
      for (final j in (jsonDecode(values[queueKey] ?? '[]') as List).cast<Map<String, dynamic>>()) {
        if (Scrobble.fromJson(j) case final s?) _queue.add(s);
      }
    } catch (_) {}
    return LastFmState(account: account, enabled: values[enabledKey] != 'false', pending: _queue.length);
  }

  LastFmClient? _client() {
    final a = state.account;
    return a == null ? null : LastFmClient(apiKey: a.apiKey, secret: a.secret, transport: transport);
  }

  Future<void> _saveQueue() async {
    state = state.copyWith(pending: _queue.length);
    await ref.read(databaseProvider).setValue(queueKey, jsonEncode([for (final s in _queue) s.toJson()]));
  }

  /// Logs in with the user's own API key; the password is used once.
  Future<void> connect({required String apiKey, required String secret, required String username, required String password}) async {
    state = state.copyWith(busy: true, error: () => null);
    try {
      final client = LastFmClient(apiKey: apiKey.trim(), secret: secret.trim(), transport: transport);
      final session = await client.login(username.trim(), password);
      final account = LastFmAccount(apiKey: apiKey.trim(), secret: secret.trim(), username: username.trim(), sessionKey: session);
      await ref.read(databaseProvider).setValue(accountKey, jsonEncode(account.toJson()));
      state = state.copyWith(account: () => account, busy: false);
      unawaited(flush());
    } catch (e) {
      state = state.copyWith(busy: false, error: () => '$e');
      rethrow;
    }
  }

  Future<void> disconnect() async {
    final a = state.account;
    final keep = a == null ? null : LastFmAccount(apiKey: a.apiKey, secret: a.secret);
    await ref.read(databaseProvider).setValue(accountKey, jsonEncode(keep?.toJson()));
    state = state.copyWith(account: () => keep, error: () => null);
  }

  Future<void> setEnabled(bool enabled) async {
    state = state.copyWith(enabled: enabled);
    await ref.read(databaseProvider).setValue(enabledKey, '$enabled');
    if (enabled) unawaited(flush());
  }

  Future<void> nowPlaying(Scrobble s) async {
    final client = _client();
    if (!state.active || client == null) return;
    try {
      await client.nowPlaying(state.account!.sessionKey!, artist: s.artist, track: s.track, album: s.album, duration: s.duration);
    } catch (_) {
      // Best effort: "now playing" isn't worth retrying.
    }
  }

  Future<void> enqueue(Scrobble s) async {
    if (!state.enabled) return;
    _queue.add(s);
    await _saveQueue();
    await flush();
  }

  /// Sends what's waiting, oldest first; keeps it if Last.fm can't be reached.
  Future<void> flush() async {
    final client = _client();
    if (_flushing || !state.active || client == null) return;
    _flushing = true;
    try {
      final cutoff = DateTime.now().subtract(maxAge);
      _queue.removeWhere((s) => s.startedAt.isBefore(cutoff));
      while (_queue.isNotEmpty) {
        final batch = _queue.take(LastFmClient.batch).toList();
        await client.scrobble(state.account!.sessionKey!, batch);
        _queue.removeRange(0, batch.length);
        await _saveQueue();
      }
      state = state.copyWith(error: () => null);
    } on LastFmException catch (e) {
      state = state.copyWith(error: () => e.message);
      if (e.isAuth) await disconnect();
    } catch (e) {
      // Offline: try again with the next listen or on the next launch.
      state = state.copyWith(error: () => null);
    } finally {
      _flushing = false;
      await _saveQueue();
    }
  }
}

/// Feeds Last.fm: "now playing" on each new song, a scrobble for each listen
/// that counts. Watched once by the app shell.
final lastFmSyncProvider = Provider<void>((ref) {
  final notifier = ref.read(lastFmProvider.notifier);
  Scrobble? describe(int songId, DateTime at) {
    final song = ref.read(songsByIdProvider)[songId];
    // Last.fm wants real tags and tracks over 30 s.
    if (song == null || song.artist == Song.unknownArtist || song.duration < const Duration(seconds: 30)) return null;
    return Scrobble(artist: song.artist, track: song.title, album: song.album, startedAt: at, duration: song.duration);
  }

  ref.listen(currentSongProvider, (prev, song) {
    if (song == null || song.id == prev?.id) return;
    if (describe(song.id, DateTime.now()) case final s?) notifier.nowPlaying(s);
  });
  ref.listen<List<PlayEvent>>(playLogProvider, (prev, next) {
    // One new listen at a time (a restore appends many: those aren't scrobbled).
    if (prev == null || next.length != prev.length + 1) return;
    final e = next.last;
    if (!e.counted) return;
    if (describe(e.songId, e.at) case final s?) notifier.enqueue(s);
  });
  // Anything left from last time.
  scheduleMicrotask(notifier.flush);
});
