import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hugeicons/hugeicons.dart';

import '../core/format.dart';
import '../core/theme/app_colors.dart';
import '../models/audio_info.dart';
import '../models/song.dart';
import '../models/song_source.dart';
import '../models/loudness.dart';
import '../providers/audio_info_providers.dart';
import '../providers/loudness_providers.dart';
import '../providers/stats_providers.dart';
import 'artwork.dart';
import 'song_labels.dart';
import '../l10n/l10n.dart';
import '../l10n/labels.dart';

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
    final stats = ref.watch(songStatsProvider.select((m) => m[song.id]));
    final loudness = ref.watch(loudnessProvider.select((m) => m[song.location]));
    final theme = Theme.of(context);
    final palette = context.palette;

    String? channels(int? n) => switch (n) {
          null => null,
          1 => context.l10n.mono,
          2 => context.l10n.stereo,
          _ => context.l10n.channelsN(n),
        };

    final fileName = (song.path ?? song.uri).split('/').last;
    final rows = <(String, List<(String, String?)>)>[
      (
        context.l10n.audio,
        [
          (context.l10n.fieldQuality, info.analysed ? context.l10n.quality(info.quality) : context.l10n.analysingSuffix(context.l10n.quality(info.quality))),
          (context.l10n.fieldCodec, info.codec),
          (context.l10n.container, info.containerMime ?? song.mimeType),
          (context.l10n.bitrate, info.kbpsOrNull == null ? null : '${info.kbpsOrNull} kbps'),
          (context.l10n.sampleRate, info.sampleRate == null ? null : '${AudioInfo.formatSampleRate(info.sampleRate!)} kHz'),
          (context.l10n.bitDepth, info.bitDepth == null ? null : '${info.bitDepth}-bit'),
          (context.l10n.channels, channels(info.channels)),
          (context.l10n.duration, formatDuration(song.duration)),
          (context.l10n.dynamicRange, loudness?.dr == null ? null : 'DR${loudness!.dr}'),
          (
            context.l10n.frequencyContent,
            loudness?.cutoffHz == null
                ? null
                : [
                    context.l10n.upToKhz((loudness!.cutoffHz! / 1000).toStringAsFixed(1)),
                    if (loudness.lossyCutoff && info.quality.isLossless) context.l10n.likelyFromLossy,
                  ].join(' · '),
          ),
        ],
      ),
      (
        context.l10n.tags,
        [
          (context.l10n.fieldTitle, song.title),
          (context.l10n.fieldArtist, song.artist),
          (context.l10n.fieldAlbum, song.album),
          (context.l10n.albumArtist, info.albumArtist),
          (context.l10n.fieldGenre, info.genre),
          (context.l10n.fieldYear, info.year),
          (context.l10n.track, song.trackNumber % 1000 == 0 ? null : '${song.trackNumber % 1000}'),
          (context.l10n.disc, info.disc),
          (context.l10n.composer, info.composer),
        ],
      ),
      (
        context.l10n.listeningSection,
        [
          (context.l10n.playsLabel, '${stats?.plays ?? 0}'),
          (context.l10n.fieldLastPlayed, stats?.lastPlayed == null ? null : _date(stats!.lastPlayed!)),
          (context.l10n.listeningTime, stats == null || stats.listened == Duration.zero ? null : formatTotalDuration(stats.listened)),
          (
            context.l10n.loudness,
            switch (loudness) {
              LoudnessInfo(source: LoudnessSource.tags, :final trackGainDb?) =>
                context.l10n.replayGainTags(formatDb(trackGainDb)),
              LoudnessInfo(source: LoudnessSource.scan, :final lufs?, :final trackGainDb?) =>
                '${lufs.toStringAsFixed(1)} LUFS · ReplayGain ${formatDb(trackGainDb)}',
              _ => null,
            },
          ),
        ],
      ),
      (
        context.l10n.file,
        [
          (context.l10n.name, fileName),
          (context.l10n.fieldFolder, song.folder),
          (context.l10n.fieldSource, '${context.l10n.sourceCategory(source.category)}${source.onSdCard ? ' · ${context.l10n.sdCard}' : ''}'),
          (context.l10n.size, formatBytes(song.sizeBytes)),
          (context.l10n.fieldAdded, _date(song.dateAdded)),
          (context.l10n.modified, song.modifiedMs == 0 ? null : _date(DateTime.fromMillisecondsSinceEpoch(song.modifiedMs))),
          (
            context.l10n.indexedBy,
            song.isFile
                ? (song.uri.startsWith('content://') ? context.l10n.indexedGranted : context.l10n.indexedScan)
                : context.l10n.indexedMediaStore,
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
                      SnackBar(content: Text(context.l10n.pathCopied)),
                    );
                  },
                  style: OutlinedButton.styleFrom(
                    foregroundColor: palette.ink,
                    side: BorderSide(color: palette.line, width: 1.5),
                  ),
                  icon: HugeIcon(icon: HugeIcons.strokeRoundedCopy01, color: palette.ink, size: 18),
                  label: Text(context.l10n.copyPath, style: TextStyle(fontWeight: FontWeight.w700)),
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
