// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String songs(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count songs',
      one: '1 song',
    );
    return '$_temp0';
  }

  @override
  String albums(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count albums',
      one: '1 album',
    );
    return '$_temp0';
  }

  @override
  String playlistsCount(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count playlists',
      one: '1 playlist',
    );
    return '$_temp0';
  }

  @override
  String plays(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count plays',
      one: '1 play',
    );
    return '$_temp0';
  }

  @override
  String folders(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count folders',
      one: '1 folder',
    );
    return '$_temp0';
  }

  @override
  String files(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count files',
      one: '1 file',
    );
    return '$_temp0';
  }

  @override
  String eqPresets(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count EQ presets',
      one: '1 EQ preset',
    );
    return '$_temp0';
  }

  @override
  String rules(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count rules',
      one: '1 rule',
    );
    return '$_temp0';
  }

  @override
  String newFavorites(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count new favorites',
      one: '1 new favorite',
    );
    return '$_temp0';
  }

  @override
  String favoritesCount(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count favorites',
      one: '1 favorite',
    );
    return '$_temp0';
  }

  @override
  String listens(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count listens',
      one: '1 listen',
    );
    return '$_temp0';
  }

  @override
  String historyEntries(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count history entries',
      one: '1 history entry',
    );
    return '$_temp0';
  }

  @override
  String get goodNight => 'Good night';

  @override
  String get goodMorning => 'Good morning';

  @override
  String get goodAfternoon => 'Good afternoon';

  @override
  String get goodEvening => 'Good evening';

  @override
  String get yourStats => 'Your stats';

  @override
  String get settings => 'Settings';

  @override
  String get shuffleAll => 'Shuffle all';

  @override
  String get favorites => 'Favorites';

  @override
  String get recentlyPlayed => 'Recently played';

  @override
  String get recentlyAdded => 'Recently added';

  @override
  String get yourPlaylists => 'Your playlists';

  @override
  String get newPlaylist => 'New playlist';

  @override
  String get create => 'Create';

  @override
  String get tabHome => 'Home';

  @override
  String get tabLibrary => 'Library';

  @override
  String get tabSearch => 'Search';

  @override
  String get couldNotPlayFile => 'Couldn\'t play this file';

  @override
  String couldNotPlay(Object title) {
    return 'Couldn\'t play \"$title\" — skipped';
  }

  @override
  String get back => 'Back';

  @override
  String get noFavoritesYet => 'No favorites yet';

  @override
  String get noFavoritesHint =>
      'Tap the heart in the player, or use a song\'s menu, to save it here.';

  @override
  String get play => 'Play';

  @override
  String get shuffle => 'Shuffle';

  @override
  String get pause => 'Pause';

  @override
  String get next => 'Next';

  @override
  String get more => 'More';

  @override
  String get nowPlaying => 'Now playing';

  @override
  String get upNext => 'Up next';

  @override
  String get shuffled => 'Shuffled';

  @override
  String get nothingQueued => 'Nothing else queued.';

  @override
  String get all => 'All';

  @override
  String get looseFiles => 'Loose files';

  @override
  String playCount(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Play $count songs',
      one: 'Play 1 song',
    );
    return '$_temp0';
  }

  @override
  String get renamePlaylist => 'Rename playlist';

  @override
  String get rename => 'Rename';

  @override
  String get deletePlaylistTitle => 'Delete playlist?';

  @override
  String deletePlaylistBody(Object name) {
    return '\"$name\" will be deleted. Your songs stay on the device.';
  }

  @override
  String get cancel => 'Cancel';

  @override
  String get delete => 'Delete';

  @override
  String get playlistOptions => 'Playlist options';

  @override
  String get emptyPlaylist => 'Empty playlist';

  @override
  String get noSongsYet => 'No songs yet';

  @override
  String get noSongsYetHint =>
      'Use \"Add to playlist…\" from any song\'s menu.';

  @override
  String get removeFromPlaylist => 'Remove from playlist';

  @override
  String get searchHint => 'Songs, albums, artists';

  @override
  String get findYourMusic => 'Find your music';

  @override
  String get searchBy => 'Search by song title, artist or album.';

  @override
  String get noResults => 'No results';

  @override
  String nothingMatches(Object query) {
    return 'Nothing matches \"$query\".';
  }

  @override
  String get artists => 'Artists';

  @override
  String get albumsTitle => 'Albums';

  @override
  String get songsTitle => 'Songs';

  @override
  String get playNext => 'Play next';

  @override
  String playingNext(Object title) {
    return 'Playing \"$title\" next';
  }

  @override
  String get addToQueue => 'Add to queue';

  @override
  String get addedToQueue => 'Added to queue';

  @override
  String get addToPlaylistEllipsis => 'Add to playlist…';

  @override
  String get addToPlaylist => 'Add to playlist';

  @override
  String get removeFromFavorites => 'Remove from favorites';

  @override
  String get addToFavorites => 'Add to favorites';

  @override
  String get addedToFavorites => 'Added to favorites';

  @override
  String get removedFromFavorites => 'Removed from favorites';

  @override
  String get soundPresetEllipsis => 'Sound preset…';

  @override
  String get songInfo => 'Song info';

  @override
  String get goToAlbum => 'Go to album';

  @override
  String get goToArtist => 'Go to artist';

  @override
  String get playlistName => 'Playlist name';

  @override
  String alreadyIn(Object name) {
    return 'Already in \"$name\"';
  }

  @override
  String addedSongsTo(num count, Object name) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Added $count songs to \"$name\"',
      one: 'Added 1 song to \"$name\"',
    );
    return '$_temp0';
  }

  @override
  String createdPlaylist(Object name) {
    return 'Created \"$name\"';
  }

  @override
  String get couldNotReadMusic => 'Could not read your music';

  @override
  String get tryAgain => 'Try again';

  @override
  String get noAudioFound => 'No audio found';

  @override
  String get noAudioFoundHint =>
      'audifac looked through your whole phone and SD card. Copy some audio files to the device, then scan again.';

  @override
  String get scanAgain => 'Scan again';

  @override
  String get everythingHidden => 'Everything is hidden';

  @override
  String everythingHiddenHint(Object count) {
    return '$count audio files were found, but your library filters (minimum length, recordings, excluded folders) hide them all.';
  }

  @override
  String get librarySettings => 'Library settings';

  @override
  String get allowAccessTitle => 'Allow access to your music';

  @override
  String get accessTurnedOff =>
      'Access was turned off. Enable \"Music and audio\" for audifac in system settings.';

  @override
  String get accessNeeded =>
      'audifac needs permission to find the songs stored on this device.';

  @override
  String get openSettings => 'Open settings';

  @override
  String get allowAccess => 'Allow access';

  @override
  String get searchingPhone => 'Searching your phone for audio…';

  @override
  String get searchingPhoneHint =>
      'Internal storage and SD card, every folder.';

  @override
  String get sortTitle => 'Title';

  @override
  String get sortArtist => 'Artist';

  @override
  String get sortAlbum => 'Album';

  @override
  String get sortRecentlyAdded => 'Recently added';

  @override
  String get sortMostPlayed => 'Most played';

  @override
  String get sortRandom => 'Random';

  @override
  String get qualityHiRes => 'Hi-Res';

  @override
  String get qualityLossless => 'Lossless';

  @override
  String get qualityLossy => 'Lossy';

  @override
  String get qualityUnknown => 'Unknown';

  @override
  String get sourceMusic => 'Music';

  @override
  String get sourceDownloads => 'Downloads';

  @override
  String get sourceRecordings => 'Recordings';

  @override
  String get sourcePodcasts => 'Podcasts';

  @override
  String get sourceAudiobooks => 'Audiobooks';

  @override
  String get sourceHidden => 'Hidden folder';

  @override
  String get sourceOther => 'Other';

  @override
  String get off => 'Off';

  @override
  String get volumeTrack => 'Track';

  @override
  String get volumeAlbum => 'Album';

  @override
  String get volumeSmart => 'Smart';

  @override
  String get range7Days => '7 days';

  @override
  String get range30Days => '30 days';

  @override
  String get rangeYear => 'Year';

  @override
  String get rangeAllTime => 'All time';

  @override
  String get fieldTitle => 'Title';

  @override
  String get fieldArtist => 'Artist';

  @override
  String get fieldAlbum => 'Album';

  @override
  String get fieldGenre => 'Genre';

  @override
  String get fieldFolder => 'Folder';

  @override
  String get fieldQuality => 'Quality';

  @override
  String get fieldCodec => 'Codec';

  @override
  String get fieldSource => 'Source';

  @override
  String get fieldYear => 'Year';

  @override
  String get fieldLength => 'Length (minutes)';

  @override
  String get fieldPlays => 'Play count';

  @override
  String get fieldAdded => 'Added';

  @override
  String get fieldLastPlayed => 'Last played';

  @override
  String get fieldFavorite => 'Favorite';

  @override
  String get opContains => 'contains';

  @override
  String get opNotContains => 'doesn\'t contain';

  @override
  String get opIs => 'is';

  @override
  String get opIsNot => 'is not';

  @override
  String get opAtLeast => 'at least';

  @override
  String get opAtMost => 'at most';

  @override
  String get opWithin => 'in the last (days)';

  @override
  String get opNotWithin => 'not in the last (days)';

  @override
  String get opNever => 'Never';

  @override
  String get yes => 'Yes';

  @override
  String get no => 'No';

  @override
  String ruleWithin(Object days, Object field) {
    return '$field in the last $days days';
  }

  @override
  String ruleNotWithin(Object days, Object field) {
    return '$field over $days days ago';
  }

  @override
  String ruleNot(Object field) {
    return 'Not $field';
  }

  @override
  String get neverPlayed => 'Never played';

  @override
  String get allSongs => 'All songs';

  @override
  String get or => 'or';

  @override
  String get smartForgotten => 'Not played in 30 days';

  @override
  String get smartAddedThisWeek => 'Added this week';

  @override
  String get reasonSession => 'this session';

  @override
  String get reasonSong => 'song';

  @override
  String get reasonAlbum => 'album';

  @override
  String get reasonArtist => 'artist';

  @override
  String get reasonGenre => 'genre';

  @override
  String get reasonSource => 'source';

  @override
  String get reasonDefault => 'default';

  @override
  String get thisSong => 'This song';

  @override
  String get thisAlbum => 'This album';

  @override
  String get thisArtist => 'This artist';

  @override
  String get thisGenre => 'This genre';

  @override
  String get thisSource => 'This source';

  @override
  String get filterPeak => 'Peak';

  @override
  String get filterLowShelf => 'Low shelf';

  @override
  String get filterHighShelf => 'High shelf';

  @override
  String get filterLowPass => 'Low-pass';

  @override
  String get filterHighPass => 'High-pass';

  @override
  String get filterNotch => 'Notch';

  @override
  String get presetNoCorrection => 'No correction';

  @override
  String get presetFlat => 'Flat';

  @override
  String get presetBassBoost => 'Bass boost';

  @override
  String get presetBassReducer => 'Bass reducer';

  @override
  String get presetTrebleBoost => 'Treble boost';

  @override
  String get presetTrebleReducer => 'Treble reducer';

  @override
  String get presetVocal => 'Vocal';

  @override
  String get presetClassical => 'Classical';

  @override
  String get presetElectronic => 'Electronic';

  @override
  String get presetAcoustic => 'Acoustic';

  @override
  String get presetLoudness => 'Loudness';

  @override
  String get presetLateNight => 'Late night';

  @override
  String get presetSmallSpeakers => 'Small speakers';

  @override
  String get presetSpoken => 'Spoken word';

  @override
  String get scanningStorage => 'Scanning internal storage and SD card…';

  @override
  String shown(Object count) {
    return '$count shown';
  }

  @override
  String shownOfFound(Object found, Object shown) {
    return '$shown shown of $found found';
  }

  @override
  String scannedIn(num count, Object seconds) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count files on storage, scanned in $seconds s',
      one: '1 file on storage, scanned in $seconds s',
    );
    return '$_temp0';
  }

  @override
  String lastScanFailed(Object error) {
    return 'Last scan failed: $error';
  }

  @override
  String get appearance => 'Appearance';

  @override
  String get themeSystem => 'System';

  @override
  String get themeLight => 'Light';

  @override
  String get themeDark => 'Dark';

  @override
  String get languageSystem => 'Phone language';

  @override
  String get sound => 'Sound';

  @override
  String get equalizer => 'Equalizer';

  @override
  String get equalizerOnSummary => 'On · presets, headphone correction, rules';

  @override
  String get volumeMatching => 'Volume matching';

  @override
  String get crossfade => 'Crossfade';

  @override
  String seconds(Object count) {
    return '$count s';
  }

  @override
  String get crossfadeOffHint =>
      'Off: songs play gaplessly, exactly as mastered.';

  @override
  String get crossfadeOnHint =>
      'Songs blend into each other — except tracks of the same album, which stay gapless.';

  @override
  String get keepAlbumsTogether => 'Keep albums together when shuffling';

  @override
  String get keepAlbumsTogetherHint =>
      'Shuffles whole albums; each plays in order';

  @override
  String get scanDevice => 'Scan device for audio';

  @override
  String get foldersTitle => 'Folders';

  @override
  String get allFoldersIncluded => 'All folders included';

  @override
  String foldersExcluded(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count folders excluded',
      one: '1 folder excluded',
    );
    return '$_temp0';
  }

  @override
  String get showLabels => 'Show labels on songs';

  @override
  String showLabelsAnalysing(Object done, Object total) {
    return 'Source & codec · analysing audio $done / $total…';
  }

  @override
  String get showLabelsHint =>
      'Source folder & codec (e.g. Downloads · FLAC 24/96)';

  @override
  String get showRecordings => 'Show recordings & voice notes';

  @override
  String get showRecordingsHint =>
      'Voice recorder, call recordings, WhatsApp voice notes';

  @override
  String get hideShorterThan => 'Hide audio shorter than';

  @override
  String get ringtonesHidden =>
      'Ringtones, alarms and notification sounds are always hidden.';

  @override
  String get addWidget => 'Add player widget to home screen';

  @override
  String get addWidgetManually =>
      'Long-press your home screen → Widgets → audifac';

  @override
  String get backup => 'Backup';

  @override
  String get backUpToFile => 'Back up to a file';

  @override
  String get backUpHint =>
      'Favorites, playlists, history & play counts, EQ, settings';

  @override
  String get restoreFromFile => 'Restore from a file';

  @override
  String get restoreHint => 'Merges with what you have — nothing is deleted';

  @override
  String get about => 'About';

  @override
  String get aboutAudifac => 'About audifac';

  @override
  String backedUp(Object favorites, Object playlists, Object presets) {
    return 'Backed up $favorites, $playlists, $presets';
  }

  @override
  String backupFailed(Object error) {
    return 'Backup failed: $error';
  }

  @override
  String cantRestore(Object reason) {
    return 'Can\'t restore: $reason';
  }

  @override
  String get restored => 'Restored';

  @override
  String fromBackupOf(Object date, Object version) {
    return 'From a backup of $date (audifac $version):';
  }

  @override
  String listensRestored(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count listens (play counts & stats)',
      one: '1 listen (play counts & stats)',
    );
    return '$_temp0';
  }

  @override
  String missingSongs(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          '$count songs from the backup aren\'t on this device and were skipped.',
      one: '1 song from the backup isn\'t on this device and was skipped.',
    );
    return '$_temp0';
  }

  @override
  String get ok => 'OK';

  @override
  String get internalStorage => 'Internal storage';

  @override
  String get sdCard => 'SD card';

  @override
  String scanningFolder(Object folder) {
    return 'Scanning $folder…';
  }

  @override
  String get foldersIntro =>
      'audifac scans your whole phone and SD card automatically. Untick a folder to hide its audio and skip it when scanning.';

  @override
  String get foldersWithAudio => 'Folders with audio';

  @override
  String get noneFoundYet => 'None found yet.';

  @override
  String get hiddenFolders => 'Hidden folders';

  @override
  String get hiddenFoldersIntro =>
      'Android hides some folders from apps (those with a \".nomedia\" file, like WhatsApp voice notes). Add one here to include its audio.';

  @override
  String get remove => 'Remove';

  @override
  String get addFolder => 'Add a folder';

  @override
  String get rescanLibrary => 'Rescan library';

  @override
  String get playlistsTitle => 'Playlists';

  @override
  String songsOf(Object shown, num total) {
    String _temp0 = intl.Intl.pluralLogic(
      total,
      locale: localeName,
      other: '$total songs',
      one: '1 song',
    );
    return '$shown of $_temp0';
  }

  @override
  String get noSongsMatch => 'No songs match';

  @override
  String get noSongsMatchHint => 'Try another quality, codec or source.';

  @override
  String get clearFilters => 'Clear filters';

  @override
  String get sort => 'Sort';

  @override
  String get shuffleAlbums => 'Shuffle albums';

  @override
  String get smartPlaylists => 'Smart playlists';

  @override
  String get newLabel => 'New';

  @override
  String get trackGain => 'Track gain';

  @override
  String get albumGain => 'Album gain';

  @override
  String get smartGain => 'Smart (album gain for whole albums)';

  @override
  String get fromTags => 'ReplayGain tags';

  @override
  String measuredLufs(Object lufs) {
    return 'measured $lufs LUFS';
  }

  @override
  String get notAnalysedYetShort => 'not analysed yet';

  @override
  String get volumeIntro =>
      'Plays every song at the same loudness (ReplayGain 2.0, −18 LUFS), from its tags or an EBU R128 measurement. Applied before the equalizer; dynamics are untouched.';

  @override
  String get volumeOffHint => 'Songs play at their mastered level.';

  @override
  String get volumeTrackHint =>
      'Every song at the same loudness — best for shuffle and mixes.';

  @override
  String get volumeAlbumHint =>
      'Albums keep their quiet and loud songs as mastered.';

  @override
  String get volumeSmartHint =>
      'Album gain while one album plays in order, track gain otherwise.';

  @override
  String nowLine(Object text) {
    return 'Now: $text';
  }

  @override
  String get preamp => 'Pre-amp';

  @override
  String get preampHint =>
      '−18 LUFS is quieter than most modern music; +3 to +6 dB is common.';

  @override
  String get untaggedGain => 'Songs without loudness data';

  @override
  String get untaggedGainHint =>
      'Used until a song is analysed, and for formats that can\'t be.';

  @override
  String get preventClipping => 'Prevent clipping';

  @override
  String get preventClippingHint => 'Never raise a song above its peak level';

  @override
  String songsWithTags(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count songs with tags',
      one: '1 song with tags',
    );
    return '$_temp0';
  }

  @override
  String songsMeasured(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count songs measured',
      one: '1 song measured',
    );
    return '$_temp0';
  }

  @override
  String cantBeAnalysed(Object count) {
    return '$count can\'t be analysed';
  }

  @override
  String notAnalysedYet(Object count) {
    return '$count not analysed yet';
  }

  @override
  String get upcomingAnalysed =>
      'Upcoming songs are analysed automatically while volume matching is on.';

  @override
  String analysingProgress(Object done, Object total) {
    return 'Analysing $done / $total…';
  }

  @override
  String get stop => 'Stop';

  @override
  String get wholeLibraryAnalysed => 'Whole library analysed';

  @override
  String analyseNow(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Analyse $count songs now',
      one: 'Analyse 1 song now',
    );
    return '$_temp0';
  }

  @override
  String get nothingYet => 'Nothing yet';

  @override
  String get playCountRule =>
      'A song counts as played once you\'ve heard half of it (or 4 minutes).';

  @override
  String get listening => 'listening';

  @override
  String playsWord(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'plays',
      one: 'play',
    );
    return '$_temp0';
  }

  @override
  String daysWord(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'days',
      one: 'day',
    );
    return '$_temp0';
  }

  @override
  String get topSongs => 'Top songs';

  @override
  String get topArtists => 'Top artists';

  @override
  String get topAlbums => 'Top albums';

  @override
  String smartCopyName(Object name) {
    return '$name (mine)';
  }

  @override
  String get smartOptions => 'Smart playlist options';

  @override
  String get editCopy => 'Edit a copy';

  @override
  String get editRules => 'Edit rules';

  @override
  String get noMatchingSongs => 'No matching songs';

  @override
  String get noMatchingSongsHint =>
      'Songs appear here as soon as they match the rules.';

  @override
  String get smartPlaylist => 'Smart playlist';

  @override
  String get save => 'Save';

  @override
  String get name => 'Name';

  @override
  String get match => 'Match';

  @override
  String get allRules => 'All rules';

  @override
  String get anyRule => 'Any rule';

  @override
  String get addRule => 'Add rule';

  @override
  String get order => 'Order';

  @override
  String get limit => 'Limit';

  @override
  String get none => 'None';

  @override
  String get noSongsMatchYet => 'No songs match yet';

  @override
  String songsMatchNow(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count songs match right now',
      one: '1 song matches right now',
    );
    return '$_temp0';
  }

  @override
  String get field => 'Field';

  @override
  String get removeRule => 'Remove rule';

  @override
  String get sleepTimer => 'Sleep timer';

  @override
  String get sleepHint => 'Music fades out, then pauses.';

  @override
  String minutesShort(Object count) {
    return '$count min';
  }

  @override
  String get endOfSong => 'End of this song';

  @override
  String get endOfQueue => 'End of the queue';

  @override
  String get turnOff => 'Turn off';

  @override
  String stopsIn(Object time) {
    return 'Stops in $time';
  }

  @override
  String get stopsAtSongEnd => 'Stops at the end of this song';

  @override
  String get stopsAtQueueEnd => 'Stops at the end of the queue';

  @override
  String get songEnd => 'Song end';

  @override
  String get queueEnd => 'Queue end';

  @override
  String get playbackSpeed => 'Playback speed';

  @override
  String get speed => 'Speed';

  @override
  String get speedHint =>
      'For audiobooks & podcasts; voices keep their pitch. Music always plays at 1×.';

  @override
  String get chapters => 'Chapters';

  @override
  String chapterN(Object n) {
    return 'Chapter $n';
  }

  @override
  String get notALyricsFile => 'That isn\'t a lyrics file (.lrc or .txt)';

  @override
  String get lyrics => 'Lyrics';

  @override
  String get lyricsOptions => 'Lyrics options';

  @override
  String get useLyricsFile => 'Use a lyrics file (.lrc / .txt)…';

  @override
  String get removeAttachedFile => 'Remove the attached file';

  @override
  String get noLyrics => 'No lyrics';

  @override
  String get noLyricsHint =>
      'Lyrics come from the song\'s tags or an .lrc file with the same name.';

  @override
  String get chooseLyricsFile => 'Choose a lyrics file';

  @override
  String get close => 'Close';

  @override
  String get queue => 'Queue';

  @override
  String get signalPathAndSpectrum => 'Signal path and spectrum';

  @override
  String get back15 => 'Back 15 seconds';

  @override
  String get forward30 => 'Forward 30 seconds';

  @override
  String get repeat => 'Repeat';

  @override
  String get equalizerOff => 'Equalizer off';

  @override
  String get signal => 'Signal';

  @override
  String get meterLegend => 'Bar: RMS · line: peak (dBFS)';

  @override
  String get signalPath => 'Signal path';

  @override
  String volumeDb(Object db) {
    return 'volume $db';
  }

  @override
  String crossfadeSeconds(Object seconds) {
    return '$seconds s crossfade';
  }

  @override
  String get decoded => 'Decoded';

  @override
  String get notThroughDsp => 'Not playing through the DSP';

  @override
  String get bitTransparent => 'Bit-transparent (no processing) → 32-bit float';

  @override
  String get processing => 'Processing';

  @override
  String dspProcessing(Object what) {
    return '$what → 32-bit float, 64-bit math';
  }

  @override
  String get androidMixer => 'Android mixer';

  @override
  String noResampling(Object rate) {
    return '$rate — no resampling';
  }

  @override
  String resampled(Object from, Object to) {
    return 'Resampled $from → $to';
  }

  @override
  String get output => 'Output';

  @override
  String get phoneSpeaker => 'Phone speaker';

  @override
  String accepts(Object rates) {
    return 'accepts $rates';
  }

  @override
  String get mono => 'Mono';

  @override
  String get stereo => 'Stereo';

  @override
  String channelsN(Object count) {
    return '$count channels';
  }

  @override
  String get audio => 'Audio';

  @override
  String analysingSuffix(Object quality) {
    return '$quality (analysing…)';
  }

  @override
  String get container => 'Container';

  @override
  String get bitrate => 'Bitrate';

  @override
  String get sampleRate => 'Sample rate';

  @override
  String get bitDepth => 'Bit depth';

  @override
  String get channels => 'Channels';

  @override
  String get duration => 'Duration';

  @override
  String get tags => 'Tags';

  @override
  String get albumArtist => 'Album artist';

  @override
  String get track => 'Track';

  @override
  String get disc => 'Disc';

  @override
  String get composer => 'Composer';

  @override
  String get listeningSection => 'Listening';

  @override
  String get playsLabel => 'Plays';

  @override
  String get listeningTime => 'Listening time';

  @override
  String get loudness => 'Loudness';

  @override
  String replayGainTags(Object db) {
    return 'ReplayGain $db (tags)';
  }

  @override
  String get file => 'File';

  @override
  String get size => 'Size';

  @override
  String get modified => 'Modified';

  @override
  String get indexedBy => 'Indexed by';

  @override
  String get indexedGranted => 'Hidden folder (granted)';

  @override
  String get indexedScan => 'audifac storage scan';

  @override
  String get indexedMediaStore => 'Android media library';

  @override
  String get pathCopied => 'File path copied';

  @override
  String get copyPath => 'Copy path';

  @override
  String get chooseSound => 'Choose a sound';

  @override
  String get soundPreset => 'Sound preset';

  @override
  String get openEqualizer => 'Open equalizer';

  @override
  String get applyTo => 'Apply to';

  @override
  String everyTimePlays(Object what) {
    return 'Every time \"$what\" plays';
  }

  @override
  String get yourPresets => 'Your presets';

  @override
  String get builtIn => 'Built-in';

  @override
  String correctionFor(Object device) {
    return 'Correction for $device';
  }

  @override
  String get correctionHint =>
      'Used automatically whenever audio plays on this output.';

  @override
  String get newCorrection => 'New correction / import AutoEQ';

  @override
  String get deletedPreset => 'Deleted preset';

  @override
  String get rulesAndDevices => 'Rules & devices';

  @override
  String get rulesIntro =>
      'The most specific rule wins: song → album → artist → genre → source → all music. Choosing a preset \"for this session\" overrides rules until you start a new queue.';

  @override
  String get allMusic => 'All music';

  @override
  String get defaultSoundPreset => 'Default sound preset';

  @override
  String get change => 'Change';

  @override
  String get genres => 'Genres';

  @override
  String get sources => 'Sources';

  @override
  String get noRulesYet => 'No rules yet';

  @override
  String get noRulesHint =>
      'Use a song\'s menu → \"Sound preset…\" to pick a preset for that song, album, artist or genre.';

  @override
  String get devices => 'Devices';

  @override
  String deviceNowPlaying(Object device) {
    return '$device · now playing';
  }

  @override
  String get thisSession => 'This session';

  @override
  String get blankGraphic => 'Blank 10-band graphic';

  @override
  String get blankParametric => 'Blank parametric';

  @override
  String get importAutoEqFile => 'Import AutoEQ file (ParametricEQ.txt)';

  @override
  String get pasteAutoEq => 'Paste AutoEQ / Equalizer APO text';

  @override
  String get myHeadphones => 'My headphones';

  @override
  String get mySound => 'My sound';

  @override
  String get imported => 'Imported';

  @override
  String get noAutoEqLines =>
      'No \"Filter: ON PK Fc … Hz Gain … dB Q …\" lines found';

  @override
  String get nameThisPreset => 'Name this preset';

  @override
  String get presetNameHint => 'Preset name';

  @override
  String get duplicatePreset => 'Duplicate preset';

  @override
  String myVersion(Object name) {
    return '$name (my version)';
  }

  @override
  String get renamePreset => 'Rename preset';

  @override
  String get copiedAutoEq => 'Copied as AutoEQ / Equalizer APO text';

  @override
  String nowDefault(Object name) {
    return '\"$name\" is now the default for all music';
  }

  @override
  String get deletePresetTitle => 'Delete preset?';

  @override
  String deletePresetBody(Object name) {
    return '\"$name\" and any rules using it will be removed.';
  }

  @override
  String get eqOffHint =>
      'The equalizer is off — you hear the original sound. Turn it on to apply the presets below.';

  @override
  String deviceLayer(Object device) {
    return 'Device · $device';
  }

  @override
  String get autoForOutput => 'auto for this output';

  @override
  String fromReason(Object reason) {
    return 'from $reason';
  }

  @override
  String get curveLegendDevice =>
      'Bold: device correction · faint: what you hear (both layers)';

  @override
  String get curveLegendSound =>
      'Bold: sound preset · faint: what you hear (both layers)';

  @override
  String get deviceCorrection => 'Device correction';

  @override
  String get graphic => 'Graphic';

  @override
  String get parametric => 'Parametric';

  @override
  String get presetOptions => 'Preset options';

  @override
  String get builtInReadOnly => 'Built-in presets are read-only.';

  @override
  String get duplicateToEdit => 'Duplicate to edit';

  @override
  String get gain => 'Gain';

  @override
  String get autoHeadroom => 'Automatic headroom';

  @override
  String autoHeadroomHint(Object db) {
    return 'Lowers the volume by the biggest boost so it never distorts · now $db';
  }

  @override
  String get boostsExceed =>
      'Boosts exceed 0 dB: the limiter will engage. Lower the preamp or turn on automatic headroom.';

  @override
  String get crossfeed => 'Crossfeed';

  @override
  String get crossfeedHint =>
      'Headphones: blends a little of each channel into the other, like speakers in a room.';

  @override
  String get balance => 'Balance';

  @override
  String get centre => 'Centre';

  @override
  String get behaviour => 'Behaviour';

  @override
  String get askOnPlay => 'Ask when I start listening';

  @override
  String get askOnPlayHint =>
      'Offer your presets when a new queue starts and no rule decides';

  @override
  String rulesDevicesCount(Object devices, Object rules) {
    return '$rules rules · $devices devices';
  }

  @override
  String get newPresetImport => 'New preset / import AutoEQ';

  @override
  String get originalSound => 'Original sound (A)';

  @override
  String get holdToCompare => 'Hold to compare with original';

  @override
  String get removeBand => 'Remove band';

  @override
  String get frequency => 'Frequency';

  @override
  String get qWidth => 'Q (width)';

  @override
  String addBand(Object count, Object max) {
    return 'Add band ($count/$max)';
  }

  @override
  String get curveTip =>
      'Tip: drag a numbered point on the curve; pinch it to change its width.';

  @override
  String get duplicate => 'Duplicate';

  @override
  String get copyAsAutoEq => 'Copy as AutoEQ text';

  @override
  String get useForAllMusic => 'Use for all music';

  @override
  String get forgetDevice => 'Forget device';

  @override
  String get offShort => 'Off';

  @override
  String get wiredHeadphones => 'Wired headphones';
}
