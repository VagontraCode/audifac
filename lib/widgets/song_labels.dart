import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hugeicons/hugeicons.dart';

import '../core/theme/app_colors.dart';
import '../models/audio_info.dart';
import '../models/song.dart';
import '../models/song_source.dart';
import '../providers/audio_info_providers.dart';
import '../l10n/l10n.dart';
import '../l10n/labels.dart';

extension SourceCategoryIcon on SourceCategory {
  List<List<dynamic>> get icon => switch (this) {
        SourceCategory.music => HugeIcons.strokeRoundedMusicNote01,
        SourceCategory.downloads => HugeIcons.strokeRoundedDownload04,
        SourceCategory.whatsapp => HugeIcons.strokeRoundedWhatsapp,
        SourceCategory.telegram => HugeIcons.strokeRoundedTelegram,
        SourceCategory.bluetooth => HugeIcons.strokeRoundedBluetooth,
        SourceCategory.recordings => HugeIcons.strokeRoundedMic01,
        SourceCategory.podcasts => HugeIcons.strokeRoundedPodcast,
        SourceCategory.audiobooks => HugeIcons.strokeRoundedBook02,
        SourceCategory.hidden => HugeIcons.strokeRoundedViewOff,
        SourceCategory.other => HugeIcons.strokeRoundedFolder01,
      };
}

extension AudioQualityColor on AudioQuality {
  /// Highlight color, or null for lossy / unknown (shown muted).
  Color? color(AppPalette palette) => switch (this) {
        AudioQuality.hiRes => palette.hiRes,
        AudioQuality.lossless => palette.lossless,
        _ => null,
      };
}

/// Slim line under a song: where it comes from + its codec.
class SongLabels extends ConsumerWidget {
  const SongLabels({super.key, required this.song});

  final Song song;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final info = ref.watch(songAudioInfoProvider(song));
    final source = SongSource.of(song);
    return Row(
      children: [
        Flexible(child: SourceLabel(source: source)),
        const SizedBox(width: 6),
        QualityBadge(info: info),
      ],
    );
  }
}

class SourceLabel extends StatelessWidget {
  const SourceLabel({super.key, required this.source});

  final SongSource source;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final style = Theme.of(context).textTheme.labelSmall?.copyWith(
          color: palette.inkMuted,
          fontWeight: FontWeight.w600,
        );
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        HugeIcon(icon: source.category.icon, color: palette.inkMuted, size: 12),
        const SizedBox(width: 4),
        Flexible(
          child: Text(context.l10n.sourceLabel(source), maxLines: 1, overflow: TextOverflow.ellipsis, style: style),
        ),
        if (source.onSdCard) ...[
          const SizedBox(width: 4),
          HugeIcon(icon: HugeIcons.strokeRoundedSdCard, color: palette.inkMuted, size: 12),
        ],
      ],
    );
  }
}

/// `FLAC 24/96` (gold), `FLAC 16/44.1` (green), `MP3 320` (muted).
class QualityBadge extends StatelessWidget {
  const QualityBadge({super.key, required this.info, this.large = false});

  final AudioInfo info;
  final bool large;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final highlight = info.quality.color(palette);
    final color = highlight ?? palette.inkMuted;
    final text = info.quality == AudioQuality.hiRes && large ? '${context.l10n.qualityHiRes} · ${info.badge}' : info.badge;
    return Container(
      padding: EdgeInsets.symmetric(horizontal: large ? 8 : 5, vertical: large ? 3 : 1),
      decoration: BoxDecoration(
        color: highlight?.withValues(alpha: 0.12),
        border: Border.all(color: color.withValues(alpha: highlight == null ? 0.35 : 0.6)),
        borderRadius: BorderRadius.circular(large ? 8 : 5),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: color,
          fontSize: large ? 12 : 10,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.3,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
    );
  }
}
