import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../cast/cast_server.dart';
import '../models/song.dart';
import '../transfer/guest_server.dart';
import 'library_providers.dart';

/// A request waiting for the host.
typedef PendingRequest = ({Song song, List<String> from});

class GuestRequestsState {
  const GuestRequestsState({this.url, this.pending = const [], this.error});

  /// Address guests open, while on.
  final String? url;
  final List<PendingRequest> pending;

  /// Why it couldn't start ('wifi', 'failed').
  final String? error;

  bool get on => url != null;
}

/// Soirée guest requests ([GuestServer]). Off until the host switches it on;
/// stays on while the app runs (the host moves around), off when switched off.
final guestRequestsProvider = NotifierProvider<GuestRequestsNotifier, GuestRequestsState>(GuestRequestsNotifier.new);

class GuestRequestsNotifier extends Notifier<GuestRequestsState> {
  GuestServer? _server;
  StreamSubscription<GuestRequest>? _sub;

  @override
  GuestRequestsState build() {
    ref.onDispose(_shutDown);
    return const GuestRequestsState();
  }

  /// What guests can find: visible songs whose title or artist matches.
  static List<GuestSong> searchSongs(List<Song> songs, String query) {
    final words = query.toLowerCase().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
    return [
      for (final s in songs)
        if (words.every((w) => '${s.title} ${s.artist}'.toLowerCase().contains(w))) (id: s.id, title: s.title, artist: s.artist),
    ];
  }

  Future<void> start(GuestPageText texts) async {
    if (_server != null) return;
    final host = await CastServer.localAddress();
    if (host == null) {
      state = const GuestRequestsState(error: 'wifi');
      return;
    }
    final server = GuestServer(search: (q) => searchSongs(ref.read(songsProvider), q), page: guestPage(texts));
    try {
      try {
        await server.start(port: 8766);
      } on Exception {
        await server.start();
      }
    } on Exception {
      state = const GuestRequestsState(error: 'failed');
      return;
    }
    _server = server;
    _sub = server.requests.listen(_onRequest);
    state = GuestRequestsState(url: 'http://$host:${server.port}/${server.token}/');
  }

  void _onRequest(GuestRequest request) {
    final song = ref.read(songsByIdProvider)[request.songId];
    if (song == null) return; // Not (or no longer) in the library.
    final pending = [...state.pending];
    final i = pending.indexWhere((p) => p.song.id == song.id);
    if (i >= 0) {
      // Asked again: one entry, names gathered.
      pending[i] = (song: song, from: {...pending[i].from, ...request.from}.toList());
    } else {
      if (pending.length >= 50) return;
      pending.add((song: song, from: request.from));
    }
    state = GuestRequestsState(url: state.url, pending: pending);
  }

  /// Taken off the list (accepted or declined).
  void resolve(Song song) =>
      state = GuestRequestsState(url: state.url, pending: [for (final p in state.pending) if (p.song.id != song.id) p]);

  Future<void> stop() async {
    await _shutDown();
    state = const GuestRequestsState();
  }

  Future<void> _shutDown() async {
    await _sub?.cancel();
    _sub = null;
    await _server?.dispose();
    _server = null;
  }
}
