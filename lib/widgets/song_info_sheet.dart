import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hugeicons/hugeicons.dart';

import '../core/format.dart';
import '../core/theme/app_colors.dart';
import '../models/audio_info.dart';
import '../models/song.dart';
import '../models/song_source.dart';
import '../providers/audio_info_providers.dart';
import 'artwork.dart';
import 'song_labels.dart';

/// Everything known about a song: tags, audio stream details and file facts.
class SongInfoSheet extends ConsumerStatefulWidget {
  const SongInfoSheet({super.key, required this.song});

  final Song song;

  static Future<void> show(BuildContext context, Song song) => showModalBottomSheet<void>(
        context: context,
        useRootNavigator: true,
        isScrollControlled: true,
        builder: (_) => SongInfoSheet(song: song),
      );

  @override
  ConsumerState<SongInfoSheet> createState() => _SongInfoSheetState();
}

class _SongInfoSheetState extends ConsumerState<SongInfoSheet> {
  @override
  void initState() {
    super.initState();
    // Not analysed yet by the background pass? Do it now.
    ref.read(audioInfoProvider.notifier).ensure(widget.song);
  }

  @override
  Widget build(BuildContext context) {
    final song = widget.song;
    final info = ref.watch(songAudioInfoProvider(song));
    final source = SongSource.of(song);
    final theme = Theme.of(context);
    final palette = context.palette;

    String? channels(int? n) => switch (n) {
          null => null,
          1 => 'Mono',
          2 => 'Stereo',
          _ => '$n channels',
        };

    final fileName = (song.path ?? song.uri).split('/').last;
    final rows = <(String, List<(String, String?)>)>[
      (
        'Audio',
        [
          ('Quality', info.analysed ? info.quality.label : '${info.quality.label} (analysing…)'),
          ('Codec', info.codec),
          ('Container', info.containerMime ?? song.mimeType),
          ('Bitrate', info.kbpsOrNull == null ? null : '${info.kbpsOrNull} kbps'),
          ('Sample rate', info.sampleRate == null ? null : '${AudioInfo.formatSampleRate(info.sampleRate!)} kHz'),
          ('Bit depth', info.bitDepth == null ? null : '${info.bitDepth}-bit'),
          ('Channels', channels(info.channels)),
          ('Duration', formatDuration(song.duration)),
        ],
      ),
      (
        'Tags',
        [
          ('Title', song.title),
          ('Artist', song.artist),
          ('Album', song.album),
          ('Album artist', info.albumArtist),
          ('Genre', info.genre),
          ('Year', info.year),
          ('Track', song.trackNumber % 1000 == 0 ? null : '${song.trackNumber % 1000}'),
          ('Disc', info.disc),
          ('Composer', info.composer),
        ],
      ),
      (
        'File',
        [
          ('Name', fileName),
          ('Folder', song.folder),
          ('Source', '${source.category.label}${source.onSdCard ? ' · SD card' : ''}'),
          ('Size', formatBytes(song.sizeBytes)),
          ('Added', _date(song.dateAdded)),
          ('Modified', song.modifiedMs == 0 ? null : _date(DateTime.fromMillisecondsSinceEpoch(song.modifiedMs))),
          (
            'Indexed by',
            song.isFile
                ? (song.uri.startsWith('content://') ? 'Hidden folder (granted)' : 'audifac storage scan')
                : 'Android media library',
          ),
        ],
      ),
    ];

    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.88),
      child: SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
          children: [
            Row(
              children: [
                Artwork.song(song, size: 72, radius: 14),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        song.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
                      ),
                      Text(song.artist, maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodyMedium),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 6,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [QualityBadge(info: info, large: true), SourceLabel(source: source)],
                      ),
                    ],
                  ),
                ),
              ],
            ),
            for (final (title, entries) in rows) ...[
              Padding(
                padding: const EdgeInsets.only(top: 22, bottom: 6),
                child: Text(
                  title.toUpperCase(),
                  style: theme.textTheme.labelSmall?.copyWith(
                    letterSpacing: 1.4,
                    fontWeight: FontWeight.w800,
                    color: palette.inkMuted,
                  ),
                ),
              ),
              for (final (label, value) in entries)
                if (value != null && value.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 5),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                          width: 112,
                          child: Text(label, style: theme.textTheme.bodyMedium),
                        ),
                        Expanded(
                          child: SelectableText(
                            value,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: palette.ink,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
            ],
            if (song.path != null) ...[
              const SizedBox(height: 16),
              Align(
                alignment: Alignment.centerLeft,
                child: OutlinedButton.icon(
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: song.path!));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('File path copied')),
                    );
                  },
                  style: OutlinedButton.styleFrom(
                    foregroundColor: palette.ink,
                    side: BorderSide(color: palette.line, width: 1.5),
                  ),
                  icon: HugeIcon(icon: HugeIcons.strokeRoundedCopy01, color: palette.ink, size: 18),
                  label: const Text('Copy path', style: TextStyle(fontWeight: FontWeight.w700)),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  static String _date(DateTime d) {
    if (d.millisecondsSinceEpoch == 0) return '—';
    String two(int n) => n.toString().padLeft(2, '0');
    return '${d.year}-${two(d.month)}-${two(d.day)} ${two(d.hour)}:${two(d.minute)}';
  }
}
