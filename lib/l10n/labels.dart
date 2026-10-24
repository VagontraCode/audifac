import '../models/app_settings.dart';
import '../models/audio_info.dart';
import '../models/eq.dart';
import '../models/eq_rules.dart';
import '../models/loudness.dart';
import '../models/play_stats.dart';
import '../models/smart_playlist.dart';
import '../models/song_source.dart';
import 'generated/app_localizations.dart';

/// Translated names for the models' enums (the models stay language-free).
extension Labels on AppLocalizations {
  String songSort(SongSort s) => switch (s) {
        SongSort.title => sortTitle,
        SongSort.artist => sortArtist,
        SongSort.album => sortAlbum,
        SongSort.dateAdded => sortRecentlyAdded,
        SongSort.resolution => sortResolution,
        SongSort.bitrate => sortBitrate,
        SongSort.dynamicRange => sortDynamicRange,
      };

  String quality(AudioQuality q) => switch (q) {
        AudioQuality.hiRes => qualityHiRes,
        AudioQuality.lossless => qualityLossless,
        AudioQuality.lossy => qualityLossy,
        AudioQuality.unknown => qualityUnknown,
      };

  String sourceCategory(SourceCategory c) => switch (c) {
        SourceCategory.music => sourceMusic,
        SourceCategory.downloads => sourceDownloads,
        SourceCategory.whatsapp => 'WhatsApp',
        SourceCategory.telegram => 'Telegram',
        SourceCategory.bluetooth => 'Bluetooth',
        SourceCategory.recordings => sourceRecordings,
        SourceCategory.podcasts => sourcePodcasts,
        SourceCategory.audiobooks => sourceAudiobooks,
        SourceCategory.hidden => sourceHidden,
        SourceCategory.other => sourceOther,
      };

  /// A song's row label: its category, or the folder name for "Other".
  String sourceLabel(SongSource s) => s.category == SourceCategory.other ? s.folderName : sourceCategory(s.category);

  String volumeMode(VolumeMode m) => switch (m) {
        VolumeMode.off => off,
        VolumeMode.track => volumeTrack,
        VolumeMode.album => volumeAlbum,
        VolumeMode.smart => volumeSmart,
      };

  String statsRange(StatsRange r) => switch (r) {
        StatsRange.week => range7Days,
        StatsRange.month => range30Days,
        StatsRange.year => rangeYear,
        StatsRange.all => rangeAllTime,
      };

  String smartField(SmartField f) => switch (f) {
        SmartField.title => fieldTitle,
        SmartField.artist => fieldArtist,
        SmartField.album => fieldAlbum,
        SmartField.genre => fieldGenre,
        SmartField.folder => fieldFolder,
        SmartField.quality => fieldQuality,
        SmartField.codec => fieldCodec,
        SmartField.source => fieldSource,
        SmartField.year => fieldYear,
        SmartField.duration => fieldLength,
        SmartField.plays => fieldPlays,
        SmartField.added => fieldAdded,
        SmartField.lastPlayed => fieldLastPlayed,
        SmartField.favorite => fieldFavorite,
      };

  String smartOp(SmartOp o) => switch (o) {
        SmartOp.contains => opContains,
        SmartOp.notContains => opNotContains,
        SmartOp.equals => opIs,
        SmartOp.notEquals => opIsNot,
        SmartOp.atLeast => opAtLeast,
        SmartOp.atMost => opAtMost,
        SmartOp.within => opWithin,
        SmartOp.notWithin => opNotWithin,
        SmartOp.never => opNever,
        SmartOp.yes => yes,
        SmartOp.no => no,
      };

  String smartSort(SmartSort s) => switch (s) {
        SmartSort.mostPlayed => sortMostPlayed,
        SmartSort.recentlyPlayed => recentlyPlayed,
        SmartSort.recentlyAdded => recentlyAdded,
        SmartSort.title => sortTitle,
        SmartSort.artist => sortArtist,
        SmartSort.random => sortRandom,
      };

