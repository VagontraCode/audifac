import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/app_settings.dart';
import '../models/backup.dart';
import '../models/eq.dart';
import '../models/eq_rules.dart';
import '../models/loudness.dart';
import '../models/play_stats.dart';
import '../models/smart_playlist.dart';
import '../models/song.dart';
import 'eq_providers.dart';
import 'library_providers.dart';
import 'loudness_providers.dart';
import 'smart_playlist_providers.dart';
import 'stats_providers.dart';
import 'user_data_providers.dart';

final backupServiceProvider = Provider<BackupService>(BackupService.new);

/// Builds and restores [BackupData] from the app's live state.
class BackupService {
  BackupService(this._ref);

  final Ref _ref;

  BackupData create({required String appVersion}) {
    final byId = _ref.read(songsByIdProvider);
    final albums = {for (final a in _ref.read(albumsProvider)) a.id: a};
    List<SongRef> refs(Iterable<int> ids) => [
          for (final id in ids)
            if (byId[id] case final song?) SongRef.of(song),
        ];

    final rules = <RuleBackup>[];
    for (final r in _ref.read(eqRulesProvider)) {
      switch (r.scope) {
        case EqScope.song:
          final song = byId[int.tryParse(r.key) ?? 0];
          if (song != null) rules.add(RuleBackup(scope: r.scope.name, presetId: r.presetId, label: r.label, song: SongRef.of(song)));
        case EqScope.album:
          final album = albums[int.tryParse(r.key) ?? 0];
          if (album != null) {
            rules.add(RuleBackup(
              scope: r.scope.name,
              presetId: r.presetId,
              label: r.label,
              album: album.title,
              albumArtist: album.artist,
            ));
          }
        case EqScope.artist || EqScope.genre || EqScope.source:
          rules.add(RuleBackup(scope: r.scope.name, presetId: r.presetId, key: r.key, label: r.label));
      }
    }

    return BackupData(
      exportedAt: DateTime.now(),
      appVersion: appVersion,
      favorites: refs(_ref.read(favoritesProvider)),
      recent: refs(_ref.read(recentIdsProvider)),
      playlists: [
        for (final p in _ref.read(playlistsProvider)) PlaylistBackup(name: p.name, songs: refs(p.songIds)),
      ],
      eqPresets: [
        for (final p in _ref.read(eqPresetsProvider))
          if (!p.builtIn) p.toJson().cast<String, dynamic>(),
      ],
      eqRules: rules,
      eqSettings: _ref.read(eqSettingsProvider).encode(),
      plays: [
        for (final e in _groupPlays(_ref.read(playLogProvider)).entries)
          if (byId[e.key] case final song?)
            PlaysBackup(
              song: SongRef.of(song),
              events: [for (final p in e.value) (p.at.millisecondsSinceEpoch, p.listenedMs, p.counted)],
            ),
      ],
      tagEdits: [
        // As the files tag them, so a restore finds them on a fresh install.
        for (final s in _ref.read(libraryProvider).value ?? const <Song>[])
          if (_ref.read(tagEditsProvider)[s.location] case final edit?) TagEditBackup(song: SongRef.of(s), edit: edit),
      ],
      settings: {
        ..._ref.read(settingsProvider).toKeyValues(),
        VolumeMatchingNotifier.key: _ref.read(volumeMatchingProvider).encode(),
        SmartPlaylistsNotifier.key: SmartPlaylist.encodeAll(_ref.read(smartPlaylistsProvider).where((l) => !l.builtIn).toList()),
      },
    );
  }

