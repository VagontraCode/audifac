// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for French (`fr`).
class AppLocalizationsFr extends AppLocalizations {
  AppLocalizationsFr([String locale = 'fr']) : super(locale);

  @override
  String songs(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count titres',
      one: '1 titre',
      zero: '0 titre',
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
      zero: '0 album',
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
      zero: '0 playlist',
    );
    return '$_temp0';
  }

  @override
  String plays(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count écoutes',
      one: '1 écoute',
      zero: '0 écoute',
    );
    return '$_temp0';
  }

  @override
  String folders(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count dossiers',
      one: '1 dossier',
      zero: '0 dossier',
    );
    return '$_temp0';
  }

  @override
  String files(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count fichiers',
      one: '1 fichier',
      zero: '0 fichier',
    );
    return '$_temp0';
  }

  @override
  String eqPresets(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count préréglages EQ',
      one: '1 préréglage EQ',
      zero: '0 préréglage EQ',
    );
    return '$_temp0';
  }

  @override
  String rules(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count règles',
      one: '1 règle',
      zero: '0 règle',
    );
    return '$_temp0';
  }

  @override
  String newFavorites(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count nouveaux favoris',
      one: '1 nouveau favori',
      zero: '0 nouveau favori',
    );
    return '$_temp0';
  }

  @override
  String favoritesCount(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count favoris',
      one: '1 favori',
      zero: '0 favori',
    );
    return '$_temp0';
  }

  @override
  String listens(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count écoutes',
      one: '1 écoute',
      zero: '0 écoute',
    );
    return '$_temp0';
  }

  @override
  String historyEntries(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count entrées d\'historique',
      one: '1 entrée d\'historique',
      zero: '0 entrée d\'historique',
    );
    return '$_temp0';
  }

  @override
  String get goodNight => 'Bonne nuit';

  @override
  String get goodMorning => 'Bonjour';

  @override
  String get goodAfternoon => 'Bon après-midi';

  @override
  String get goodEvening => 'Bonsoir';

  @override
  String get yourStats => 'Vos statistiques';

  @override
  String get settings => 'Réglages';

  @override
  String get shuffleAll => 'Tout en aléatoire';

  @override
  String get favorites => 'Favoris';

  @override
  String get recentlyPlayed => 'Écoutés récemment';

  @override
  String get recentlyAdded => 'Ajoutés récemment';

  @override
  String get yourPlaylists => 'Vos playlists';

  @override
  String get newPlaylist => 'Nouvelle playlist';

  @override
  String get create => 'Créer';

  @override
  String get tabHome => 'Accueil';

  @override
  String get tabLibrary => 'Bibliothèque';

  @override
  String get tabSearch => 'Recherche';

  @override
  String get couldNotPlayFile => 'Impossible de lire ce fichier';

  @override
  String couldNotPlay(Object title) {
    return 'Impossible de lire « $title » — passé';
  }

  @override
  String get back => 'Retour';

  @override
  String get noFavoritesYet => 'Pas encore de favoris';

  @override
  String get noFavoritesHint =>
      'Touchez le cœur dans le lecteur, ou utilisez le menu d\'un titre, pour l\'ajouter ici.';

  @override
  String get play => 'Lire';

  @override
  String get shuffle => 'Aléatoire';

  @override
  String get pause => 'Pause';

  @override
  String get next => 'Suivant';

  @override
  String get more => 'Plus';

  @override
  String get nowPlaying => 'En cours de lecture';

  @override
  String get upNext => 'À suivre';

  @override
  String get shuffled => 'Aléatoire';

  @override
  String get nothingQueued => 'Rien d\'autre dans la file.';

  @override
  String get all => 'Tout';

  @override
  String get looseFiles => 'Fichiers à la racine';

  @override
  String playCount(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Lire $count titres',
      one: 'Lire 1 titre',
      zero: 'Lire 0 titre',
    );
    return '$_temp0';
  }

  @override
  String get renamePlaylist => 'Renommer la playlist';

  @override
  String get rename => 'Renommer';

  @override
  String get deletePlaylistTitle => 'Supprimer la playlist ?';

  @override
  String deletePlaylistBody(Object name) {
    return '« $name » sera supprimée. Vos titres restent sur l\'appareil.';
  }

  @override
  String get cancel => 'Annuler';

  @override
  String get delete => 'Supprimer';

  @override
  String get playlistOptions => 'Options de la playlist';

  @override
  String get emptyPlaylist => 'Playlist vide';

  @override
  String get noSongsYet => 'Aucun titre pour l\'instant';

  @override
  String get noSongsYetHint =>
      'Utilisez « Ajouter à une playlist… » dans le menu d\'un titre.';

  @override
  String get removeFromPlaylist => 'Retirer de la playlist';

  @override
  String get searchHint => 'Titres, albums, artistes';

  @override
  String get findYourMusic => 'Trouvez votre musique';

  @override
  String get searchBy => 'Cherchez par titre, artiste ou album.';

  @override
  String get noResults => 'Aucun résultat';

  @override
  String nothingMatches(Object query) {
    return 'Rien ne correspond à « $query ».';
  }

  @override
  String get artists => 'Artistes';

  @override
  String get albumsTitle => 'Albums';

  @override
  String get songsTitle => 'Titres';

  @override
  String get playNext => 'Lire ensuite';

  @override
  String playingNext(Object title) {
    return '« $title » sera lu ensuite';
  }

  @override
  String get addToQueue => 'Ajouter à la file';

  @override
  String get addedToQueue => 'Ajouté à la file';

  @override
  String get addToPlaylistEllipsis => 'Ajouter à une playlist…';

  @override
  String get addToPlaylist => 'Ajouter à une playlist';

  @override
  String get removeFromFavorites => 'Retirer des favoris';

  @override
  String get addToFavorites => 'Ajouter aux favoris';

  @override
  String get addedToFavorites => 'Ajouté aux favoris';

  @override
  String get removedFromFavorites => 'Retiré des favoris';

  @override
  String get soundPresetEllipsis => 'Préréglage sonore…';

  @override
  String get songInfo => 'Infos du titre';

  @override
  String get goToAlbum => 'Aller à l\'album';

  @override
  String get goToArtist => 'Aller à l\'artiste';

  @override
  String get playlistName => 'Nom de la playlist';

  @override
  String alreadyIn(Object name) {
    return 'Déjà dans « $name »';
  }

  @override
  String addedSongsTo(num count, Object name) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count titres ajoutés à « $name »',
      one: '1 titre ajouté à « $name »',
      zero: '0 titre ajouté à « $name »',
    );
    return '$_temp0';
  }

  @override
  String createdPlaylist(Object name) {
    return '« $name » créée';
  }

  @override
  String get couldNotReadMusic => 'Impossible de lire votre musique';

  @override
  String get tryAgain => 'Réessayer';

  @override
  String get noAudioFound => 'Aucun fichier audio';

  @override
  String get noAudioFoundHint =>
      'audifac a parcouru tout votre téléphone et la carte SD. Copiez des fichiers audio sur l\'appareil, puis relancez la recherche.';

  @override
  String get scanAgain => 'Rechercher à nouveau';

  @override
  String get everythingHidden => 'Tout est masqué';

  @override
  String everythingHiddenHint(Object count) {
    return '$count fichiers audio ont été trouvés, mais vos filtres (durée minimale, enregistrements, dossiers exclus) les masquent tous.';
  }

  @override
  String get librarySettings => 'Réglages de la bibliothèque';

  @override
  String get allowAccessTitle => 'Autoriser l\'accès à votre musique';

  @override
  String get accessTurnedOff =>
      'L\'accès a été désactivé. Activez « Musique et audio » pour audifac dans les réglages du système.';

  @override
  String get accessNeeded =>
      'audifac a besoin d\'une autorisation pour trouver les titres de cet appareil.';

  @override
  String get openSettings => 'Ouvrir les réglages';

  @override
  String get allowAccess => 'Autoriser l\'accès';

  @override
  String get searchingPhone =>
      'Recherche des fichiers audio sur votre téléphone…';

  @override
  String get searchingPhoneHint =>
      'Stockage interne et carte SD, tous les dossiers.';

  @override
  String get sortTitle => 'Titre';

  @override
  String get sortArtist => 'Artiste';

  @override
  String get sortAlbum => 'Album';

  @override
  String get sortRecentlyAdded => 'Ajout récent';

  @override
  String get sortMostPlayed => 'Les plus écoutés';

  @override
  String get sortRandom => 'Aléatoire';

  @override
  String get qualityHiRes => 'Hi-Res';

  @override
  String get qualityLossless => 'Sans perte';

  @override
  String get qualityLossy => 'Avec perte';

  @override
  String get qualityUnknown => 'Inconnue';

  @override
  String get sourceMusic => 'Musique';

  @override
  String get sourceDownloads => 'Téléchargements';

  @override
  String get sourceRecordings => 'Enregistrements';

  @override
  String get sourcePodcasts => 'Podcasts';

  @override
  String get sourceAudiobooks => 'Livres audio';

  @override
  String get sourceHidden => 'Dossier masqué';

  @override
  String get sourceOther => 'Autre';

  @override
  String get off => 'Désactivé';

  @override
  String get volumeTrack => 'Titre';

  @override
  String get volumeAlbum => 'Album';

  @override
  String get volumeSmart => 'Auto';

  @override
  String get range7Days => '7 jours';

  @override
  String get range30Days => '30 jours';

  @override
  String get rangeYear => 'Année';

  @override
  String get rangeAllTime => 'Toujours';

  @override
  String get fieldTitle => 'Titre';

  @override
  String get fieldArtist => 'Artiste';

  @override
  String get fieldAlbum => 'Album';

  @override
  String get fieldGenre => 'Genre';

  @override
  String get fieldFolder => 'Dossier';

  @override
  String get fieldQuality => 'Qualité';

  @override
  String get fieldCodec => 'Codec';

  @override
  String get fieldSource => 'Source';

  @override
  String get fieldYear => 'Année';

  @override
  String get fieldLength => 'Durée (minutes)';

  @override
  String get fieldPlays => 'Nombre d\'écoutes';

  @override
  String get fieldAdded => 'Ajouté';

  @override
  String get fieldLastPlayed => 'Dernière écoute';

  @override
  String get fieldFavorite => 'Favori';

  @override
  String get opContains => 'contient';

  @override
  String get opNotContains => 'ne contient pas';

  @override
  String get opIs => 'est';

  @override
  String get opIsNot => 'n\'est pas';

  @override
  String get opAtLeast => 'au moins';

  @override
  String get opAtMost => 'au plus';

  @override
  String get opWithin => 'ces derniers (jours)';

  @override
  String get opNotWithin => 'pas ces derniers (jours)';

  @override
  String get opNever => 'Jamais';

  @override
  String get yes => 'Oui';

  @override
  String get no => 'Non';

  @override
  String ruleWithin(Object days, Object field) {
    return '$field ces $days derniers jours';
  }

  @override
  String ruleNotWithin(Object days, Object field) {
    return '$field il y a plus de $days jours';
  }

  @override
  String ruleNot(Object field) {
    return 'Pas $field';
  }

  @override
  String get neverPlayed => 'Jamais écoutés';

  @override
  String get allSongs => 'Tous les titres';

  @override
  String get or => 'ou';

  @override
  String get smartForgotten => 'Pas écoutés depuis 30 jours';

  @override
  String get smartAddedThisWeek => 'Ajoutés cette semaine';

  @override
  String get reasonSession => 'cette session';

  @override
  String get reasonSong => 'titre';

  @override
  String get reasonAlbum => 'album';

  @override
  String get reasonArtist => 'artiste';

  @override
  String get reasonGenre => 'genre';

  @override
  String get reasonSource => 'source';

  @override
  String get reasonDefault => 'par défaut';

  @override
  String get thisSong => 'Ce titre';

  @override
  String get thisAlbum => 'Cet album';

  @override
  String get thisArtist => 'Cet artiste';

  @override
  String get thisGenre => 'Ce genre';

  @override
  String get thisSource => 'Cette source';

  @override
  String get filterPeak => 'Cloche';

  @override
  String get filterLowShelf => 'Plateau grave';

  @override
  String get filterHighShelf => 'Plateau aigu';

  @override
  String get filterLowPass => 'Passe-bas';

  @override
  String get filterHighPass => 'Passe-haut';

  @override
  String get filterNotch => 'Coupe-bande';

  @override
  String get presetNoCorrection => 'Aucune correction';

  @override
  String get presetFlat => 'Neutre';

  @override
  String get presetBassBoost => 'Graves renforcés';

  @override
  String get presetBassReducer => 'Graves réduits';

  @override
  String get presetTrebleBoost => 'Aigus renforcés';

  @override
  String get presetTrebleReducer => 'Aigus réduits';

  @override
  String get presetVocal => 'Voix';

  @override
  String get presetClassical => 'Classique';

  @override
  String get presetElectronic => 'Électronique';

  @override
  String get presetAcoustic => 'Acoustique';

  @override
  String get presetLoudness => 'Loudness';

  @override
  String get presetLateNight => 'Soirée';

  @override
  String get presetSmallSpeakers => 'Petits haut-parleurs';

  @override
  String get presetSpoken => 'Voix parlée';

  @override
  String get scanningStorage =>
      'Analyse du stockage interne et de la carte SD…';

  @override
  String shown(Object count) {
    return '$count affichés';
  }

  @override
  String shownOfFound(Object found, Object shown) {
    return '$shown affichés sur $found trouvés';
  }

  @override
  String scannedIn(num count, Object seconds) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count fichiers sur le stockage, analysés en $seconds s',
      one: '1 fichier sur le stockage, analysé en $seconds s',
      zero: '0 fichier sur le stockage, analysé en $seconds s',
    );
    return '$_temp0';
  }

  @override
  String lastScanFailed(Object error) {
    return 'Dernière analyse échouée : $error';
  }

  @override
  String get appearance => 'Apparence';

  @override
  String get themeSystem => 'Système';

  @override
  String get themeLight => 'Clair';

  @override
  String get themeDark => 'Sombre';

  @override
  String get languageSystem => 'Auto';

  @override
  String get sound => 'Son';

  @override
  String get equalizer => 'Égaliseur';

  @override
  String get equalizerOnSummary =>
      'Activé · préréglages, correction du casque, règles';

  @override
  String get volumeMatching => 'Égalisation du volume';

  @override
  String get crossfade => 'Fondu enchaîné';

  @override
  String seconds(Object count) {
    return '$count s';
  }

  @override
  String get crossfadeOffHint =>
      'Désactivé : les titres s\'enchaînent sans blanc, exactement comme masterisés.';

  @override
  String get crossfadeOnHint =>
      'Les titres se fondent l\'un dans l\'autre — sauf ceux d\'un même album, qui restent enchaînés sans blanc.';

  @override
  String get keepAlbumsTogether => 'Garder les albums entiers en aléatoire';

  @override
  String get keepAlbumsTogetherHint =>
      'Mélange des albums entiers, chacun lu dans l\'ordre';

  @override
  String get scanDevice => 'Rechercher l\'audio sur l\'appareil';

  @override
  String get foldersTitle => 'Dossiers';

  @override
  String get allFoldersIncluded => 'Tous les dossiers inclus';

  @override
  String foldersExcluded(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count dossiers exclus',
      one: '1 dossier exclu',
      zero: '0 dossier exclu',
    );
    return '$_temp0';
  }

  @override
  String get showLabels => 'Étiquettes sur les titres';

  @override
  String showLabelsAnalysing(Object done, Object total) {
    return 'Source et codec · analyse audio $done / $total…';
  }

  @override
  String get showLabelsHint =>
      'Dossier source et codec (ex. Téléchargements · FLAC 24/96)';

  @override
  String get showRecordings => 'Afficher les enregistrements et notes vocales';

  @override
  String get showRecordingsHint =>
      'Dictaphone, enregistrements d\'appels, notes vocales WhatsApp';

  @override
  String get hideShorterThan => 'Masquer l\'audio de moins de';

  @override
  String get ringtonesHidden =>
      'Les sonneries, alarmes et sons de notification sont toujours masqués.';

  @override
  String get addWidget => 'Ajouter le widget à l\'écran d\'accueil';

  @override
  String get addWidgetManually =>
      'Appui long sur l\'écran d\'accueil → Widgets → audifac';

  @override
  String get backup => 'Sauvegarde';

  @override
  String get backUpToFile => 'Sauvegarder dans un fichier';

  @override
  String get backUpHint =>
      'Favoris, playlists, historique et écoutes, EQ, réglages';

  @override
  String get restoreFromFile => 'Restaurer depuis un fichier';

  @override
  String get restoreHint => 'Fusionne avec l\'existant — rien n\'est supprimé';

  @override
  String get about => 'À propos';

  @override
  String get aboutAudifac => 'À propos d\'audifac';

  @override
  String backedUp(Object favorites, Object playlists, Object presets) {
    return 'Sauvegardé : $favorites, $playlists, $presets';
  }

  @override
  String backupFailed(Object error) {
    return 'Échec de la sauvegarde : $error';
  }

  @override
  String cantRestore(Object reason) {
    return 'Restauration impossible : $reason';
  }

  @override
  String get restored => 'Restauré';

  @override
  String fromBackupOf(Object date, Object version) {
    return 'Depuis une sauvegarde du $date (audifac $version) :';
  }

  @override
  String listensRestored(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count écoutes (statistiques)',
      one: '1 écoute (statistiques)',
      zero: '0 écoute (statistiques)',
    );
    return '$_temp0';
  }

  @override
  String missingSongs(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          '$count titres de la sauvegarde ne sont pas sur cet appareil et ont été ignorés.',
      one:
          '1 titre de la sauvegarde n\'est pas sur cet appareil et a été ignoré.',
    );
    return '$_temp0';
  }

  @override
  String get ok => 'OK';

  @override
  String get internalStorage => 'Stockage interne';

  @override
  String get sdCard => 'Carte SD';

  @override
  String scanningFolder(Object folder) {
    return 'Analyse de $folder…';
  }

  @override
  String get foldersIntro =>
      'audifac analyse automatiquement tout votre téléphone et la carte SD. Décochez un dossier pour masquer son audio et l\'ignorer lors des analyses.';

  @override
  String get foldersWithAudio => 'Dossiers avec de l\'audio';

  @override
  String get noneFoundYet => 'Aucun pour l\'instant.';

  @override
  String get hiddenFolders => 'Dossiers masqués';

  @override
  String get hiddenFoldersIntro =>
      'Android masque certains dossiers et fichiers aux applications : les dossiers contenant un fichier « .nomedia » (comme les notes vocales WhatsApp), ainsi que les fichiers WavPack (.wv) et TTA, qu\'il ne reconnaît pas comme audio. Ajoutez leur dossier ici pour les inclure.';

  @override
  String get remove => 'Retirer';

  @override
  String get addFolder => 'Ajouter un dossier';

  @override
  String get rescanLibrary => 'Réanalyser la bibliothèque';

  @override
  String get playlistsTitle => 'Playlists';

  @override
  String songsOf(Object shown, num total) {
    String _temp0 = intl.Intl.pluralLogic(
      total,
      locale: localeName,
      other: '$total titres',
      one: '1 titre',
      zero: '0 titre',
    );
    return '$shown sur $_temp0';
  }

  @override
  String get noSongsMatch => 'Aucun titre ne correspond';

  @override
  String get noSongsMatchHint =>
      'Essayez une autre qualité, un autre codec ou une autre source.';

  @override
  String get clearFilters => 'Effacer les filtres';

  @override
  String get sort => 'Trier';

  @override
  String get shuffleAlbums => 'Albums en aléatoire';

  @override
  String get smartPlaylists => 'Playlists intelligentes';

  @override
  String get newLabel => 'Nouvelle';

  @override
  String get trackGain => 'Gain par titre';

  @override
  String get albumGain => 'Gain par album';

  @override
  String get smartGain => 'Auto (gain d\'album pour les albums entiers)';

  @override
  String get fromTags => 'balises ReplayGain';

  @override
  String measuredLufs(Object lufs) {
    return 'mesuré $lufs LUFS';
  }

  @override
  String get notAnalysedYetShort => 'pas encore analysé';

  @override
  String get volumeIntro =>
      'Lit chaque titre au même volume perçu (ReplayGain 2.0, −18 LUFS), d\'après ses balises ou une mesure EBU R128. Appliqué avant l\'égaliseur ; la dynamique est intacte.';

  @override
  String get volumeOffHint => 'Les titres sont lus à leur niveau de mastering.';

  @override
  String get volumeTrackHint =>
      'Chaque titre au même volume — idéal en aléatoire et pour les mix.';

  @override
  String get volumeAlbumHint =>
      'Les albums gardent leurs titres calmes et forts comme masterisés.';

  @override
  String get volumeSmartHint =>
      'Gain d\'album quand un album est lu dans l\'ordre, gain par titre sinon.';

  @override
  String nowLine(Object text) {
    return 'En cours : $text';
  }

  @override
  String get preamp => 'Pré-ampli';

  @override
  String get preampHint =>
      '−18 LUFS est plus calme que la plupart de la musique actuelle ; +3 à +6 dB est courant.';

  @override
  String get untaggedGain => 'Titres sans données de volume';

  @override
  String get untaggedGainHint =>
      'Utilisé tant qu\'un titre n\'est pas analysé, et pour les formats qui ne peuvent pas l\'être.';

  @override
  String get preventClipping => 'Éviter l\'écrêtage';

  @override
  String get preventClippingHint =>
      'Ne jamais monter un titre au-delà de son niveau crête';

  @override
  String songsWithTags(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count titres balisés',
      one: '1 titre balisé',
      zero: '0 titre balisé',
    );
    return '$_temp0';
  }

  @override
  String songsMeasured(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count titres mesurés',
      one: '1 titre mesuré',
      zero: '0 titre mesuré',
    );
    return '$_temp0';
  }

  @override
  String cantBeAnalysed(Object count) {
    return '$count non analysables';
  }

  @override
  String notAnalysedYet(Object count) {
    return '$count pas encore analysés';
  }

  @override
  String get upcomingAnalysed =>
      'Les prochains titres sont analysés automatiquement quand l\'égalisation du volume est active.';

  @override
  String analysingProgress(Object done, Object total) {
    return 'Analyse $done / $total…';
  }

  @override
  String get stop => 'Arrêter';

  @override
  String get wholeLibraryAnalysed => 'Toute la bibliothèque est analysée';

  @override
  String analyseNow(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Analyser $count titres maintenant',
      one: 'Analyser 1 titre maintenant',
      zero: 'Analyser 0 titre',
    );
    return '$_temp0';
  }

  @override
  String get nothingYet => 'Rien pour l\'instant';

  @override
  String get playCountRule =>
      'Un titre compte comme écouté une fois que vous en avez entendu la moitié (ou 4 minutes).';

  @override
  String get listening => 'd\'écoute';

  @override
  String playsWord(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'écoutes',
      one: 'écoute',
      zero: 'écoute',
    );
    return '$_temp0';
  }

  @override
  String daysWord(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'jours',
      one: 'jour',
      zero: 'jour',
    );
    return '$_temp0';
  }

  @override
  String get topSongs => 'Titres les plus écoutés';

  @override
  String get topArtists => 'Artistes les plus écoutés';

  @override
  String get topAlbums => 'Albums les plus écoutés';

  @override
  String smartCopyName(Object name) {
    return '$name (copie)';
  }

  @override
  String get smartOptions => 'Options de la playlist intelligente';

  @override
  String get editCopy => 'Modifier une copie';

  @override
  String get editRules => 'Modifier les règles';

  @override
  String get noMatchingSongs => 'Aucun titre correspondant';

  @override
  String get noMatchingSongsHint =>
      'Les titres apparaissent ici dès qu\'ils correspondent aux règles.';

  @override
  String get smartPlaylist => 'Playlist intelligente';

  @override
  String get save => 'Enregistrer';

  @override
  String get name => 'Nom';

  @override
  String get match => 'Correspondre à';

  @override
  String get allRules => 'Toutes les règles';

  @override
  String get anyRule => 'Une des règles';

  @override
  String get addRule => 'Ajouter une règle';

  @override
  String get order => 'Ordre';

  @override
  String get limit => 'Limite';

  @override
  String get none => 'Aucune';

  @override
  String get noSongsMatchYet => 'Aucun titre ne correspond pour l\'instant';

  @override
  String songsMatchNow(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count titres correspondent',
      one: '1 titre correspond',
      zero: '0 titre correspond',
    );
    return '$_temp0';
  }

  @override
  String get field => 'Champ';

  @override
  String get removeRule => 'Supprimer la règle';

  @override
  String get sleepTimer => 'Minuteur de sommeil';

  @override
  String get sleepHint => 'La musique s\'estompe, puis se met en pause.';

  @override
  String minutesShort(Object count) {
    return '$count min';
  }

  @override
  String get endOfSong => 'Fin de ce titre';

  @override
  String get endOfQueue => 'Fin de la file';

  @override
  String get turnOff => 'Désactiver';

  @override
  String stopsIn(Object time) {
    return 'Arrêt dans $time';
  }

  @override
  String get stopsAtSongEnd => 'Arrêt à la fin de ce titre';

  @override
  String get stopsAtQueueEnd => 'Arrêt à la fin de la file';

  @override
  String get songEnd => 'Fin du titre';

  @override
  String get queueEnd => 'Fin de la file';

  @override
  String get playbackSpeed => 'Vitesse de lecture';

  @override
  String get speed => 'Vitesse';

  @override
  String get speedHint =>
      'Pour les livres audio et podcasts ; les voix gardent leur hauteur. La musique est toujours lue à 1×.';

  @override
  String get chapters => 'Chapitres';

  @override
  String chapterN(Object n) {
    return 'Chapitre $n';
  }

  @override
  String get notALyricsFile =>
      'Ce n\'est pas un fichier de paroles (.lrc ou .txt)';

  @override
  String get lyrics => 'Paroles';

  @override
  String get lyricsOptions => 'Options des paroles';

  @override
  String get useLyricsFile => 'Utiliser un fichier de paroles (.lrc / .txt)…';

  @override
  String get removeAttachedFile => 'Retirer le fichier associé';

  @override
  String get noLyrics => 'Pas de paroles';

  @override
  String get noLyricsHint =>
      'Les paroles viennent des balises du titre ou d\'un fichier .lrc du même nom.';

  @override
  String get chooseLyricsFile => 'Choisir un fichier de paroles';

  @override
  String get close => 'Fermer';

  @override
  String get queue => 'File d\'attente';

  @override
  String get signalPathAndSpectrum => 'Chaîne audio et spectre';

  @override
  String get back15 => 'Reculer de 15 secondes';

  @override
  String get forward30 => 'Avancer de 30 secondes';

  @override
  String get repeat => 'Répéter';

  @override
  String get equalizerOff => 'Égaliseur désactivé';

  @override
  String get signal => 'Signal';

  @override
  String get meterLegend => 'Barre : RMS · trait : crête (dBFS)';

  @override
  String get signalPath => 'Chaîne audio';

  @override
  String volumeDb(Object db) {
    return 'volume $db';
  }

  @override
  String crossfadeSeconds(Object seconds) {
    return 'fondu de $seconds s';
  }

  @override
  String get decoded => 'Décodé';

  @override
  String get notThroughDsp => 'Lecture hors du DSP';

  @override
  String get bitTransparent =>
      'Bit-transparent (aucun traitement) → flottant 32 bits';

  @override
  String get processing => 'Traitement';

  @override
  String dspProcessing(Object what) {
    return '$what → flottant 32 bits, calcul 64 bits';
  }

  @override
  String get androidMixer => 'Mixeur Android';

  @override
  String noResampling(Object rate) {
    return '$rate — sans rééchantillonnage';
  }

  @override
  String resampled(Object from, Object to) {
    return 'Rééchantillonné $from → $to';
  }

  @override
  String get output => 'Sortie';

  @override
  String get phoneSpeaker => 'Haut-parleur du téléphone';

  @override
  String accepts(Object rates) {
    return 'accepte $rates';
  }

  @override
  String get mono => 'Mono';

  @override
  String get stereo => 'Stéréo';

  @override
  String channelsN(Object count) {
    return '$count canaux';
  }

  @override
  String get audio => 'Audio';

  @override
  String analysingSuffix(Object quality) {
    return '$quality (analyse…)';
  }

  @override
  String get container => 'Conteneur';

  @override
  String get bitrate => 'Débit';

  @override
  String get sampleRate => 'Fréquence d\'échantillonnage';

  @override
  String get bitDepth => 'Résolution';

  @override
  String get channels => 'Canaux';

  @override
  String get duration => 'Durée';

  @override
  String get tags => 'Balises';

  @override
  String get albumArtist => 'Artiste de l\'album';

  @override
  String get track => 'Piste';

  @override
  String get disc => 'Disque';

  @override
  String get composer => 'Compositeur';

  @override
  String get listeningSection => 'Écoute';

  @override
  String get playsLabel => 'Écoutes';

  @override
  String get listeningTime => 'Temps d\'écoute';

  @override
  String get loudness => 'Volume perçu';

  @override
  String replayGainTags(Object db) {
    return 'ReplayGain $db (balises)';
  }

  @override
  String get file => 'Fichier';

  @override
  String get size => 'Taille';

  @override
  String get modified => 'Modifié';

  @override
  String get indexedBy => 'Indexé par';

  @override
  String get indexedGranted => 'Dossier masqué (autorisé)';

  @override
  String get indexedScan => 'analyse du stockage audifac';

  @override
  String get indexedMediaStore => 'médiathèque Android';

  @override
  String get pathCopied => 'Chemin du fichier copié';

  @override
  String get copyPath => 'Copier le chemin';

  @override
  String get chooseSound => 'Choisir un son';

  @override
  String get soundPreset => 'Préréglage sonore';

  @override
  String get openEqualizer => 'Ouvrir l\'égaliseur';

  @override
  String get applyTo => 'Appliquer à';

  @override
  String everyTimePlays(Object what) {
    return 'À chaque écoute de « $what »';
  }

  @override
  String get yourPresets => 'Vos préréglages';

  @override
  String get builtIn => 'Intégrés';

  @override
  String correctionFor(Object device) {
    return 'Correction pour $device';
  }

  @override
  String get correctionHint =>
      'Utilisée automatiquement dès que l\'audio sort par cette sortie.';

  @override
  String get newCorrection => 'Nouvelle correction / importer AutoEQ';

  @override
  String get deletedPreset => 'Préréglage supprimé';

  @override
  String get rulesAndDevices => 'Règles et appareils';

  @override
  String get rulesIntro =>
      'La règle la plus précise l\'emporte : titre → album → artiste → genre → source → toute la musique. Choisir un préréglage « pour cette session » remplace les règles jusqu\'à la prochaine file.';

  @override
  String get allMusic => 'Toute la musique';

  @override
  String get defaultSoundPreset => 'Préréglage sonore par défaut';

  @override
  String get change => 'Changer';

  @override
  String get genres => 'Genres';

  @override
  String get sources => 'Sources';

  @override
  String get noRulesYet => 'Pas encore de règles';

  @override
  String get noRulesHint =>
      'Utilisez le menu d\'un titre → « Préréglage sonore… » pour choisir un préréglage pour ce titre, cet album, cet artiste ou ce genre.';

  @override
  String get devices => 'Appareils';

  @override
  String deviceNowPlaying(Object device) {
    return '$device · en cours';
  }

  @override
  String get thisSession => 'Cette session';

  @override
  String get blankGraphic => 'Graphique 10 bandes vierge';

  @override
  String get blankParametric => 'Paramétrique vierge';

  @override
  String get importAutoEqFile =>
      'Importer un fichier AutoEQ (ParametricEQ.txt)';

  @override
  String get pasteAutoEq => 'Coller un texte AutoEQ / Equalizer APO';

  @override
  String get myHeadphones => 'Mon casque';

  @override
  String get mySound => 'Mon son';

  @override
  String get imported => 'Importé';

  @override
  String get noAutoEqLines =>
      'Aucune ligne « Filter: ON PK Fc … Hz Gain … dB Q … » trouvée';

  @override
  String get nameThisPreset => 'Nommer ce préréglage';

  @override
  String get presetNameHint => 'Nom du préréglage';

  @override
  String get duplicatePreset => 'Dupliquer le préréglage';

  @override
  String myVersion(Object name) {
    return '$name (ma version)';
  }

  @override
  String get renamePreset => 'Renommer le préréglage';

  @override
  String get copiedAutoEq => 'Copié en texte AutoEQ / Equalizer APO';

  @override
  String nowDefault(Object name) {
    return '« $name » est maintenant le réglage par défaut';
  }

  @override
  String get deletePresetTitle => 'Supprimer le préréglage ?';

  @override
  String deletePresetBody(Object name) {
    return '« $name » et les règles qui l\'utilisent seront supprimés.';
  }

  @override
  String get eqOffHint =>
      'L\'égaliseur est désactivé — vous entendez le son d\'origine. Activez-le pour appliquer les préréglages ci-dessous.';

  @override
  String deviceLayer(Object device) {
    return 'Appareil · $device';
  }

  @override
  String get autoForOutput => 'auto pour cette sortie';

  @override
  String fromReason(Object reason) {
    return 'selon $reason';
  }

  @override
  String get curveLegendDevice =>
      'Gras : correction de l\'appareil · pâle : ce que vous entendez (les deux couches)';

  @override
  String get curveLegendSound =>
      'Gras : préréglage sonore · pâle : ce que vous entendez (les deux couches)';

  @override
  String get deviceCorrection => 'Correction de l\'appareil';

  @override
  String get graphic => 'Graphique';

  @override
  String get parametric => 'Paramétrique';

  @override
  String get presetOptions => 'Options du préréglage';

  @override
  String get builtInReadOnly =>
      'Les préréglages intégrés sont en lecture seule.';

  @override
  String get duplicateToEdit => 'Dupliquer pour modifier';

  @override
  String get gain => 'Gain';

  @override
  String get autoHeadroom => 'Marge automatique';

  @override
  String autoHeadroomHint(Object db) {
    return 'Baisse le volume de la plus forte accentuation pour ne jamais saturer · actuellement $db';
  }

  @override
  String get boostsExceed =>
      'Les accentuations dépassent 0 dB : le limiteur va agir. Baissez le pré-ampli ou activez la marge automatique.';

  @override
  String get crossfeed => 'Crossfeed';

  @override
  String get crossfeedHint =>
      'Casque : mélange un peu de chaque canal dans l\'autre, comme des enceintes dans une pièce.';

  @override
  String get balance => 'Balance';

  @override
  String get centre => 'Centre';

  @override
  String get behaviour => 'Comportement';

  @override
  String get askOnPlay => 'Demander au début de l\'écoute';

  @override
  String get askOnPlayHint =>
      'Proposer vos préréglages quand une file commence et qu\'aucune règle ne décide';

  @override
  String rulesDevicesCount(Object devices, Object rules) {
    return '$rules règles · $devices appareils';
  }

  @override
  String get newPresetImport => 'Nouveau préréglage / importer AutoEQ';

  @override
  String get originalSound => 'Son d\'origine (A)';

  @override
  String get holdToCompare => 'Maintenir pour comparer à l\'original';

  @override
  String get removeBand => 'Supprimer la bande';

  @override
  String get frequency => 'Fréquence';

  @override
  String get qWidth => 'Q (largeur)';

  @override
  String addBand(Object count, Object max) {
    return 'Ajouter une bande ($count/$max)';
  }

  @override
  String get curveTip =>
      'Astuce : faites glisser un point numéroté de la courbe ; pincez-le pour changer sa largeur.';

  @override
  String get duplicate => 'Dupliquer';

  @override
  String get copyAsAutoEq => 'Copier en texte AutoEQ';

  @override
  String get useForAllMusic => 'Utiliser pour toute la musique';

  @override
  String get forgetDevice => 'Oublier l\'appareil';

  @override
  String get offShort => 'Non';

  @override
  String get wiredHeadphones => 'Casque filaire';

  @override
  String get lastFmIntro =>
      'Envoie vos écoutes à Last.fm (la moitié d\'un titre ou 4 minutes compte). Utilise votre propre clé d\'API Last.fm — créez-en une gratuitement sur last.fm/api/account/create.';

  @override
  String lastFmConnectedAs(Object user) {
    return 'Connecté en tant que $user';
  }

  @override
  String get lastFmScrobble => 'Envoyer mes écoutes';

  @override
  String get lastFmAllSent => 'Tout est envoyé';

  @override
  String lastFmPending(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count écoutes en attente du réseau',
      one: '1 écoute en attente du réseau',
      zero: '0 écoute en attente du réseau',
    );
    return '$_temp0';
  }

  @override
  String get lastFmSendNow => 'Envoyer maintenant';

  @override
  String get lastFmDisconnect => 'Se déconnecter';

  @override
  String get lastFmKeyHint =>
      'Collez votre clé d\'API et votre secret partagé, puis connectez-vous une fois. Votre mot de passe n\'est pas enregistré.';

  @override
  String get lastFmApiKey => 'Clé d\'API';

  @override
  String get lastFmSecret => 'Secret partagé';

  @override
  String get lastFmUser => 'Nom d\'utilisateur Last.fm';

  @override
  String get lastFmPassword => 'Mot de passe';

  @override
  String get lastFmConnect => 'Se connecter';

  @override
  String get lastFmOff => 'Non connecté';

  @override
  String get castTitle => 'Lire sur…';

  @override
  String get castIntro =>
      'Téléviseurs, Chromecast et enceintes réseau sur ce Wi-Fi. L\'appareil lit le fichier d\'origine (l\'égaliseur et l\'égalisation du volume de l\'app ne s\'appliquent pas).';

  @override
  String castingTo(Object device) {
    return 'Lecture sur $device';
  }

  @override
  String get castingHint =>
      'Le téléphone reste en pause ; la file continue sur l\'appareil.';

  @override
  String get noCastDevices =>
      'Rien trouvé. Vérifiez que le téléviseur ou l\'enceinte est allumé et sur le même Wi-Fi.';

  @override
  String get searchAgain => 'Rechercher à nouveau';

  @override
  String get playOnPhone => 'Lire sur ce téléphone';

  @override
  String get previous => 'Précédent';

  @override
  String get cast => 'Lire sur un téléviseur ou une enceinte';

  @override
  String get iosAddMusic => 'Ajouter de la musique';

  @override
  String get iosFilesHint =>
      'Les titres téléchargés dans l\'app Musique apparaissent automatiquement. Pour ajouter vos propres fichiers (FLAC, WAV, ALAC…), copiez-les dans audifac avec l\'app Fichiers (Sur mon iPhone → audifac) ou depuis un ordinateur avec le partage de fichiers du Finder / d\'iTunes.';

  @override
  String get bitPerfect => 'Sortie USB bit-perfect';

  @override
  String get bitPerfectHint =>
      'Android 14+ avec un DAC USB : les échantillons du fichier arrivent intacts au DAC, à leur propre fréquence, dès que l\'égaliseur, l\'égalisation du volume et le fondu sont désactivés.';

  @override
  String get bitPerfectOn => 'Contourné — bit-perfect vers le DAC USB';

  @override
  String get hqResampler => 'Rééchantillonnage haute qualité';

  @override
  String get hqResamplerHint =>
      'Haut-parleur et prise casque : les titres sont convertis à la fréquence du mélangeur d\'Android par le rééchantillonneur d\'audifac (plus précis, phase linéaire) au lieu de celui d\'Android — et des titres de fréquences différentes s\'enchaînent sans blanc. À partir du titre suivant.';

  @override
  String resampledByAudifac(Object from, Object to) {
    return '$from → $to, phase linéaire';
  }

  @override
  String get levels => 'Niveaux';

  @override
  String peakDbfs(Object db) {
    return 'crête $db dBFS';
  }

  @override
  String limiterShare(Object percent) {
    return 'limiteur actif $percent % du temps';
  }

  @override
  String clippedCount(Object count) {
    return '$count échantillons saturés';
  }

  @override
  String get noClipping => 'aucune saturation';

  @override
  String get toAndroid => 'Vers Android';

  @override
  String get float32 => 'Flottant 32 bits';

  @override
  String get pcm16Dithered => '16 bits avec dither (vitesse modifiée)';

  @override
  String get tone => 'Tonalité';

  @override
  String get bass => 'Graves';

  @override
  String get treble => 'Aigus';

  @override
  String get tilt => 'Inclinaison';

  @override
  String get brighter => 'plus brillant';

  @override
  String get warmer => 'plus chaud';

  @override
  String get loudnessCompensation => 'Compensation physiologique';

  @override
  String get loudnessCompensationHint =>
      'À faible volume, l\'oreille perçoit moins les graves et les aigus : ils sont relevés à mesure que vous baissez le volume (courbes d\'isosonie), jamais à plein volume.';

  @override
  String loudnessBass(Object db) {
    return 'compensation $db graves';
  }

  @override
  String get stereoSection => 'Stéréo';

  @override
  String get width => 'Largeur';

  @override
  String get channelDelay => 'Retard de canal';

  @override
  String get channelDelayHint =>
      'Enceintes à des distances différentes : retardez la plus proche d\'environ 2,9 ms par mètre d\'écart.';

  @override
  String get invertLeft => 'Inverser la polarité gauche';

  @override
  String get invertRight => 'Inverser la polarité droite';

  @override
  String get resetTone => 'Réinitialiser la tonalité';

  @override
  String get resetStereo => 'Réinitialiser la stéréo';

  @override
  String get convolution => 'Convolution';

  @override
  String impulseResponseFor(Object device) {
    return 'Réponse impulsionnelle · $device';
  }

  @override
  String get irNone =>
      'Aucune. Chargez une correction de pièce ou de casque en WAV (mono, stéréo ou vraie stéréo) ; normalisée à 0 dB, utilisée pour cette sortie uniquement.';

  @override
  String get loadIr => 'Charger un WAV';

  @override
  String get removeIr => 'Retirer';

  @override
  String irLoaded(Object channels, Object name, Object seconds) {
    return '$name : $channels canaux, $seconds s';
  }

  @override
  String get irUnusable =>
      'Réponse impulsionnelle inutilisable (un WAV de 1, 2 ou 4 canaux)';

  @override
  String convolutionWith(Object name) {
    return 'RI $name';
  }

  @override
  String get linearPhase => 'Égaliseur à phase linéaire';

  @override
  String get linearPhaseHint =>
      'L\'égaliseur ne décale aucune phase : chaque fréquence garde son timing (un filtre de 8192 coefficients au lieu des filtres habituels). Ajoute environ 0,1 s de délai et consomme plus de batterie.';

  @override
  String get linearPhaseShort => 'phase linéaire';

  @override
  String get compressor => 'Compresseur';

  @override
  String get compressorLight => 'Léger';

  @override
  String get compressorMedium => 'Moyen';

  @override
  String get compressorStrong => 'Fort';

  @override
  String get compressorHint =>
      'Rapproche passages calmes et forts : pour les lieux bruyants ou l\'écoute de nuit. Désactivé, la dynamique de la musique reste intacte.';

  @override
  String compressorIs(Object strength) {
    return 'compresseur $strength';
  }

  @override
  String get findHeadphones => 'Trouver mon casque';

  @override
  String get findHeadphonesHint =>
      'Correction toute faite de la base AutoEQ (en ligne)';

  @override
  String get headphoneModelHint => 'Modèle, ex. HD 600, AirPods Pro';

  @override
  String autoEqIntro(Object count) {
    return '$count casques et écouteurs mesurés par des testeurs (oratory1990, crinacle…), chacun avec une correction vers la cible Harman. Tapez un modèle ; s\'il a été mesuré par plusieurs testeurs, choisissez-en un.';
  }

  @override
  String measuredBy(Object source) {
    return 'mesuré par $source';
  }

  @override
  String get autoEqOffline =>
      'Impossible de télécharger la base AutoEQ. Vérifiez votre connexion.';

  @override
  String get autoEqDownloadFailed =>
      'Impossible de télécharger cette correction';

  @override
  String get autoEqCredit =>
      'Données : projet AutoEQ de Jaakko Pasanen (github.com/jaakkopasanen/AutoEq)';

  @override
  String get downmix => 'Réduire le surround en stéréo';

  @override
  String get downmixHint =>
      'Les fichiers 5.1 et 7.1 sont d\'abord ramenés en stéréo (coefficients UIT), pour que l\'égaliseur, les outils stéréo et la convolution s\'appliquent à ce que vous entendez. Désactivé : Android reçoit tous les canaux.';
}
