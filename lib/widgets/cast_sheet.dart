import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hugeicons/hugeicons.dart';

import '../cast/cast_target.dart';
import '../core/format.dart';
import '../core/theme/app_colors.dart';
import '../l10n/l10n.dart';
import '../providers/cast_provider.dart';
import 'artwork.dart';

/// Pick a TV / speaker, then control what plays on it.
class CastSheet extends ConsumerStatefulWidget {
  const CastSheet({super.key});

  static Future<void> show(BuildContext context) => showModalBottomSheet<void>(
        context: context,
        useRootNavigator: true,
        isScrollControlled: true,
        builder: (_) => const CastSheet(),
      );

  @override
  ConsumerState<CastSheet> createState() => _CastSheetState();
}

class _CastSheetState extends ConsumerState<CastSheet> {
  double? _seeking;

  @override
  void initState() {
    super.initState();
    if (!ref.read(castProvider).active) Future.microtask(() => ref.read(castProvider.notifier).discover());
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final s = ref.watch(castProvider);
    final notifier = ref.read(castProvider.notifier);
    final theme = Theme.of(context);
    final palette = context.palette;
    final muted = theme.textTheme.bodySmall?.copyWith(color: palette.inkMuted);

    Widget body;
    if (s.active) {
      final song = s.song;
      final duration = s.status.duration ?? song?.duration ?? Duration.zero;
      final position = s.status.position;
      final max = duration.inMilliseconds.toDouble().clamp(1.0, double.infinity);
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l10n.castingTo(s.target!.name), style: const TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text(l10n.castingHint, style: muted),
          const SizedBox(height: 16),
          if (song != null)
            Row(
              children: [
                Artwork.song(song, size: 56, radius: 12),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(song.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700)),
                      Text(song.artist, maxLines: 1, overflow: TextOverflow.ellipsis, style: muted),
                    ],
                  ),
                ),
              ],
            ),
          Slider(
            value: (_seeking ?? position.inMilliseconds.toDouble()).clamp(0, max),
            max: max,
            onChanged: (v) => setState(() => _seeking = v),
            onChangeEnd: (v) {
              setState(() => _seeking = null);
              notifier.seek(Duration(milliseconds: v.round()));
            },
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(formatDuration(position), style: muted),
              Text(formatDuration(duration), style: muted),
            ],
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                tooltip: l10n.previous,
                onPressed: notifier.previous,
                icon: HugeIcon(icon: HugeIcons.strokeRoundedPrevious, color: palette.ink, size: 32),
              ),
              const SizedBox(width: 16),
              IconButton.filled(
                tooltip: s.status.playback == CastPlayback.playing ? l10n.pause : l10n.play,
                onPressed: notifier.togglePlay,
                iconSize: 36,
                icon: s.status.playback == CastPlayback.loading
                    ? const SizedBox.square(dimension: 28, child: CircularProgressIndicator(strokeWidth: 3))
                    : Icon(s.status.playback == CastPlayback.playing ? Icons.pause_rounded : Icons.play_arrow_rounded),
              ),
              const SizedBox(width: 16),
              IconButton(
                tooltip: l10n.next,
                onPressed: notifier.next,
                icon: HugeIcon(icon: HugeIcons.strokeRoundedNext, color: palette.ink, size: 32),
              ),
            ],
          ),
          if (s.status.volume != null)
            Row(
              children: [
                HugeIcon(icon: HugeIcons.strokeRoundedVolumeLow, color: palette.inkMuted, size: 20),
                Expanded(child: Slider(value: s.status.volume!.clamp(0, 1), onChanged: notifier.setVolume)),
                HugeIcon(icon: HugeIcons.strokeRoundedVolumeHigh, color: palette.inkMuted, size: 20),
              ],
            ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: () async {
              await notifier.disconnect();
              if (context.mounted) Navigator.of(context).pop();
            },
            icon: HugeIcon(icon: HugeIcons.strokeRoundedSmartPhone01, color: palette.ink, size: 18),
            label: Text(l10n.playOnPhone),
          ),
        ],
      );
    } else {
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l10n.castIntro, style: muted),
          const SizedBox(height: 12),
          if (s.discovering) const LinearProgressIndicator(),
          for (final d in s.devices)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: HugeIcon(
                icon: d.kind == CastKind.chromecast ? HugeIcons.strokeRoundedTv01 : HugeIcons.strokeRoundedSpeaker,
                color: palette.ink,
                size: 24,
              ),
              title: Text(d.name, style: const TextStyle(fontWeight: FontWeight.w600)),
              subtitle: Text(d.kind == CastKind.chromecast ? 'Google Cast' : 'DLNA / UPnP'),
              trailing: s.connecting ? const SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2)) : null,
              onTap: s.connecting ? null : () => notifier.connect(d),
            ),
          if (!s.discovering && s.devices.isEmpty) Padding(padding: const EdgeInsets.symmetric(vertical: 12), child: Text(l10n.noCastDevices)),
          TextButton.icon(
            onPressed: s.discovering ? null : notifier.discover,
            icon: HugeIcon(icon: HugeIcons.strokeRoundedRefresh, color: palette.ink, size: 18),
            label: Text(l10n.searchAgain),
          ),
        ],
      );
    }

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l10n.castTitle, style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            body,
            if (s.error != null) ...[
              const SizedBox(height: 8),
              Text(s.error!, style: theme.textTheme.bodySmall?.copyWith(color: const Color(0xFFD70015))),
            ],
          ],
        ),
      ),
    );
  }
}