  /// Merges [data] into the app: nothing existing is deleted.
  Future<RestoreReport> restore(BackupData data) async {
    final report = RestoreReport();
    final matcher = SongMatcher(_ref.read(songsProvider));

    List<Song> resolve(List<SongRef> refs) {
      final out = <Song>[];
      for (final r in refs) {
        final s = matcher.match(r);
        if (s == null) {
          report.missingSongs++;
        } else {
          out.add(s);
        }
      }
      return out;
    }

    // Favorites & history.
    report.favorites = _ref.read(favoritesProvider.notifier).addAll([for (final s in resolve(data.favorites)) s.id]);
    report.recent = await _ref.read(recentIdsProvider.notifier).restore([for (final s in resolve(data.recent)) s.id]);

    // Listening history (play counts, stats).
    final plays = <PlayEvent>[];
    for (final p in data.plays) {
      final song = matcher.match(p.song);
      if (song == null) continue;
      for (final (at, ms, counted) in p.events) {
        plays.add(PlayEvent(songId: song.id, at: DateTime.fromMillisecondsSinceEpoch(at), listenedMs: ms, counted: counted));
      }
    }
    report.plays = await _ref.read(playLogProvider.notifier).restore(plays);

    // Tag edits: songs already edited here keep their edits.
    final edits = _ref.read(tagEditsProvider.notifier);
    for (final t in data.tagEdits) {
      final song = matcher.match(t.song);
      if (song == null || t.edit.isEmpty || _ref.read(tagEditsProvider).containsKey(song.location)) continue;
      await edits.set(song, t.edit);
      report.tagEdits++;
    }

    // Playlists: same name + same songs = already there; otherwise add.
    final playlists = _ref.read(playlistsProvider.notifier);
    for (final p in data.playlists) {
      final songs = [for (final s in resolve(p.songs)) s.id];
      final existing = _ref.read(playlistsProvider).where((x) => x.name == p.name).toList();
      if (existing.any((x) => _sameSongs(x.songIds, songs))) continue;
      final name = existing.isEmpty ? p.name : '${p.name} (restored)';
      await playlists.create(name, songIds: songs);
      report.playlists++;
      report.playlistSongs += songs.length;
    }

    // EQ presets keep their ids, so rules / device assignments still point at them.
    final presets = _ref.read(eqPresetsProvider.notifier);
    for (final json in data.eqPresets) {
      try {
        await presets.save(EqPreset.fromJson(json).copyWith(builtIn: false));
        report.presets++;
      } catch (_) {
        // Skip a malformed preset rather than failing the whole restore.
      }
    }
    if (data.eqSettings != null) {
      _ref.read(eqSettingsProvider.notifier).restore(EqSettings.decode(data.eqSettings));
    }

    // Rules: re-target song / album rules at this device's ids.
    final rules = _ref.read(eqRulesProvider.notifier);
    final albums = _ref.read(albumsProvider);
    for (final r in data.eqRules) {
      final scope = EqScope.values.where((s) => s.name == r.scope).firstOrNull;
      if (scope == null) continue;
      String? key;
      switch (scope) {
        case EqScope.song:
          key = r.song == null ? null : matcher.match(r.song!)?.id.toString();
        case EqScope.album:
          key = albums
              .where((a) => a.title.toLowerCase() == r.album?.toLowerCase() && a.artist.toLowerCase() == r.albumArtist?.toLowerCase())
              .firstOrNull
              ?.id
              .toString();
        case EqScope.artist || EqScope.genre || EqScope.source:
          key = r.key;
      }
      if (key == null) {
        report.missingSongs++;
        continue;
      }
      await rules.put(EqRule(scope: scope, key: key, label: r.label, presetId: r.presetId));
      report.rules++;
    }

    // App settings.
    if (data.settings.isNotEmpty) {
      _ref.read(settingsProvider.notifier).replace(AppSettings.fromKeyValues(data.settings));
      if (data.settings[VolumeMatchingNotifier.key] case final volume?) {
        _ref.read(volumeMatchingProvider.notifier).set(VolumeMatching.decode(volume));
      }
      if (data.settings[SmartPlaylistsNotifier.key] case final smart?) {
        _ref.read(smartPlaylistsProvider.notifier).restore(SmartPlaylist.decodeAll(smart));
      }
      report.settings = true;
    }
    return report;
  }

  static bool _sameSongs(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

Map<int, List<PlayEvent>> _groupPlays(List<PlayEvent> log) {
  final out = <int, List<PlayEvent>>{};
  for (final e in log) {
    out.putIfAbsent(e.songId, () => []).add(e);
  }
  return out;
}
