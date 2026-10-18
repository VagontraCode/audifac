import 'song.dart';

/// Where a song lives on the device, derived from its folder.
enum SourceCategory {
  music('Music'),
  downloads('Downloads'),
  whatsapp('WhatsApp'),
  telegram('Telegram'),
  bluetooth('Bluetooth'),
  recordings('Recordings'),
  podcasts('Podcasts'),
  audiobooks('Audiobooks'),
  hidden('Hidden folder'),
  other('Other');

  const SourceCategory(this.label);
  final String label;
}

class SongSource {
  const SongSource({required this.category, required this.folderName, required this.onSdCard});

  final SourceCategory category;

  /// Name of the containing folder, e.g. "Download" or "Rock".
  final String folderName;
  final bool onSdCard;

  /// Text for the row label: the category, or the folder name for "Other".
  String get label => category == SourceCategory.other ? folderName : category.label;

  static final _sdCard = RegExp(r'^/storage/[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}(/|$)');

  /// First matching rule wins, so e.g. WhatsApp voice notes count as
  /// Recordings and music downloaded by Telegram counts as Telegram.
  static SongSource of(Song song) {
    final path = (song.path ?? '').toLowerCase();
    final folder = song.folder ?? '';
    final folderName = folder.isEmpty ? 'Unknown' : folder.substring(folder.lastIndexOf('/') + 1);

    bool has(String segment) => path.contains('/$segment/');

    final category = switch (path) {
      _ when song.isRecording || Song.looksLikeRecording(song.path) => SourceCategory.recordings,
      _ when has('whatsapp') || path.contains('/com.whatsapp') => SourceCategory.whatsapp,
      _ when has('telegram') || path.contains('/org.telegram') => SourceCategory.telegram,
      _ when has('bluetooth') => SourceCategory.bluetooth,
      _ when has('podcasts') || song.isPodcast => SourceCategory.podcasts,
      _ when has('audiobooks') => SourceCategory.audiobooks,
      _ when has('download') || has('downloads') => SourceCategory.downloads,
      _ when has('music') => SourceCategory.music,
      _ when song.isFile => SourceCategory.hidden,
      _ => SourceCategory.other,
    };

    return SongSource(
      category: category,
      folderName: folderName,
      onSdCard: _sdCard.hasMatch(song.path ?? ''),
    );
  }
}