  /// A rule in words ("Quality is Hi-Res", "Added in the last 7 days").
  String smartRule(SmartRule r) {
    final field = smartField(r.field);
    final value = switch (r.field) {
      SmartField.quality => quality(AudioQuality.values.where((q) => q.name == r.value).firstOrNull ?? AudioQuality.unknown),
      SmartField.source =>
        sourceCategory(SourceCategory.values.where((c) => c.name == r.value).firstOrNull ?? SourceCategory.other),
      _ => r.value,
    };
    return switch (r.op) {
      SmartOp.within => ruleWithin(r.value, field), // (generated parameters are alphabetical)
      SmartOp.notWithin => ruleNotWithin(r.value, field),
      SmartOp.never => r.field == SmartField.lastPlayed ? neverPlayed : '$field ${opNever.toLowerCase()}',
      SmartOp.yes => field,
      SmartOp.no => ruleNot(field.toLowerCase()),
      _ => '$field ${smartOp(r.op)}${value.isEmpty ? '' : ' $value'}',
    };
  }

  String smartDescribe(SmartPlaylist l) {
    if (l.rules.isEmpty) return allSongs;
    return l.rules.map(smartRule).join(l.matchAll ? ' · ' : ' $or ');
  }

  /// Built-in smart playlists have translated names; the user's keep theirs.
  String smartName(SmartPlaylist l) => switch (l.id) {
        'b_lossless' => qualityLossless,
        'b_hires' => qualityHiRes,
        'b_most' => sortMostPlayed,
        'b_forgotten' => smartForgotten,
        'b_new' => smartAddedThisWeek,
        'b_never' => neverPlayed,
        _ => l.name,
      };

  String eqReason(EqReason r) => switch (r) {
        EqReason.queue => reasonSession,
        EqReason.song => reasonSong,
        EqReason.album => reasonAlbum,
        EqReason.artist => reasonArtist,
        EqReason.genre => reasonGenre,
        EqReason.source => reasonSource,
        EqReason.defaultPreset => reasonDefault,
      };

  String eqScope(EqScope s) => switch (s) {
        EqScope.song => thisSong,
        EqScope.album => thisAlbum,
        EqScope.artist => thisArtist,
        EqScope.genre => thisGenre,
        EqScope.source => thisSource,
      };

  String filterType(EqFilterType t) => switch (t) {
        EqFilterType.peaking => filterPeak,
        EqFilterType.lowShelf => filterLowShelf,
        EqFilterType.highShelf => filterHighShelf,
        EqFilterType.lowPass => filterLowPass,
        EqFilterType.highPass => filterHighPass,
        EqFilterType.notch => filterNotch,
      };

  /// An output device's name; the generic ones are translated.
  String deviceName(EqDevice d) => switch (d.key) {
        'speaker' => phoneSpeaker,
        'wired' => wiredHeadphones,
        _ => d.name,
      };

  /// Built-in presets have translated names; the user's keep theirs.
  String presetName(EqPreset p) {
    if (!p.builtIn) return p.name;
    return switch (p.id) {
      'b_device_none' => presetNoCorrection,
      'b_flat' => presetFlat,
      'b_bass_boost' => presetBassBoost,
      'b_bass_reducer' => presetBassReducer,
      'b_treble_boost' => presetTrebleBoost,
      'b_treble_reducer' => presetTrebleReducer,
      'b_vocal' => presetVocal,
      'b_rock' => 'Rock',
      'b_pop' => 'Pop',
      'b_jazz' => 'Jazz',
      'b_classical' => presetClassical,
      'b_electronic' => presetElectronic,
      'b_hiphop' => 'Hip-hop',
      'b_acoustic' => presetAcoustic,
      'b_loudness' => presetLoudness,
      'b_late_night' => presetLateNight,
      'b_small_speakers' => presetSmallSpeakers,
      'b_spoken' => presetSpoken,
      _ => p.name,
    };
  }
}
