import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_fr.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'generated/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('fr'),
  ];

  /// No description provided for @songs.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 song} other{{count} songs}}'**
  String songs(num count);

  /// No description provided for @albums.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 album} other{{count} albums}}'**
  String albums(num count);

  /// No description provided for @playlistsCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 playlist} other{{count} playlists}}'**
  String playlistsCount(num count);

  /// No description provided for @plays.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 play} other{{count} plays}}'**
  String plays(num count);

  /// No description provided for @folders.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 folder} other{{count} folders}}'**
  String folders(num count);

  /// No description provided for @files.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 file} other{{count} files}}'**
  String files(num count);

  /// No description provided for @eqPresets.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 EQ preset} other{{count} EQ presets}}'**
  String eqPresets(num count);

  /// No description provided for @rules.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 rule} other{{count} rules}}'**
  String rules(num count);

  /// No description provided for @newFavorites.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 new favorite} other{{count} new favorites}}'**
  String newFavorites(num count);

  /// No description provided for @favoritesCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 favorite} other{{count} favorites}}'**
  String favoritesCount(num count);

  /// No description provided for @listens.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 listen} other{{count} listens}}'**
  String listens(num count);

  /// No description provided for @historyEntries.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 history entry} other{{count} history entries}}'**
  String historyEntries(num count);

  /// No description provided for @goodNight.
  ///
  /// In en, this message translates to:
  /// **'Good night'**
  String get goodNight;

  /// No description provided for @goodMorning.
  ///
  /// In en, this message translates to:
  /// **'Good morning'**
  String get goodMorning;

  /// No description provided for @goodAfternoon.
  ///
  /// In en, this message translates to:
  /// **'Good afternoon'**
  String get goodAfternoon;

  /// No description provided for @goodEvening.
  ///
  /// In en, this message translates to:
  /// **'Good evening'**
  String get goodEvening;

  /// No description provided for @yourStats.
  ///
  /// In en, this message translates to:
  /// **'Your stats'**
  String get yourStats;

  /// No description provided for @settings.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settings;

  /// No description provided for @shuffleAll.
  ///
  /// In en, this message translates to:
  /// **'Shuffle all'**
  String get shuffleAll;

  /// No description provided for @favorites.
  ///
  /// In en, this message translates to:
  /// **'Favorites'**
  String get favorites;

  /// No description provided for @recentlyPlayed.
  ///
  /// In en, this message translates to:
  /// **'Recently played'**
  String get recentlyPlayed;

  /// No description provided for @recentlyAdded.
  ///
  /// In en, this message translates to:
  /// **'Recently added'**
  String get recentlyAdded;

  /// No description provided for @yourPlaylists.
  ///
  /// In en, this message translates to:
  /// **'Your playlists'**
  String get yourPlaylists;

  /// No description provided for @newPlaylist.
  ///
  /// In en, this message translates to:
  /// **'New playlist'**
  String get newPlaylist;

  /// No description provided for @create.
  ///
  /// In en, this message translates to:
  /// **'Create'**
  String get create;

  /// No description provided for @tabHome.
  ///
  /// In en, this message translates to:
  /// **'Home'**
  String get tabHome;

  /// No description provided for @tabLibrary.
  ///
  /// In en, this message translates to:
  /// **'Library'**
  String get tabLibrary;

  /// No description provided for @tabSearch.
  ///
  /// In en, this message translates to:
  /// **'Search'**
  String get tabSearch;

  /// No description provided for @couldNotPlayFile.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t play this file'**
  String get couldNotPlayFile;

  /// No description provided for @couldNotPlay.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t play \"{title}\" — skipped'**
  String couldNotPlay(Object title);

  /// No description provided for @back.
  ///
  /// In en, this message translates to:
  /// **'Back'**
  String get back;

  /// No description provided for @noFavoritesYet.
  ///
  /// In en, this message translates to:
  /// **'No favorites yet'**
  String get noFavoritesYet;

  /// No description provided for @noFavoritesHint.
  ///
  /// In en, this message translates to:
  /// **'Tap the heart in the player, or use a song\'s menu, to save it here.'**
  String get noFavoritesHint;

  /// No description provided for @play.
  ///
  /// In en, this message translates to:
  /// **'Play'**
  String get play;

  /// No description provided for @shuffle.
  ///
  /// In en, this message translates to:
  /// **'Shuffle'**
  String get shuffle;

  /// No description provided for @pause.
  ///
  /// In en, this message translates to:
  /// **'Pause'**
  String get pause;

  /// No description provided for @next.
  ///
  /// In en, this message translates to:
  /// **'Next'**
  String get next;

  /// No description provided for @more.
  ///
  /// In en, this message translates to:
  /// **'More'**
  String get more;

  /// No description provided for @nowPlaying.
  ///
  /// In en, this message translates to:
  /// **'Now playing'**
  String get nowPlaying;

  /// No description provided for @upNext.
  ///
  /// In en, this message translates to:
  /// **'Up next'**
  String get upNext;

  /// No description provided for @shuffled.
  ///
  /// In en, this message translates to:
  /// **'Shuffled'**
  String get shuffled;

  /// No description provided for @nothingQueued.
  ///
  /// In en, this message translates to:
  /// **'Nothing else queued.'**
  String get nothingQueued;

  /// No description provided for @all.
  ///
  /// In en, this message translates to:
  /// **'All'**
  String get all;

  /// No description provided for @looseFiles.
  ///
  /// In en, this message translates to:
  /// **'Loose files'**
  String get looseFiles;

  /// No description provided for @playCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{Play 1 song} other{Play {count} songs}}'**
  String playCount(num count);

  /// No description provided for @renamePlaylist.
  ///
  /// In en, this message translates to:
  /// **'Rename playlist'**
  String get renamePlaylist;

  /// No description provided for @rename.
  ///
  /// In en, this message translates to:
  /// **'Rename'**
  String get rename;

  /// No description provided for @deletePlaylistTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete playlist?'**
  String get deletePlaylistTitle;

  /// No description provided for @deletePlaylistBody.
  ///
  /// In en, this message translates to:
  /// **'\"{name}\" will be deleted. Your songs stay on the device.'**
  String deletePlaylistBody(Object name);

  /// No description provided for @cancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get cancel;

  /// No description provided for @delete.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get delete;

  /// No description provided for @playlistOptions.
  ///
  /// In en, this message translates to:
  /// **'Playlist options'**
  String get playlistOptions;

  /// No description provided for @emptyPlaylist.
  ///
  /// In en, this message translates to:
  /// **'Empty playlist'**
  String get emptyPlaylist;

  /// No description provided for @noSongsYet.
  ///
  /// In en, this message translates to:
  /// **'No songs yet'**
  String get noSongsYet;

  /// No description provided for @noSongsYetHint.
  ///
  /// In en, this message translates to:
  /// **'Use \"Add to playlist…\" from any song\'s menu.'**
  String get noSongsYetHint;

  /// No description provided for @removeFromPlaylist.
  ///
  /// In en, this message translates to:
  /// **'Remove from playlist'**
  String get removeFromPlaylist;

  /// No description provided for @searchHint.
  ///
  /// In en, this message translates to:
  /// **'Songs, albums, artists'**
  String get searchHint;

  /// No description provided for @findYourMusic.
  ///
  /// In en, this message translates to:
  /// **'Find your music'**
  String get findYourMusic;

  /// No description provided for @searchBy.
  ///
  /// In en, this message translates to:
  /// **'Search by song title, artist or album.'**
  String get searchBy;

  /// No description provided for @noResults.
  ///
  /// In en, this message translates to:
  /// **'No results'**
  String get noResults;

  /// No description provided for @nothingMatches.
  ///
  /// In en, this message translates to:
  /// **'Nothing matches \"{query}\".'**
  String nothingMatches(Object query);

  /// No description provided for @artists.
  ///
  /// In en, this message translates to:
  /// **'Artists'**
  String get artists;

  /// No description provided for @albumsTitle.
  ///
  /// In en, this message translates to:
  /// **'Albums'**
  String get albumsTitle;

  /// No description provided for @songsTitle.
  ///
  /// In en, this message translates to:
  /// **'Songs'**
  String get songsTitle;

  /// No description provided for @playNext.
  ///
  /// In en, this message translates to:
  /// **'Play next'**
  String get playNext;

  /// No description provided for @playingNext.
  ///
  /// In en, this message translates to:
  /// **'Playing \"{title}\" next'**
  String playingNext(Object title);

  /// No description provided for @addToQueue.
  ///
  /// In en, this message translates to:
  /// **'Add to queue'**
  String get addToQueue;

  /// No description provided for @addedToQueue.
  ///
  /// In en, this message translates to:
  /// **'Added to queue'**
  String get addedToQueue;

  /// No description provided for @addToPlaylistEllipsis.
  ///
  /// In en, this message translates to:
  /// **'Add to playlist…'**
  String get addToPlaylistEllipsis;

  /// No description provided for @addToPlaylist.
  ///
  /// In en, this message translates to:
  /// **'Add to playlist'**
  String get addToPlaylist;

  /// No description provided for @removeFromFavorites.
  ///
  /// In en, this message translates to:
  /// **'Remove from favorites'**
  String get removeFromFavorites;

  /// No description provided for @addToFavorites.
  ///
  /// In en, this message translates to:
  /// **'Add to favorites'**
  String get addToFavorites;

  /// No description provided for @addedToFavorites.
  ///
  /// In en, this message translates to:
  /// **'Added to favorites'**
  String get addedToFavorites;

  /// No description provided for @removedFromFavorites.
  ///
  /// In en, this message translates to:
  /// **'Removed from favorites'**
  String get removedFromFavorites;

  /// No description provided for @soundPresetEllipsis.
  ///
  /// In en, this message translates to:
  /// **'Sound preset…'**
  String get soundPresetEllipsis;

  /// No description provided for @songInfo.
  ///
  /// In en, this message translates to:
  /// **'Song info'**
  String get songInfo;

  /// No description provided for @goToAlbum.
  ///
  /// In en, this message translates to:
  /// **'Go to album'**
  String get goToAlbum;

  /// No description provided for @goToArtist.
  ///
  /// In en, this message translates to:
  /// **'Go to artist'**
  String get goToArtist;

  /// No description provided for @playlistName.
  ///
  /// In en, this message translates to:
  /// **'Playlist name'**
  String get playlistName;

  /// No description provided for @alreadyIn.
  ///
  /// In en, this message translates to:
  /// **'Already in \"{name}\"'**
  String alreadyIn(Object name);

  /// No description provided for @addedSongsTo.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{Added 1 song to \"{name}\"} other{Added {count} songs to \"{name}\"}}'**
  String addedSongsTo(num count, Object name);

  /// No description provided for @createdPlaylist.
  ///
  /// In en, this message translates to:
  /// **'Created \"{name}\"'**
  String createdPlaylist(Object name);

  /// No description provided for @couldNotReadMusic.
  ///
  /// In en, this message translates to:
  /// **'Could not read your music'**
  String get couldNotReadMusic;

  /// No description provided for @tryAgain.
  ///
  /// In en, this message translates to:
  /// **'Try again'**
  String get tryAgain;

  /// No description provided for @noAudioFound.
  ///
  /// In en, this message translates to:
  /// **'No audio found'**
  String get noAudioFound;

  /// No description provided for @noAudioFoundHint.
  ///
  /// In en, this message translates to:
  /// **'audifac looked through your whole phone and SD card. Copy some audio files to the device, then scan again.'**
  String get noAudioFoundHint;

  /// No description provided for @scanAgain.
  ///
  /// In en, this message translates to:
  /// **'Scan again'**
  String get scanAgain;

  /// No description provided for @everythingHidden.
  ///
  /// In en, this message translates to:
  /// **'Everything is hidden'**
  String get everythingHidden;

  /// No description provided for @everythingHiddenHint.
  ///
  /// In en, this message translates to:
  /// **'{count} audio files were found, but your library filters (minimum length, recordings, excluded folders) hide them all.'**
  String everythingHiddenHint(Object count);

  /// No description provided for @librarySettings.
  ///
  /// In en, this message translates to:
  /// **'Library settings'**
  String get librarySettings;

  /// No description provided for @allowAccessTitle.
  ///
  /// In en, this message translates to:
  /// **'Allow access to your music'**
  String get allowAccessTitle;

  /// No description provided for @accessTurnedOff.
  ///
  /// In en, this message translates to:
  /// **'Access was turned off. Enable \"Music and audio\" for audifac in system settings.'**
  String get accessTurnedOff;

  /// No description provided for @accessNeeded.
  ///
  /// In en, this message translates to:
  /// **'audifac needs permission to find the songs stored on this device.'**
  String get accessNeeded;

  /// No description provided for @openSettings.
  ///
  /// In en, this message translates to:
  /// **'Open settings'**
  String get openSettings;

  /// No description provided for @allowAccess.
  ///
  /// In en, this message translates to:
  /// **'Allow access'**
  String get allowAccess;

  /// No description provided for @searchingPhone.
  ///
  /// In en, this message translates to:
  /// **'Searching your phone for audio…'**
  String get searchingPhone;

  /// No description provided for @searchingPhoneHint.
  ///
  /// In en, this message translates to:
  /// **'Internal storage and SD card, every folder.'**
  String get searchingPhoneHint;

  /// No description provided for @sortTitle.
  ///
  /// In en, this message translates to:
  /// **'Title'**
  String get sortTitle;

  /// No description provided for @sortArtist.
  ///
  /// In en, this message translates to:
  /// **'Artist'**
  String get sortArtist;

  /// No description provided for @sortAlbum.
  ///
  /// In en, this message translates to:
  /// **'Album'**
  String get sortAlbum;

  /// No description provided for @sortRecentlyAdded.
  ///
  /// In en, this message translates to:
  /// **'Recently added'**
  String get sortRecentlyAdded;

  /// No description provided for @sortMostPlayed.
  ///
  /// In en, this message translates to:
  /// **'Most played'**
  String get sortMostPlayed;

  /// No description provided for @sortRandom.
  ///
  /// In en, this message translates to:
  /// **'Random'**
  String get sortRandom;

  /// No description provided for @qualityHiRes.
  ///
  /// In en, this message translates to:
  /// **'Hi-Res'**
  String get qualityHiRes;

  /// No description provided for @qualityLossless.
  ///
  /// In en, this message translates to:
  /// **'Lossless'**
  String get qualityLossless;

  /// No description provided for @qualityLossy.
  ///
  /// In en, this message translates to:
  /// **'Lossy'**
  String get qualityLossy;

  /// No description provided for @qualityUnknown.
  ///
  /// In en, this message translates to:
  /// **'Unknown'**
  String get qualityUnknown;

  /// No description provided for @sourceMusic.
  ///
  /// In en, this message translates to:
  /// **'Music'**
  String get sourceMusic;

  /// No description provided for @sourceDownloads.
  ///
  /// In en, this message translates to:
  /// **'Downloads'**
  String get sourceDownloads;

  /// No description provided for @sourceRecordings.
  ///
  /// In en, this message translates to:
  /// **'Recordings'**
  String get sourceRecordings;

  /// No description provided for @sourcePodcasts.
  ///
  /// In en, this message translates to:
  /// **'Podcasts'**
  String get sourcePodcasts;

  /// No description provided for @sourceAudiobooks.
  ///
  /// In en, this message translates to:
  /// **'Audiobooks'**
  String get sourceAudiobooks;

  /// No description provided for @sourceHidden.
  ///
  /// In en, this message translates to:
  /// **'Hidden folder'**
  String get sourceHidden;

  /// No description provided for @sourceOther.
  ///
  /// In en, this message translates to:
  /// **'Other'**
  String get sourceOther;

  /// No description provided for @off.
  ///
  /// In en, this message translates to:
  /// **'Off'**
  String get off;

  /// No description provided for @volumeTrack.
  ///
  /// In en, this message translates to:
  /// **'Track'**
  String get volumeTrack;

  /// No description provided for @volumeAlbum.
  ///
  /// In en, this message translates to:
  /// **'Album'**
  String get volumeAlbum;

  /// No description provided for @volumeSmart.
  ///
  /// In en, this message translates to:
  /// **'Smart'**
  String get volumeSmart;

  /// No description provided for @range7Days.
  ///
  /// In en, this message translates to:
  /// **'7 days'**
  String get range7Days;

  /// No description provided for @range30Days.
  ///
  /// In en, this message translates to:
  /// **'30 days'**
  String get range30Days;

  /// No description provided for @rangeYear.
  ///
  /// In en, this message translates to:
  /// **'Year'**
  String get rangeYear;

  /// No description provided for @rangeAllTime.
  ///
  /// In en, this message translates to:
  /// **'All time'**
  String get rangeAllTime;

  /// No description provided for @fieldTitle.
  ///
  /// In en, this message translates to:
  /// **'Title'**
  String get fieldTitle;

  /// No description provided for @fieldArtist.
  ///
  /// In en, this message translates to:
  /// **'Artist'**
  String get fieldArtist;

  /// No description provided for @fieldAlbum.
  ///
  /// In en, this message translates to:
  /// **'Album'**
  String get fieldAlbum;

  /// No description provided for @fieldGenre.
  ///
  /// In en, this message translates to:
  /// **'Genre'**
  String get fieldGenre;

  /// No description provided for @fieldFolder.
  ///
  /// In en, this message translates to:
  /// **'Folder'**
  String get fieldFolder;

  /// No description provided for @fieldQuality.
  ///
  /// In en, this message translates to:
  /// **'Quality'**
  String get fieldQuality;

  /// No description provided for @fieldCodec.
  ///
  /// In en, this message translates to:
  /// **'Codec'**
  String get fieldCodec;

  /// No description provided for @fieldSource.
  ///
  /// In en, this message translates to:
  /// **'Source'**
  String get fieldSource;

  /// No description provided for @fieldYear.
  ///
  /// In en, this message translates to:
  /// **'Year'**
  String get fieldYear;

  /// No description provided for @fieldLength.
  ///
  /// In en, this message translates to:
  /// **'Length (minutes)'**
  String get fieldLength;

  /// No description provided for @fieldPlays.
  ///
  /// In en, this message translates to:
  /// **'Play count'**
  String get fieldPlays;

  /// No description provided for @fieldAdded.
  ///
  /// In en, this message translates to:
  /// **'Added'**
  String get fieldAdded;

  /// No description provided for @fieldLastPlayed.
  ///
  /// In en, this message translates to:
  /// **'Last played'**
  String get fieldLastPlayed;

  /// No description provided for @fieldFavorite.
  ///
  /// In en, this message translates to:
  /// **'Favorite'**
  String get fieldFavorite;

  /// No description provided for @opContains.
  ///
  /// In en, this message translates to:
  /// **'contains'**
  String get opContains;

  /// No description provided for @opNotContains.
  ///
  /// In en, this message translates to:
  /// **'doesn\'t contain'**
  String get opNotContains;

  /// No description provided for @opIs.
  ///
  /// In en, this message translates to:
  /// **'is'**
  String get opIs;

  /// No description provided for @opIsNot.
  ///
  /// In en, this message translates to:
  /// **'is not'**
  String get opIsNot;

  /// No description provided for @opAtLeast.
  ///
  /// In en, this message translates to:
  /// **'at least'**
  String get opAtLeast;

  /// No description provided for @opAtMost.
  ///
  /// In en, this message translates to:
  /// **'at most'**
  String get opAtMost;

  /// No description provided for @opWithin.
  ///
  /// In en, this message translates to:
  /// **'in the last (days)'**
  String get opWithin;

  /// No description provided for @opNotWithin.
  ///
  /// In en, this message translates to:
  /// **'not in the last (days)'**
  String get opNotWithin;

  /// No description provided for @opNever.
  ///
  /// In en, this message translates to:
  /// **'Never'**
  String get opNever;

  /// No description provided for @yes.
  ///
  /// In en, this message translates to:
  /// **'Yes'**
  String get yes;

  /// No description provided for @no.
  ///
  /// In en, this message translates to:
  /// **'No'**
  String get no;

  /// No description provided for @ruleWithin.
  ///
  /// In en, this message translates to:
  /// **'{field} in the last {days} days'**
  String ruleWithin(Object days, Object field);

  /// No description provided for @ruleNotWithin.
  ///
  /// In en, this message translates to:
  /// **'{field} over {days} days ago'**
  String ruleNotWithin(Object days, Object field);

  /// No description provided for @ruleNot.
  ///
  /// In en, this message translates to:
  /// **'Not {field}'**
  String ruleNot(Object field);

  /// No description provided for @neverPlayed.
  ///
  /// In en, this message translates to:
  /// **'Never played'**
  String get neverPlayed;

  /// No description provided for @allSongs.
  ///
  /// In en, this message translates to:
  /// **'All songs'**
  String get allSongs;

  /// No description provided for @or.
  ///
  /// In en, this message translates to:
  /// **'or'**
  String get or;

  /// No description provided for @smartForgotten.
  ///
  /// In en, this message translates to:
  /// **'Not played in 30 days'**
  String get smartForgotten;

  /// No description provided for @smartAddedThisWeek.
  ///
  /// In en, this message translates to:
  /// **'Added this week'**
  String get smartAddedThisWeek;

  /// No description provided for @reasonSession.
  ///
  /// In en, this message translates to:
  /// **'this session'**
  String get reasonSession;

  /// No description provided for @reasonSong.
  ///
  /// In en, this message translates to:
  /// **'song'**
  String get reasonSong;

  /// No description provided for @reasonAlbum.
  ///
  /// In en, this message translates to:
  /// **'album'**
  String get reasonAlbum;

  /// No description provided for @reasonArtist.
  ///
  /// In en, this message translates to:
  /// **'artist'**
  String get reasonArtist;

  /// No description provided for @reasonGenre.
  ///
  /// In en, this message translates to:
  /// **'genre'**
  String get reasonGenre;

  /// No description provided for @reasonSource.
  ///
  /// In en, this message translates to:
  /// **'source'**
  String get reasonSource;

  /// No description provided for @reasonDefault.
  ///
  /// In en, this message translates to:
  /// **'default'**
  String get reasonDefault;

  /// No description provided for @thisSong.
  ///
  /// In en, this message translates to:
  /// **'This song'**
  String get thisSong;

  /// No description provided for @thisAlbum.
  ///
  /// In en, this message translates to:
  /// **'This album'**
  String get thisAlbum;

  /// No description provided for @thisArtist.
  ///
  /// In en, this message translates to:
  /// **'This artist'**
  String get thisArtist;

  /// No description provided for @thisGenre.
  ///
  /// In en, this message translates to:
  /// **'This genre'**
  String get thisGenre;

  /// No description provided for @thisSource.
  ///
  /// In en, this message translates to:
  /// **'This source'**
  String get thisSource;

  /// No description provided for @filterPeak.
  ///
  /// In en, this message translates to:
  /// **'Peak'**
  String get filterPeak;

  /// No description provided for @filterLowShelf.
  ///
  /// In en, this message translates to:
  /// **'Low shelf'**
  String get filterLowShelf;

  /// No description provided for @filterHighShelf.
  ///
  /// In en, this message translates to:
  /// **'High shelf'**
  String get filterHighShelf;

  /// No description provided for @filterLowPass.
  ///
  /// In en, this message translates to:
  /// **'Low-pass'**
  String get filterLowPass;

  /// No description provided for @filterHighPass.
  ///
  /// In en, this message translates to:
  /// **'High-pass'**
  String get filterHighPass;

  /// No description provided for @filterNotch.
  ///
  /// In en, this message translates to:
  /// **'Notch'**
  String get filterNotch;

  /// No description provided for @presetNoCorrection.
  ///
  /// In en, this message translates to:
  /// **'No correction'**
  String get presetNoCorrection;

  /// No description provided for @presetFlat.
  ///
  /// In en, this message translates to:
  /// **'Flat'**
  String get presetFlat;

  /// No description provided for @presetBassBoost.
  ///
  /// In en, this message translates to:
  /// **'Bass boost'**
  String get presetBassBoost;

  /// No description provided for @presetBassReducer.
  ///
  /// In en, this message translates to:
  /// **'Bass reducer'**
  String get presetBassReducer;

  /// No description provided for @presetTrebleBoost.
  ///
  /// In en, this message translates to:
  /// **'Treble boost'**
  String get presetTrebleBoost;

  /// No description provided for @presetTrebleReducer.
  ///
  /// In en, this message translates to:
  /// **'Treble reducer'**
  String get presetTrebleReducer;

  /// No description provided for @presetVocal.
  ///
  /// In en, this message translates to:
  /// **'Vocal'**
  String get presetVocal;

  /// No description provided for @presetClassical.
  ///
  /// In en, this message translates to:
  /// **'Classical'**
  String get presetClassical;

  /// No description provided for @presetElectronic.
  ///
  /// In en, this message translates to:
  /// **'Electronic'**
  String get presetElectronic;

  /// No description provided for @presetAcoustic.
  ///
  /// In en, this message translates to:
  /// **'Acoustic'**
  String get presetAcoustic;

  /// No description provided for @presetLoudness.
  ///
  /// In en, this message translates to:
  /// **'Loudness'**
  String get presetLoudness;

  /// No description provided for @presetLateNight.
  ///
  /// In en, this message translates to:
  /// **'Late night'**
  String get presetLateNight;

  /// No description provided for @presetSmallSpeakers.
  ///
  /// In en, this message translates to:
  /// **'Small speakers'**
  String get presetSmallSpeakers;

  /// No description provided for @presetSpoken.
  ///
  /// In en, this message translates to:
  /// **'Spoken word'**
  String get presetSpoken;

  /// No description provided for @scanningStorage.
  ///
  /// In en, this message translates to:
  /// **'Scanning internal storage and SD card…'**
  String get scanningStorage;

  /// No description provided for @shown.
  ///
  /// In en, this message translates to:
  /// **'{count} shown'**
  String shown(Object count);

  /// No description provided for @shownOfFound.
  ///
  /// In en, this message translates to:
  /// **'{shown} shown of {found} found'**
  String shownOfFound(Object found, Object shown);

  /// No description provided for @scannedIn.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 file on storage, scanned in {seconds} s} other{{count} files on storage, scanned in {seconds} s}}'**
  String scannedIn(num count, Object seconds);

  /// No description provided for @lastScanFailed.
  ///
  /// In en, this message translates to:
  /// **'Last scan failed: {error}'**
  String lastScanFailed(Object error);

  /// No description provided for @appearance.
  ///
  /// In en, this message translates to:
  /// **'Appearance'**
  String get appearance;

  /// No description provided for @themeSystem.
  ///
  /// In en, this message translates to:
  /// **'System'**
  String get themeSystem;

  /// No description provided for @themeLight.
  ///
  /// In en, this message translates to:
  /// **'Light'**
  String get themeLight;

  /// No description provided for @themeDark.
  ///
  /// In en, this message translates to:
  /// **'Dark'**
  String get themeDark;

  /// No description provided for @languageSystem.
  ///
  /// In en, this message translates to:
  /// **'Phone language'**
  String get languageSystem;

  /// No description provided for @sound.
  ///
  /// In en, this message translates to:
  /// **'Sound'**
  String get sound;

  /// No description provided for @equalizer.
  ///
  /// In en, this message translates to:
  /// **'Equalizer'**
  String get equalizer;

  /// No description provided for @equalizerOnSummary.
  ///
  /// In en, this message translates to:
  /// **'On · presets, headphone correction, rules'**
  String get equalizerOnSummary;

  /// No description provided for @volumeMatching.
  ///
  /// In en, this message translates to:
  /// **'Volume matching'**
  String get volumeMatching;

  /// No description provided for @crossfade.
  ///
  /// In en, this message translates to:
  /// **'Crossfade'**
  String get crossfade;

  /// No description provided for @seconds.
  ///
  /// In en, this message translates to:
  /// **'{count} s'**
  String seconds(Object count);

  /// No description provided for @crossfadeOffHint.
  ///
  /// In en, this message translates to:
  /// **'Off: songs play gaplessly, exactly as mastered.'**
  String get crossfadeOffHint;

  /// No description provided for @crossfadeOnHint.
  ///
  /// In en, this message translates to:
  /// **'Songs blend into each other — except tracks of the same album, which stay gapless.'**
  String get crossfadeOnHint;

  /// No description provided for @keepAlbumsTogether.
  ///
  /// In en, this message translates to:
  /// **'Keep albums together when shuffling'**
  String get keepAlbumsTogether;

  /// No description provided for @keepAlbumsTogetherHint.
  ///
  /// In en, this message translates to:
  /// **'Shuffles whole albums; each plays in order'**
  String get keepAlbumsTogetherHint;

  /// No description provided for @scanDevice.
  ///
  /// In en, this message translates to:
  /// **'Scan device for audio'**
  String get scanDevice;

  /// No description provided for @foldersTitle.
  ///
  /// In en, this message translates to:
  /// **'Folders'**
  String get foldersTitle;

  /// No description provided for @allFoldersIncluded.
  ///
  /// In en, this message translates to:
  /// **'All folders included'**
  String get allFoldersIncluded;

  /// No description provided for @foldersExcluded.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 folder excluded} other{{count} folders excluded}}'**
  String foldersExcluded(num count);

  /// No description provided for @showLabels.
  ///
  /// In en, this message translates to:
  /// **'Show labels on songs'**
  String get showLabels;

  /// No description provided for @showLabelsAnalysing.
  ///
  /// In en, this message translates to:
  /// **'Source & codec · analysing audio {done} / {total}…'**
  String showLabelsAnalysing(Object done, Object total);

  /// No description provided for @showLabelsHint.
  ///
  /// In en, this message translates to:
  /// **'Source folder & codec (e.g. Downloads · FLAC 24/96)'**
  String get showLabelsHint;

  /// No description provided for @showRecordings.
  ///
  /// In en, this message translates to:
  /// **'Show recordings & voice notes'**
  String get showRecordings;

  /// No description provided for @showRecordingsHint.
  ///
  /// In en, this message translates to:
  /// **'Voice recorder, call recordings, WhatsApp voice notes'**
  String get showRecordingsHint;

  /// No description provided for @hideShorterThan.
  ///
  /// In en, this message translates to:
  /// **'Hide audio shorter than'**
  String get hideShorterThan;

  /// No description provided for @ringtonesHidden.
  ///
  /// In en, this message translates to:
  /// **'Ringtones, alarms and notification sounds are always hidden.'**
  String get ringtonesHidden;

  /// No description provided for @addWidget.
  ///
  /// In en, this message translates to:
  /// **'Add player widget to home screen'**
  String get addWidget;

  /// No description provided for @addWidgetManually.
  ///
  /// In en, this message translates to:
  /// **'Long-press your home screen → Widgets → audifac'**
  String get addWidgetManually;

  /// No description provided for @backup.
  ///
  /// In en, this message translates to:
  /// **'Backup'**
  String get backup;

  /// No description provided for @backUpToFile.
  ///
  /// In en, this message translates to:
  /// **'Back up to a file'**
  String get backUpToFile;

  /// No description provided for @backUpHint.
  ///
  /// In en, this message translates to:
  /// **'Favorites, playlists, history & play counts, EQ, settings'**
  String get backUpHint;

  /// No description provided for @restoreFromFile.
  ///
  /// In en, this message translates to:
  /// **'Restore from a file'**
  String get restoreFromFile;

  /// No description provided for @restoreHint.
  ///
  /// In en, this message translates to:
  /// **'Merges with what you have — nothing is deleted'**
  String get restoreHint;

  /// No description provided for @about.
  ///
  /// In en, this message translates to:
  /// **'About'**
  String get about;

  /// No description provided for @aboutAudifac.
  ///
  /// In en, this message translates to:
  /// **'About audifac'**
  String get aboutAudifac;

  /// No description provided for @backedUp.
  ///
  /// In en, this message translates to:
  /// **'Backed up {favorites}, {playlists}, {presets}'**
  String backedUp(Object favorites, Object playlists, Object presets);

  /// No description provided for @backupFailed.
  ///
  /// In en, this message translates to:
  /// **'Backup failed: {error}'**
  String backupFailed(Object error);

  /// No description provided for @cantRestore.
  ///
  /// In en, this message translates to:
  /// **'Can\'t restore: {reason}'**
  String cantRestore(Object reason);

  /// No description provided for @restored.
  ///
  /// In en, this message translates to:
  /// **'Restored'**
  String get restored;

  /// No description provided for @fromBackupOf.
  ///
  /// In en, this message translates to:
  /// **'From a backup of {date} (audifac {version}):'**
  String fromBackupOf(Object date, Object version);

  /// No description provided for @listensRestored.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 listen (play counts & stats)} other{{count} listens (play counts & stats)}}'**
  String listensRestored(num count);

  /// No description provided for @missingSongs.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 song from the backup isn\'t on this device and was skipped.} other{{count} songs from the backup aren\'t on this device and were skipped.}}'**
  String missingSongs(num count);

  /// No description provided for @ok.
  ///
  /// In en, this message translates to:
  /// **'OK'**
  String get ok;

  /// No description provided for @internalStorage.
  ///
  /// In en, this message translates to:
  /// **'Internal storage'**
  String get internalStorage;

  /// No description provided for @sdCard.
  ///
  /// In en, this message translates to:
  /// **'SD card'**
  String get sdCard;

  /// No description provided for @scanningFolder.
  ///
  /// In en, this message translates to:
  /// **'Scanning {folder}…'**
  String scanningFolder(Object folder);

  /// No description provided for @foldersIntro.
  ///
  /// In en, this message translates to:
  /// **'audifac scans your whole phone and SD card automatically. Untick a folder to hide its audio and skip it when scanning.'**
  String get foldersIntro;

  /// No description provided for @foldersWithAudio.
  ///
  /// In en, this message translates to:
  /// **'Folders with audio'**
  String get foldersWithAudio;

  /// No description provided for @noneFoundYet.
  ///
  /// In en, this message translates to:
  /// **'None found yet.'**
  String get noneFoundYet;

  /// No description provided for @hiddenFolders.
  ///
  /// In en, this message translates to:
  /// **'Hidden folders'**
  String get hiddenFolders;

  /// No description provided for @hiddenFoldersIntro.
  ///
  /// In en, this message translates to:
  /// **'Android hides some folders and files from apps: folders with a \".nomedia\" file (like WhatsApp voice notes), and WavPack (.wv) and TTA files, which it doesn\'t recognise as audio. Add their folder here to include them.'**
  String get hiddenFoldersIntro;

  /// No description provided for @remove.
  ///
  /// In en, this message translates to:
  /// **'Remove'**
  String get remove;

  /// No description provided for @addFolder.
  ///
  /// In en, this message translates to:
  /// **'Add a folder'**
  String get addFolder;

  /// No description provided for @rescanLibrary.
  ///
  /// In en, this message translates to:
  /// **'Rescan library'**
  String get rescanLibrary;

  /// No description provided for @playlistsTitle.
  ///
  /// In en, this message translates to:
  /// **'Playlists'**
  String get playlistsTitle;

  /// No description provided for @songsOf.
  ///
  /// In en, this message translates to:
  /// **'{shown} of {total, plural, =1{1 song} other{{total} songs}}'**
  String songsOf(Object shown, num total);

  /// No description provided for @noSongsMatch.
  ///
  /// In en, this message translates to:
  /// **'No songs match'**
  String get noSongsMatch;

  /// No description provided for @noSongsMatchHint.
  ///
  /// In en, this message translates to:
  /// **'Try another quality, codec or source.'**
  String get noSongsMatchHint;

  /// No description provided for @clearFilters.
  ///
  /// In en, this message translates to:
  /// **'Clear filters'**
  String get clearFilters;

  /// No description provided for @sort.
  ///
  /// In en, this message translates to:
  /// **'Sort'**
  String get sort;

  /// No description provided for @shuffleAlbums.
  ///
  /// In en, this message translates to:
  /// **'Shuffle albums'**
  String get shuffleAlbums;

  /// No description provided for @smartPlaylists.
  ///
  /// In en, this message translates to:
  /// **'Smart playlists'**
  String get smartPlaylists;

  /// No description provided for @newLabel.
  ///
  /// In en, this message translates to:
  /// **'New'**
  String get newLabel;

  /// No description provided for @trackGain.
  ///
  /// In en, this message translates to:
  /// **'Track gain'**
  String get trackGain;

  /// No description provided for @albumGain.
  ///
  /// In en, this message translates to:
  /// **'Album gain'**
  String get albumGain;

  /// No description provided for @smartGain.
  ///
  /// In en, this message translates to:
  /// **'Smart (album gain for whole albums)'**
  String get smartGain;

  /// No description provided for @fromTags.
  ///
  /// In en, this message translates to:
  /// **'ReplayGain tags'**
  String get fromTags;

  /// No description provided for @measuredLufs.
  ///
  /// In en, this message translates to:
  /// **'measured {lufs} LUFS'**
  String measuredLufs(Object lufs);

  /// No description provided for @notAnalysedYetShort.
  ///
  /// In en, this message translates to:
  /// **'not analysed yet'**
  String get notAnalysedYetShort;

  /// No description provided for @volumeIntro.
  ///
  /// In en, this message translates to:
  /// **'Plays every song at the same loudness (ReplayGain 2.0, −18 LUFS), from its tags or an EBU R128 measurement. Applied before the equalizer; dynamics are untouched.'**
  String get volumeIntro;

  /// No description provided for @volumeOffHint.
  ///
  /// In en, this message translates to:
  /// **'Songs play at their mastered level.'**
  String get volumeOffHint;

  /// No description provided for @volumeTrackHint.
  ///
  /// In en, this message translates to:
  /// **'Every song at the same loudness — best for shuffle and mixes.'**
  String get volumeTrackHint;

  /// No description provided for @volumeAlbumHint.
  ///
  /// In en, this message translates to:
  /// **'Albums keep their quiet and loud songs as mastered.'**
  String get volumeAlbumHint;

  /// No description provided for @volumeSmartHint.
  ///
  /// In en, this message translates to:
  /// **'Album gain while one album plays in order, track gain otherwise.'**
  String get volumeSmartHint;

  /// No description provided for @nowLine.
  ///
  /// In en, this message translates to:
  /// **'Now: {text}'**
  String nowLine(Object text);

  /// No description provided for @preamp.
  ///
  /// In en, this message translates to:
  /// **'Pre-amp'**
  String get preamp;

  /// No description provided for @preampHint.
  ///
  /// In en, this message translates to:
  /// **'−18 LUFS is quieter than most modern music; +3 to +6 dB is common.'**
  String get preampHint;

  /// No description provided for @untaggedGain.
  ///
  /// In en, this message translates to:
  /// **'Songs without loudness data'**
  String get untaggedGain;

  /// No description provided for @untaggedGainHint.
  ///
  /// In en, this message translates to:
  /// **'Used until a song is analysed, and for formats that can\'t be.'**
  String get untaggedGainHint;

  /// No description provided for @preventClipping.
  ///
  /// In en, this message translates to:
  /// **'Prevent clipping'**
  String get preventClipping;

  /// No description provided for @preventClippingHint.
  ///
  /// In en, this message translates to:
  /// **'Never raise a song above its peak level'**
  String get preventClippingHint;

  /// No description provided for @songsWithTags.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 song with tags} other{{count} songs with tags}}'**
  String songsWithTags(num count);

  /// No description provided for @songsMeasured.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 song measured} other{{count} songs measured}}'**
  String songsMeasured(num count);

  /// No description provided for @cantBeAnalysed.
  ///
  /// In en, this message translates to:
  /// **'{count} can\'t be analysed'**
  String cantBeAnalysed(Object count);

  /// No description provided for @notAnalysedYet.
  ///
  /// In en, this message translates to:
  /// **'{count} not analysed yet'**
  String notAnalysedYet(Object count);

  /// No description provided for @upcomingAnalysed.
  ///
  /// In en, this message translates to:
  /// **'Upcoming songs are analysed automatically while volume matching is on.'**
  String get upcomingAnalysed;

  /// No description provided for @analysingProgress.
  ///
  /// In en, this message translates to:
  /// **'Analysing {done} / {total}…'**
  String analysingProgress(Object done, Object total);

  /// No description provided for @stop.
  ///
  /// In en, this message translates to:
  /// **'Stop'**
  String get stop;

  /// No description provided for @wholeLibraryAnalysed.
  ///
  /// In en, this message translates to:
  /// **'Whole library analysed'**
  String get wholeLibraryAnalysed;

  /// No description provided for @analyseNow.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{Analyse 1 song now} other{Analyse {count} songs now}}'**
  String analyseNow(num count);

  /// No description provided for @nothingYet.
  ///
  /// In en, this message translates to:
  /// **'Nothing yet'**
  String get nothingYet;

  /// No description provided for @playCountRule.
  ///
  /// In en, this message translates to:
  /// **'A song counts as played once you\'ve heard half of it (or 4 minutes).'**
  String get playCountRule;

  /// No description provided for @listening.
  ///
  /// In en, this message translates to:
  /// **'listening'**
  String get listening;

  /// No description provided for @playsWord.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{play} other{plays}}'**
  String playsWord(num count);

  /// No description provided for @daysWord.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{day} other{days}}'**
  String daysWord(num count);

  /// No description provided for @topSongs.
  ///
  /// In en, this message translates to:
  /// **'Top songs'**
  String get topSongs;

  /// No description provided for @topArtists.
  ///
  /// In en, this message translates to:
  /// **'Top artists'**
  String get topArtists;

  /// No description provided for @topAlbums.
  ///
  /// In en, this message translates to:
  /// **'Top albums'**
  String get topAlbums;

  /// No description provided for @smartCopyName.
  ///
  /// In en, this message translates to:
  /// **'{name} (mine)'**
  String smartCopyName(Object name);

  /// No description provided for @smartOptions.
  ///
  /// In en, this message translates to:
  /// **'Smart playlist options'**
  String get smartOptions;

  /// No description provided for @editCopy.
  ///
  /// In en, this message translates to:
  /// **'Edit a copy'**
  String get editCopy;

  /// No description provided for @editRules.
  ///
  /// In en, this message translates to:
  /// **'Edit rules'**
  String get editRules;

  /// No description provided for @noMatchingSongs.
  ///
  /// In en, this message translates to:
  /// **'No matching songs'**
  String get noMatchingSongs;

  /// No description provided for @noMatchingSongsHint.
  ///
  /// In en, this message translates to:
  /// **'Songs appear here as soon as they match the rules.'**
  String get noMatchingSongsHint;

  /// No description provided for @smartPlaylist.
  ///
  /// In en, this message translates to:
  /// **'Smart playlist'**
  String get smartPlaylist;

  /// No description provided for @save.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get save;

  /// No description provided for @name.
  ///
  /// In en, this message translates to:
  /// **'Name'**
  String get name;

  /// No description provided for @match.
  ///
  /// In en, this message translates to:
  /// **'Match'**
  String get match;

  /// No description provided for @allRules.
  ///
  /// In en, this message translates to:
  /// **'All rules'**
  String get allRules;

  /// No description provided for @anyRule.
  ///
  /// In en, this message translates to:
  /// **'Any rule'**
  String get anyRule;

  /// No description provided for @addRule.
  ///
  /// In en, this message translates to:
  /// **'Add rule'**
  String get addRule;

  /// No description provided for @order.
  ///
  /// In en, this message translates to:
  /// **'Order'**
  String get order;

  /// No description provided for @limit.
  ///
  /// In en, this message translates to:
  /// **'Limit'**
  String get limit;

  /// No description provided for @none.
  ///
  /// In en, this message translates to:
  /// **'None'**
  String get none;

  /// No description provided for @noSongsMatchYet.
  ///
  /// In en, this message translates to:
  /// **'No songs match yet'**
  String get noSongsMatchYet;

  /// No description provided for @songsMatchNow.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 song matches right now} other{{count} songs match right now}}'**
  String songsMatchNow(num count);

  /// No description provided for @field.
  ///
  /// In en, this message translates to:
  /// **'Field'**
  String get field;

  /// No description provided for @removeRule.
  ///
  /// In en, this message translates to:
  /// **'Remove rule'**
  String get removeRule;

  /// No description provided for @sleepTimer.
  ///
  /// In en, this message translates to:
  /// **'Sleep timer'**
  String get sleepTimer;

  /// No description provided for @sleepHint.
  ///
  /// In en, this message translates to:
  /// **'Music fades out, then pauses.'**
  String get sleepHint;

  /// No description provided for @minutesShort.
  ///
  /// In en, this message translates to:
  /// **'{count} min'**
  String minutesShort(Object count);

  /// No description provided for @endOfSong.
  ///
  /// In en, this message translates to:
  /// **'End of this song'**
  String get endOfSong;

  /// No description provided for @endOfQueue.
  ///
  /// In en, this message translates to:
  /// **'End of the queue'**
  String get endOfQueue;

  /// No description provided for @turnOff.
  ///
  /// In en, this message translates to:
  /// **'Turn off'**
  String get turnOff;

  /// No description provided for @stopsIn.
  ///
  /// In en, this message translates to:
  /// **'Stops in {time}'**
  String stopsIn(Object time);

  /// No description provided for @stopsAtSongEnd.
  ///
  /// In en, this message translates to:
  /// **'Stops at the end of this song'**
  String get stopsAtSongEnd;

  /// No description provided for @stopsAtQueueEnd.
  ///
  /// In en, this message translates to:
  /// **'Stops at the end of the queue'**
  String get stopsAtQueueEnd;

  /// No description provided for @songEnd.
  ///
  /// In en, this message translates to:
  /// **'Song end'**
  String get songEnd;

  /// No description provided for @queueEnd.
  ///
  /// In en, this message translates to:
  /// **'Queue end'**
  String get queueEnd;

  /// No description provided for @playbackSpeed.
  ///
  /// In en, this message translates to:
  /// **'Playback speed'**
  String get playbackSpeed;

  /// No description provided for @speed.
  ///
  /// In en, this message translates to:
  /// **'Speed'**
  String get speed;

  /// No description provided for @speedHint.
  ///
  /// In en, this message translates to:
  /// **'For audiobooks & podcasts; voices keep their pitch. Music always plays at 1×.'**
  String get speedHint;

  /// No description provided for @chapters.
  ///
  /// In en, this message translates to:
  /// **'Chapters'**
  String get chapters;

  /// No description provided for @chapterN.
  ///
  /// In en, this message translates to:
  /// **'Chapter {n}'**
  String chapterN(Object n);

  /// No description provided for @notALyricsFile.
  ///
  /// In en, this message translates to:
  /// **'That isn\'t a lyrics file (.lrc or .txt)'**
  String get notALyricsFile;

  /// No description provided for @lyrics.
  ///
  /// In en, this message translates to:
  /// **'Lyrics'**
  String get lyrics;

  /// No description provided for @lyricsOptions.
  ///
  /// In en, this message translates to:
  /// **'Lyrics options'**
  String get lyricsOptions;

  /// No description provided for @useLyricsFile.
  ///
  /// In en, this message translates to:
  /// **'Use a lyrics file (.lrc / .txt)…'**
  String get useLyricsFile;

  /// No description provided for @removeAttachedFile.
  ///
  /// In en, this message translates to:
  /// **'Remove the attached file'**
  String get removeAttachedFile;

  /// No description provided for @noLyrics.
  ///
  /// In en, this message translates to:
  /// **'No lyrics'**
  String get noLyrics;

  /// No description provided for @noLyricsHint.
  ///
  /// In en, this message translates to:
  /// **'Lyrics come from the song\'s tags or an .lrc file with the same name.'**
  String get noLyricsHint;

  /// No description provided for @chooseLyricsFile.
  ///
  /// In en, this message translates to:
  /// **'Choose a lyrics file'**
  String get chooseLyricsFile;

  /// No description provided for @close.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get close;

  /// No description provided for @queue.
  ///
  /// In en, this message translates to:
  /// **'Queue'**
  String get queue;

  /// No description provided for @signalPathAndSpectrum.
  ///
  /// In en, this message translates to:
  /// **'Signal path and spectrum'**
  String get signalPathAndSpectrum;

  /// No description provided for @back15.
  ///
  /// In en, this message translates to:
  /// **'Back 15 seconds'**
  String get back15;

  /// No description provided for @forward30.
  ///
  /// In en, this message translates to:
  /// **'Forward 30 seconds'**
  String get forward30;

  /// No description provided for @repeat.
  ///
  /// In en, this message translates to:
  /// **'Repeat'**
  String get repeat;

  /// No description provided for @equalizerOff.
  ///
  /// In en, this message translates to:
  /// **'Equalizer off'**
  String get equalizerOff;

  /// No description provided for @signal.
  ///
  /// In en, this message translates to:
  /// **'Signal'**
  String get signal;

  /// No description provided for @meterLegend.
  ///
  /// In en, this message translates to:
  /// **'Bar: RMS · line: peak (dBFS)'**
  String get meterLegend;

  /// No description provided for @signalPath.
  ///
  /// In en, this message translates to:
  /// **'Signal path'**
  String get signalPath;

  /// No description provided for @volumeDb.
  ///
  /// In en, this message translates to:
  /// **'volume {db}'**
  String volumeDb(Object db);

  /// No description provided for @crossfadeSeconds.
  ///
  /// In en, this message translates to:
  /// **'{seconds} s crossfade'**
  String crossfadeSeconds(Object seconds);

  /// No description provided for @decoded.
  ///
  /// In en, this message translates to:
  /// **'Decoded'**
  String get decoded;

  /// No description provided for @notThroughDsp.
  ///
  /// In en, this message translates to:
  /// **'Not playing through the DSP'**
  String get notThroughDsp;

  /// No description provided for @bitTransparent.
  ///
  /// In en, this message translates to:
  /// **'Bit-transparent (no processing) → 32-bit float'**
  String get bitTransparent;

  /// No description provided for @processing.
  ///
  /// In en, this message translates to:
  /// **'Processing'**
  String get processing;

  /// No description provided for @dspProcessing.
  ///
  /// In en, this message translates to:
  /// **'{what} → 32-bit float, 64-bit math'**
  String dspProcessing(Object what);

  /// No description provided for @androidMixer.
  ///
  /// In en, this message translates to:
  /// **'Android mixer'**
  String get androidMixer;

  /// No description provided for @noResampling.
  ///
  /// In en, this message translates to:
  /// **'{rate} — no resampling'**
  String noResampling(Object rate);

  /// No description provided for @resampled.
  ///
  /// In en, this message translates to:
  /// **'Resampled {from} → {to}'**
  String resampled(Object from, Object to);

  /// No description provided for @output.
  ///
  /// In en, this message translates to:
  /// **'Output'**
  String get output;

  /// No description provided for @phoneSpeaker.
  ///
  /// In en, this message translates to:
  /// **'Phone speaker'**
  String get phoneSpeaker;

  /// No description provided for @accepts.
  ///
  /// In en, this message translates to:
  /// **'accepts {rates}'**
  String accepts(Object rates);

  /// No description provided for @mono.
  ///
  /// In en, this message translates to:
  /// **'Mono'**
  String get mono;

  /// No description provided for @stereo.
  ///
  /// In en, this message translates to:
  /// **'Stereo'**
  String get stereo;

  /// No description provided for @channelsN.
  ///
  /// In en, this message translates to:
  /// **'{count} channels'**
  String channelsN(Object count);

  /// No description provided for @audio.
  ///
  /// In en, this message translates to:
  /// **'Audio'**
  String get audio;

  /// No description provided for @analysingSuffix.
  ///
  /// In en, this message translates to:
  /// **'{quality} (analysing…)'**
  String analysingSuffix(Object quality);

  /// No description provided for @container.
  ///
  /// In en, this message translates to:
  /// **'Container'**
  String get container;

  /// No description provided for @bitrate.
  ///
  /// In en, this message translates to:
  /// **'Bitrate'**
  String get bitrate;

  /// No description provided for @sampleRate.
  ///
  /// In en, this message translates to:
  /// **'Sample rate'**
  String get sampleRate;

  /// No description provided for @bitDepth.
  ///
  /// In en, this message translates to:
  /// **'Bit depth'**
  String get bitDepth;

  /// No description provided for @channels.
  ///
  /// In en, this message translates to:
  /// **'Channels'**
  String get channels;

  /// No description provided for @duration.
  ///
  /// In en, this message translates to:
  /// **'Duration'**
  String get duration;

  /// No description provided for @tags.
  ///
  /// In en, this message translates to:
  /// **'Tags'**
  String get tags;

  /// No description provided for @albumArtist.
  ///
  /// In en, this message translates to:
  /// **'Album artist'**
  String get albumArtist;

  /// No description provided for @track.
  ///
  /// In en, this message translates to:
  /// **'Track'**
  String get track;

  /// No description provided for @disc.
  ///
  /// In en, this message translates to:
  /// **'Disc'**
  String get disc;

  /// No description provided for @composer.
  ///
  /// In en, this message translates to:
  /// **'Composer'**
  String get composer;

  /// No description provided for @listeningSection.
  ///
  /// In en, this message translates to:
  /// **'Listening'**
  String get listeningSection;

  /// No description provided for @playsLabel.
  ///
  /// In en, this message translates to:
  /// **'Plays'**
  String get playsLabel;

  /// No description provided for @listeningTime.
  ///
  /// In en, this message translates to:
  /// **'Listening time'**
  String get listeningTime;

  /// No description provided for @loudness.
  ///
  /// In en, this message translates to:
  /// **'Loudness'**
  String get loudness;

  /// No description provided for @replayGainTags.
  ///
  /// In en, this message translates to:
  /// **'ReplayGain {db} (tags)'**
  String replayGainTags(Object db);

  /// No description provided for @file.
  ///
  /// In en, this message translates to:
  /// **'File'**
  String get file;

  /// No description provided for @size.
  ///
  /// In en, this message translates to:
  /// **'Size'**
  String get size;

  /// No description provided for @modified.
  ///
  /// In en, this message translates to:
  /// **'Modified'**
  String get modified;

  /// No description provided for @indexedBy.
  ///
  /// In en, this message translates to:
  /// **'Indexed by'**
  String get indexedBy;

  /// No description provided for @indexedGranted.
  ///
  /// In en, this message translates to:
  /// **'Hidden folder (granted)'**
  String get indexedGranted;

  /// No description provided for @indexedScan.
  ///
  /// In en, this message translates to:
  /// **'audifac storage scan'**
  String get indexedScan;

  /// No description provided for @indexedMediaStore.
  ///
  /// In en, this message translates to:
  /// **'Android media library'**
  String get indexedMediaStore;

  /// No description provided for @pathCopied.
  ///
  /// In en, this message translates to:
  /// **'File path copied'**
  String get pathCopied;

  /// No description provided for @copyPath.
  ///
  /// In en, this message translates to:
  /// **'Copy path'**
  String get copyPath;

  /// No description provided for @chooseSound.
  ///
  /// In en, this message translates to:
  /// **'Choose a sound'**
  String get chooseSound;

  /// No description provided for @soundPreset.
  ///
  /// In en, this message translates to:
  /// **'Sound preset'**
  String get soundPreset;

  /// No description provided for @openEqualizer.
  ///
  /// In en, this message translates to:
  /// **'Open equalizer'**
  String get openEqualizer;

  /// No description provided for @applyTo.
  ///
  /// In en, this message translates to:
  /// **'Apply to'**
  String get applyTo;

  /// No description provided for @everyTimePlays.
  ///
  /// In en, this message translates to:
  /// **'Every time \"{what}\" plays'**
  String everyTimePlays(Object what);

  /// No description provided for @yourPresets.
  ///
  /// In en, this message translates to:
  /// **'Your presets'**
  String get yourPresets;

  /// No description provided for @builtIn.
  ///
  /// In en, this message translates to:
  /// **'Built-in'**
  String get builtIn;

  /// No description provided for @correctionFor.
  ///
  /// In en, this message translates to:
  /// **'Correction for {device}'**
  String correctionFor(Object device);

  /// No description provided for @correctionHint.
  ///
  /// In en, this message translates to:
  /// **'Used automatically whenever audio plays on this output.'**
  String get correctionHint;

  /// No description provided for @newCorrection.
  ///
  /// In en, this message translates to:
  /// **'New correction / import AutoEQ'**
  String get newCorrection;

  /// No description provided for @deletedPreset.
  ///
  /// In en, this message translates to:
  /// **'Deleted preset'**
  String get deletedPreset;

  /// No description provided for @rulesAndDevices.
  ///
  /// In en, this message translates to:
  /// **'Rules & devices'**
  String get rulesAndDevices;

  /// No description provided for @rulesIntro.
  ///
  /// In en, this message translates to:
  /// **'The most specific rule wins: song → album → artist → genre → source → all music. Choosing a preset \"for this session\" overrides rules until you start a new queue.'**
  String get rulesIntro;

  /// No description provided for @allMusic.
  ///
  /// In en, this message translates to:
  /// **'All music'**
  String get allMusic;

  /// No description provided for @defaultSoundPreset.
  ///
  /// In en, this message translates to:
  /// **'Default sound preset'**
  String get defaultSoundPreset;

  /// No description provided for @change.
  ///
  /// In en, this message translates to:
  /// **'Change'**
  String get change;

  /// No description provided for @genres.
  ///
  /// In en, this message translates to:
  /// **'Genres'**
  String get genres;

  /// No description provided for @sources.
  ///
  /// In en, this message translates to:
  /// **'Sources'**
  String get sources;

  /// No description provided for @noRulesYet.
  ///
  /// In en, this message translates to:
  /// **'No rules yet'**
  String get noRulesYet;

  /// No description provided for @noRulesHint.
  ///
  /// In en, this message translates to:
  /// **'Use a song\'s menu → \"Sound preset…\" to pick a preset for that song, album, artist or genre.'**
  String get noRulesHint;

  /// No description provided for @devices.
  ///
  /// In en, this message translates to:
  /// **'Devices'**
  String get devices;

  /// No description provided for @deviceNowPlaying.
  ///
  /// In en, this message translates to:
  /// **'{device} · now playing'**
  String deviceNowPlaying(Object device);

  /// No description provided for @thisSession.
  ///
  /// In en, this message translates to:
  /// **'This session'**
  String get thisSession;

  /// No description provided for @blankGraphic.
  ///
  /// In en, this message translates to:
  /// **'Blank 10-band graphic'**
  String get blankGraphic;

  /// No description provided for @blankParametric.
  ///
  /// In en, this message translates to:
  /// **'Blank parametric'**
  String get blankParametric;

  /// No description provided for @importAutoEqFile.
  ///
  /// In en, this message translates to:
  /// **'Import AutoEQ file (ParametricEQ.txt)'**
  String get importAutoEqFile;

  /// No description provided for @pasteAutoEq.
  ///
  /// In en, this message translates to:
  /// **'Paste AutoEQ / Equalizer APO text'**
  String get pasteAutoEq;

  /// No description provided for @myHeadphones.
  ///
  /// In en, this message translates to:
  /// **'My headphones'**
  String get myHeadphones;

  /// No description provided for @mySound.
  ///
  /// In en, this message translates to:
  /// **'My sound'**
  String get mySound;

  /// No description provided for @imported.
  ///
  /// In en, this message translates to:
  /// **'Imported'**
  String get imported;

  /// No description provided for @noAutoEqLines.
  ///
  /// In en, this message translates to:
  /// **'No \"Filter: ON PK Fc … Hz Gain … dB Q …\" lines found'**
  String get noAutoEqLines;

  /// No description provided for @nameThisPreset.
  ///
  /// In en, this message translates to:
  /// **'Name this preset'**
  String get nameThisPreset;

  /// No description provided for @presetNameHint.
  ///
  /// In en, this message translates to:
  /// **'Preset name'**
  String get presetNameHint;

  /// No description provided for @duplicatePreset.
  ///
  /// In en, this message translates to:
  /// **'Duplicate preset'**
  String get duplicatePreset;

  /// No description provided for @myVersion.
  ///
  /// In en, this message translates to:
  /// **'{name} (my version)'**
  String myVersion(Object name);

  /// No description provided for @renamePreset.
  ///
  /// In en, this message translates to:
  /// **'Rename preset'**
  String get renamePreset;

  /// No description provided for @copiedAutoEq.
  ///
  /// In en, this message translates to:
  /// **'Copied as AutoEQ / Equalizer APO text'**
  String get copiedAutoEq;

  /// No description provided for @nowDefault.
  ///
  /// In en, this message translates to:
  /// **'\"{name}\" is now the default for all music'**
  String nowDefault(Object name);

  /// No description provided for @deletePresetTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete preset?'**
  String get deletePresetTitle;

  /// No description provided for @deletePresetBody.
  ///
  /// In en, this message translates to:
  /// **'\"{name}\" and any rules using it will be removed.'**
  String deletePresetBody(Object name);

  /// No description provided for @eqOffHint.
  ///
  /// In en, this message translates to:
  /// **'The equalizer is off — you hear the original sound. Turn it on to apply the presets below.'**
  String get eqOffHint;

  /// No description provided for @deviceLayer.
  ///
  /// In en, this message translates to:
  /// **'Device · {device}'**
  String deviceLayer(Object device);

  /// No description provided for @autoForOutput.
  ///
  /// In en, this message translates to:
  /// **'auto for this output'**
  String get autoForOutput;

  /// No description provided for @fromReason.
  ///
  /// In en, this message translates to:
  /// **'from {reason}'**
  String fromReason(Object reason);

  /// No description provided for @curveLegendDevice.
  ///
  /// In en, this message translates to:
  /// **'Bold: device correction · faint: what you hear (both layers)'**
  String get curveLegendDevice;

  /// No description provided for @curveLegendSound.
  ///
  /// In en, this message translates to:
  /// **'Bold: sound preset · faint: what you hear (both layers)'**
  String get curveLegendSound;

  /// No description provided for @deviceCorrection.
  ///
  /// In en, this message translates to:
  /// **'Device correction'**
  String get deviceCorrection;

  /// No description provided for @graphic.
  ///
  /// In en, this message translates to:
  /// **'Graphic'**
  String get graphic;

  /// No description provided for @parametric.
  ///
  /// In en, this message translates to:
  /// **'Parametric'**
  String get parametric;

  /// No description provided for @presetOptions.
  ///
  /// In en, this message translates to:
  /// **'Preset options'**
  String get presetOptions;

  /// No description provided for @builtInReadOnly.
  ///
  /// In en, this message translates to:
  /// **'Built-in presets are read-only.'**
  String get builtInReadOnly;

  /// No description provided for @duplicateToEdit.
  ///
  /// In en, this message translates to:
  /// **'Duplicate to edit'**
  String get duplicateToEdit;

  /// No description provided for @gain.
  ///
  /// In en, this message translates to:
  /// **'Gain'**
  String get gain;

  /// No description provided for @autoHeadroom.
  ///
  /// In en, this message translates to:
  /// **'Automatic headroom'**
  String get autoHeadroom;

  /// No description provided for @autoHeadroomHint.
  ///
  /// In en, this message translates to:
  /// **'Lowers the volume by the biggest boost so it never distorts · now {db}'**
  String autoHeadroomHint(Object db);

  /// No description provided for @boostsExceed.
  ///
  /// In en, this message translates to:
  /// **'Boosts exceed 0 dB: the limiter will engage. Lower the preamp or turn on automatic headroom.'**
  String get boostsExceed;

  /// No description provided for @crossfeed.
  ///
  /// In en, this message translates to:
  /// **'Crossfeed'**
  String get crossfeed;

  /// No description provided for @crossfeedHint.
  ///
  /// In en, this message translates to:
  /// **'Headphones: blends a little of each channel into the other, like speakers in a room.'**
  String get crossfeedHint;

  /// No description provided for @balance.
  ///
  /// In en, this message translates to:
  /// **'Balance'**
  String get balance;

  /// No description provided for @centre.
  ///
  /// In en, this message translates to:
  /// **'Centre'**
  String get centre;

  /// No description provided for @behaviour.
  ///
  /// In en, this message translates to:
  /// **'Behaviour'**
  String get behaviour;

  /// No description provided for @askOnPlay.
  ///
  /// In en, this message translates to:
  /// **'Ask when I start listening'**
  String get askOnPlay;

  /// No description provided for @askOnPlayHint.
  ///
  /// In en, this message translates to:
  /// **'Offer your presets when a new queue starts and no rule decides'**
  String get askOnPlayHint;

  /// No description provided for @rulesDevicesCount.
  ///
  /// In en, this message translates to:
  /// **'{rules} rules · {devices} devices'**
  String rulesDevicesCount(Object devices, Object rules);

  /// No description provided for @newPresetImport.
  ///
  /// In en, this message translates to:
  /// **'New preset / import AutoEQ'**
  String get newPresetImport;

  /// No description provided for @originalSound.
  ///
  /// In en, this message translates to:
  /// **'Original sound (A)'**
  String get originalSound;

  /// No description provided for @holdToCompare.
  ///
  /// In en, this message translates to:
  /// **'Hold to compare with original'**
  String get holdToCompare;

  /// No description provided for @removeBand.
  ///
  /// In en, this message translates to:
  /// **'Remove band'**
  String get removeBand;

  /// No description provided for @frequency.
  ///
  /// In en, this message translates to:
  /// **'Frequency'**
  String get frequency;

  /// No description provided for @qWidth.
  ///
  /// In en, this message translates to:
  /// **'Q (width)'**
  String get qWidth;

  /// No description provided for @addBand.
  ///
  /// In en, this message translates to:
  /// **'Add band ({count}/{max})'**
  String addBand(Object count, Object max);

  /// No description provided for @curveTip.
  ///
  /// In en, this message translates to:
  /// **'Tip: drag a numbered point on the curve; pinch it to change its width.'**
  String get curveTip;

  /// No description provided for @duplicate.
  ///
  /// In en, this message translates to:
  /// **'Duplicate'**
  String get duplicate;

  /// No description provided for @copyAsAutoEq.
  ///
  /// In en, this message translates to:
  /// **'Copy as AutoEQ text'**
  String get copyAsAutoEq;

  /// No description provided for @useForAllMusic.
  ///
  /// In en, this message translates to:
  /// **'Use for all music'**
  String get useForAllMusic;

  /// No description provided for @forgetDevice.
  ///
  /// In en, this message translates to:
  /// **'Forget device'**
  String get forgetDevice;

  /// No description provided for @offShort.
  ///
  /// In en, this message translates to:
  /// **'Off'**
  String get offShort;

  /// No description provided for @wiredHeadphones.
  ///
  /// In en, this message translates to:
  /// **'Wired headphones'**
  String get wiredHeadphones;

  /// No description provided for @lastFmIntro.
  ///
  /// In en, this message translates to:
  /// **'Scrobbles what you listen to (half a song or 4 minutes counts). Uses your own Last.fm API key — create one free at last.fm/api/account/create.'**
  String get lastFmIntro;

  /// No description provided for @lastFmConnectedAs.
  ///
  /// In en, this message translates to:
  /// **'Connected as {user}'**
  String lastFmConnectedAs(Object user);

  /// No description provided for @lastFmScrobble.
  ///
  /// In en, this message translates to:
  /// **'Scrobble my listening'**
  String get lastFmScrobble;

  /// No description provided for @lastFmAllSent.
  ///
  /// In en, this message translates to:
  /// **'Everything sent'**
  String get lastFmAllSent;

  /// No description provided for @lastFmPending.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 scrobble waiting for the network} other{{count} scrobbles waiting for the network}}'**
  String lastFmPending(num count);

  /// No description provided for @lastFmSendNow.
  ///
  /// In en, this message translates to:
  /// **'Send now'**
  String get lastFmSendNow;

  /// No description provided for @lastFmDisconnect.
  ///
  /// In en, this message translates to:
  /// **'Disconnect'**
  String get lastFmDisconnect;

  /// No description provided for @lastFmKeyHint.
  ///
  /// In en, this message translates to:
  /// **'Paste your API key and shared secret, then log in once. Your password isn\'t stored.'**
  String get lastFmKeyHint;

  /// No description provided for @lastFmApiKey.
  ///
  /// In en, this message translates to:
  /// **'API key'**
  String get lastFmApiKey;

  /// No description provided for @lastFmSecret.
  ///
  /// In en, this message translates to:
  /// **'Shared secret'**
  String get lastFmSecret;

  /// No description provided for @lastFmUser.
  ///
  /// In en, this message translates to:
  /// **'Last.fm username'**
  String get lastFmUser;

  /// No description provided for @lastFmPassword.
  ///
  /// In en, this message translates to:
  /// **'Password'**
  String get lastFmPassword;

  /// No description provided for @lastFmConnect.
  ///
  /// In en, this message translates to:
  /// **'Connect'**
  String get lastFmConnect;

  /// No description provided for @lastFmOff.
  ///
  /// In en, this message translates to:
  /// **'Not connected'**
  String get lastFmOff;

  /// No description provided for @castTitle.
  ///
  /// In en, this message translates to:
  /// **'Play on…'**
  String get castTitle;

  /// No description provided for @castIntro.
  ///
  /// In en, this message translates to:
  /// **'TVs, Chromecasts and network speakers on this Wi-Fi. The device plays the original file (the app\'s EQ and volume matching don\'t apply).'**
  String get castIntro;

  /// No description provided for @castingTo.
  ///
  /// In en, this message translates to:
  /// **'Playing on {device}'**
  String castingTo(Object device);

  /// No description provided for @castingHint.
  ///
  /// In en, this message translates to:
  /// **'The phone stays paused; the queue continues on the device.'**
  String get castingHint;

  /// No description provided for @noCastDevices.
  ///
  /// In en, this message translates to:
  /// **'Nothing found. Check that the TV or speaker is on and on the same Wi-Fi.'**
  String get noCastDevices;

  /// No description provided for @searchAgain.
  ///
  /// In en, this message translates to:
  /// **'Search again'**
  String get searchAgain;

  /// No description provided for @playOnPhone.
  ///
  /// In en, this message translates to:
  /// **'Play on this phone'**
  String get playOnPhone;

  /// No description provided for @previous.
  ///
  /// In en, this message translates to:
  /// **'Previous'**
  String get previous;

  /// No description provided for @cast.
  ///
  /// In en, this message translates to:
  /// **'Play on a TV or speaker'**
  String get cast;

  /// No description provided for @iosAddMusic.
  ///
  /// In en, this message translates to:
  /// **'Adding music'**
  String get iosAddMusic;

  /// No description provided for @iosFilesHint.
  ///
  /// In en, this message translates to:
  /// **'Songs downloaded in the Apple Music app appear automatically. To add your own files (FLAC, WAV, ALAC…), copy them into audifac with the Files app (On My iPhone → audifac) or from a computer with Finder / iTunes file sharing.'**
  String get iosFilesHint;

  /// No description provided for @bitPerfect.
  ///
  /// In en, this message translates to:
  /// **'Bit-perfect USB output'**
  String get bitPerfect;

  /// No description provided for @bitPerfectHint.
  ///
  /// In en, this message translates to:
  /// **'Android 14+ with a USB DAC: the file\'s samples reach the DAC untouched, at their own rate, whenever the EQ, volume matching and crossfade are off.'**
  String get bitPerfectHint;

  /// No description provided for @bitPerfectOn.
  ///
  /// In en, this message translates to:
  /// **'Bypassed — bit-perfect to the USB DAC'**
  String get bitPerfectOn;

  /// No description provided for @hqResampler.
  ///
  /// In en, this message translates to:
  /// **'High-quality resampling'**
  String get hqResampler;

  /// No description provided for @hqResamplerHint.
  ///
  /// In en, this message translates to:
  /// **'Phone speaker and headphone jack: songs are converted to the rate Android mixes at by audifac\'s own resampler (sharper, linear phase) instead of Android\'s — and songs of different rates follow each other without a gap. From the next song.'**
  String get hqResamplerHint;

  /// No description provided for @resampledByAudifac.
  ///
  /// In en, this message translates to:
  /// **'{from} → {to}, linear phase'**
  String resampledByAudifac(Object from, Object to);

  /// No description provided for @levels.
  ///
  /// In en, this message translates to:
  /// **'Levels'**
  String get levels;

  /// No description provided for @peakDbfs.
  ///
  /// In en, this message translates to:
  /// **'peak {db} dBFS'**
  String peakDbfs(Object db);

  /// No description provided for @limiterShare.
  ///
  /// In en, this message translates to:
  /// **'limiter working {percent} % of the time'**
  String limiterShare(Object percent);

  /// No description provided for @clippedCount.
  ///
  /// In en, this message translates to:
  /// **'{count} clipped samples'**
  String clippedCount(Object count);

  /// No description provided for @noClipping.
  ///
  /// In en, this message translates to:
  /// **'no clipping'**
  String get noClipping;

  /// No description provided for @toAndroid.
  ///
  /// In en, this message translates to:
  /// **'To Android'**
  String get toAndroid;

  /// No description provided for @float32.
  ///
  /// In en, this message translates to:
  /// **'32-bit float'**
  String get float32;

  /// No description provided for @pcm16Dithered.
  ///
  /// In en, this message translates to:
  /// **'16-bit, dithered (speed changed)'**
  String get pcm16Dithered;

  /// No description provided for @tone.
  ///
  /// In en, this message translates to:
  /// **'Tone'**
  String get tone;

  /// No description provided for @bass.
  ///
  /// In en, this message translates to:
  /// **'Bass'**
  String get bass;

  /// No description provided for @treble.
  ///
  /// In en, this message translates to:
  /// **'Treble'**
  String get treble;

  /// No description provided for @tilt.
  ///
  /// In en, this message translates to:
  /// **'Tilt'**
  String get tilt;

  /// No description provided for @brighter.
  ///
  /// In en, this message translates to:
  /// **'brighter'**
  String get brighter;

  /// No description provided for @warmer.
  ///
  /// In en, this message translates to:
  /// **'warmer'**
  String get warmer;

  /// No description provided for @loudnessCompensation.
  ///
  /// In en, this message translates to:
  /// **'Loudness compensation'**
  String get loudnessCompensation;

  /// No description provided for @loudnessCompensationHint.
  ///
  /// In en, this message translates to:
  /// **'At low volume the ear hears less bass and treble: they are raised as you turn the volume down (equal-loudness curves), never at full volume.'**
  String get loudnessCompensationHint;

  /// No description provided for @loudnessBass.
  ///
  /// In en, this message translates to:
  /// **'loudness {db} bass'**
  String loudnessBass(Object db);

  /// No description provided for @stereoSection.
  ///
  /// In en, this message translates to:
  /// **'Stereo'**
  String get stereoSection;

  /// No description provided for @width.
  ///
  /// In en, this message translates to:
  /// **'Width'**
  String get width;

  /// No description provided for @channelDelay.
  ///
  /// In en, this message translates to:
  /// **'Channel delay'**
  String get channelDelay;

  /// No description provided for @channelDelayHint.
  ///
  /// In en, this message translates to:
  /// **'Speakers at different distances: delay the nearer one by about 2.9 ms per metre of difference.'**
  String get channelDelayHint;

  /// No description provided for @invertLeft.
  ///
  /// In en, this message translates to:
  /// **'Invert left polarity'**
  String get invertLeft;

  /// No description provided for @invertRight.
  ///
  /// In en, this message translates to:
  /// **'Invert right polarity'**
  String get invertRight;

  /// No description provided for @resetTone.
  ///
  /// In en, this message translates to:
  /// **'Reset tone'**
  String get resetTone;

  /// No description provided for @resetStereo.
  ///
  /// In en, this message translates to:
  /// **'Reset stereo'**
  String get resetStereo;

  /// No description provided for @convolution.
  ///
  /// In en, this message translates to:
  /// **'Convolution'**
  String get convolution;

  /// No description provided for @impulseResponseFor.
  ///
  /// In en, this message translates to:
  /// **'Impulse response · {device}'**
  String impulseResponseFor(Object device);

  /// No description provided for @irNone.
  ///
  /// In en, this message translates to:
  /// **'None. Load a WAV room or headphone correction (mono, stereo or true stereo); it\'s normalised to 0 dB and used for this output only.'**
  String get irNone;

  /// No description provided for @loadIr.
  ///
  /// In en, this message translates to:
  /// **'Load WAV'**
  String get loadIr;

  /// No description provided for @removeIr.
  ///
  /// In en, this message translates to:
  /// **'Remove'**
  String get removeIr;

  /// No description provided for @irLoaded.
  ///
  /// In en, this message translates to:
  /// **'{name}: {channels} ch, {seconds} s'**
  String irLoaded(Object channels, Object name, Object seconds);

  /// No description provided for @irUnusable.
  ///
  /// In en, this message translates to:
  /// **'Not a usable impulse response (a WAV with 1, 2 or 4 channels)'**
  String get irUnusable;

  /// No description provided for @convolutionWith.
  ///
  /// In en, this message translates to:
  /// **'IR {name}'**
  String convolutionWith(Object name);

  /// No description provided for @linearPhase.
  ///
  /// In en, this message translates to:
  /// **'Linear-phase EQ'**
  String get linearPhase;

  /// No description provided for @linearPhaseHint.
  ///
  /// In en, this message translates to:
  /// **'The EQ shifts no phase: every frequency keeps its timing (an 8192-tap filter instead of the usual ones). Adds about 0.1 s of delay and uses more battery.'**
  String get linearPhaseHint;

  /// No description provided for @linearPhaseShort.
  ///
  /// In en, this message translates to:
  /// **'linear phase'**
  String get linearPhaseShort;

  /// No description provided for @compressor.
  ///
  /// In en, this message translates to:
  /// **'Compressor'**
  String get compressor;

  /// No description provided for @compressorLight.
  ///
  /// In en, this message translates to:
  /// **'Light'**
  String get compressorLight;

  /// No description provided for @compressorMedium.
  ///
  /// In en, this message translates to:
  /// **'Medium'**
  String get compressorMedium;

  /// No description provided for @compressorStrong.
  ///
  /// In en, this message translates to:
  /// **'Strong'**
  String get compressorStrong;

  /// No description provided for @compressorHint.
  ///
  /// In en, this message translates to:
  /// **'Brings quiet and loud passages closer: for noisy places or night listening. Off keeps the music\'s dynamics intact.'**
  String get compressorHint;

  /// No description provided for @compressorIs.
  ///
  /// In en, this message translates to:
  /// **'compressor {strength}'**
  String compressorIs(Object strength);

  /// No description provided for @findHeadphones.
  ///
  /// In en, this message translates to:
  /// **'Find my headphones'**
  String get findHeadphones;

  /// No description provided for @findHeadphonesHint.
  ///
  /// In en, this message translates to:
  /// **'Ready-made correction from the AutoEQ database (online)'**
  String get findHeadphonesHint;

  /// No description provided for @headphoneModelHint.
  ///
  /// In en, this message translates to:
  /// **'Model, e.g. HD 600, AirPods Pro'**
  String get headphoneModelHint;

  /// No description provided for @autoEqIntro.
  ///
  /// In en, this message translates to:
  /// **'{count} headphones and earphones measured by reviewers (oratory1990, crinacle…), each with a correction to the Harman target. Type a model; when several reviewers measured it, pick one.'**
  String autoEqIntro(Object count);

  /// No description provided for @measuredBy.
  ///
  /// In en, this message translates to:
  /// **'measured by {source}'**
  String measuredBy(Object source);

  /// No description provided for @autoEqOffline.
  ///
  /// In en, this message translates to:
  /// **'The AutoEQ database couldn\'t be downloaded. Check your connection.'**
  String get autoEqOffline;

  /// No description provided for @autoEqDownloadFailed.
  ///
  /// In en, this message translates to:
  /// **'This correction couldn\'t be downloaded'**
  String get autoEqDownloadFailed;

  /// No description provided for @autoEqCredit.
  ///
  /// In en, this message translates to:
  /// **'Data: AutoEQ project by Jaakko Pasanen (github.com/jaakkopasanen/AutoEq)'**
  String get autoEqCredit;

  /// No description provided for @downmix.
  ///
  /// In en, this message translates to:
  /// **'Downmix surround to stereo'**
  String get downmix;

  /// No description provided for @downmixHint.
  ///
  /// In en, this message translates to:
  /// **'5.1 and 7.1 files are folded to stereo first (ITU coefficients), so the EQ, stereo tools and convolution apply to what you hear. Off: Android gets every channel.'**
  String get downmixHint;

  /// No description provided for @dynamicRange.
  ///
  /// In en, this message translates to:
  /// **'Dynamic range'**
  String get dynamicRange;

  /// No description provided for @frequencyContent.
  ///
  /// In en, this message translates to:
  /// **'Frequency content'**
  String get frequencyContent;

  /// No description provided for @upToKhz.
  ///
  /// In en, this message translates to:
  /// **'up to {khz} kHz'**
  String upToKhz(Object khz);

  /// No description provided for @likelyFromLossy.
  ///
  /// In en, this message translates to:
  /// **'sharp cut: probably converted from an MP3 / AAC'**
  String get likelyFromLossy;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'fr'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'fr':
      return AppLocalizationsFr();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
