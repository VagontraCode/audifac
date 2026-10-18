import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_colors.dart';
import '../../models/loudness.dart';
import '../../providers/library_providers.dart';
import '../../providers/loudness_providers.dart';
import '../../providers/player_providers.dart';
import '../../l10n/l10n.dart';
import '../../l10n/labels.dart';

/// Settings → Sound → Volume matching.
class VolumeMatchingSheet extends ConsumerWidget {
  const VolumeMatchingSheet({super.key});

  static Future<void> show(BuildContext context) => showModalBottomSheet<void>(
        context: context,
        useRootNavigator: true,
        isScrollControlled: true,
        builder: (_) => const VolumeMatchingSheet(),
      );

  static String describe(AppLocalizations l10n, VolumeMatching v) => switch (v.mode) {
        VolumeMode.off => l10n.off,
        VolumeMode.track => l10n.trackGain,
        VolumeMode.album => l10n.albumGain,
        VolumeMode.smart => l10n.smartGain,
      };

  static String _db(double db) => '${db > 0 ? '+' : db < 0 ? '−' : ''}${db.abs().toStringAsFixed(1)} dB';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final v = ref.watch(volumeMatchingProvider);
    final notifier = ref.read(volumeMatchingProvider.notifier);
    final known = ref.watch(loudnessProvider);
    final songs = ref.watch(songsProvider);
    final scan = ref.watch(loudnessScanStatusProvider);
    final theme = Theme.of(context);
    final palette = context.palette;
    final muted = theme.textTheme.bodySmall?.copyWith(color: palette.inkMuted);

    var tagged = 0, scanned = 0, failed = 0;
    for (final s in songs) {
      final info = known[s.location];
      if (info == null || !info.describes(s)) continue;
      switch (info.source) {
        case LoudnessSource.tags:
          tagged++;
        case LoudnessSource.scan:
          scanned++;
        case LoudnessSource.none:
          failed++;
      }
    }
    final missing = songs.length - tagged - scanned - failed;

    final current = ref.watch(currentSongProvider);
    String? nowPlaying;
    if (current != null && v.mode != VolumeMode.off) {
      final queue = ref.watch(playQueueProvider);
      final albumInOrder = isAlbumInOrder(queue.songs, shuffled: queue.shuffled);
      final gains = gainsFor([current], known: known, library: songs).values.firstOrNull;
      final db = v.appliedDb(gains, albumInOrder: albumInOrder)!;
      final info = known[current.location];
      final from = switch (info?.source) {
        LoudnessSource.tags => context.l10n.fromTags,
        LoudnessSource.scan => context.l10n.measuredLufs(info!.lufs?.toStringAsFixed(1) ?? '?'),
        _ => context.l10n.notAnalysedYetShort,
      };
      final which = v.mode == VolumeMode.smart ? (albumInOrder ? ' · ${context.l10n.reasonAlbum}' : ' · ${context.l10n.volumeTrack.toLowerCase()}') : '';
      nowPlaying = '${current.title}: ${_db(db)} ($from$which)';
    }

    Widget heading(String text) => Padding(
          padding: const EdgeInsets.only(top: 20, bottom: 6),
          child: Text(text, style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
        );

    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.85),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(context.l10n.volumeMatching, style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
              const SizedBox(height: 6),
              Text(
                context.l10n.volumeIntro,
                style: muted,
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: SegmentedButton<VolumeMode>(
                  showSelectedIcon: false,
                  style: SegmentedButton.styleFrom(
                    selectedBackgroundColor: palette.ink,
                    selectedForegroundColor: palette.onInk,
                    foregroundColor: palette.ink,
                    side: BorderSide(color: palette.line),
                  ),
                  segments: [for (final m in VolumeMode.values) ButtonSegment(value: m, label: Text(context.l10n.volumeMode(m)))],
                  selected: {v.mode},
                  onSelectionChanged: (s) => notifier.set(v.copyWith(mode: s.first)),
                ),
              ),
              const SizedBox(height: 6),
              Text(switch (v.mode) {
                VolumeMode.off => context.l10n.volumeOffHint,
                VolumeMode.track => context.l10n.volumeTrackHint,
                VolumeMode.album => context.l10n.volumeAlbumHint,
                VolumeMode.smart => context.l10n.volumeSmartHint,
              }, style: muted),
              if (nowPlaying != null) ...[
                const SizedBox(height: 10),
                Text(context.l10n.nowLine(nowPlaying), style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600)),
              ],
              AnimatedSize(
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOutCubic,
                child: v.mode == VolumeMode.off
                    ? const SizedBox(width: double.infinity)
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          heading('${context.l10n.preamp}  ${_db(v.preampDb)}'),
                          Text(context.l10n.preampHint, style: muted),
                          Slider(
                            value: v.preampDb,
                            min: -6,
                            max: 12,
                            divisions: 36,
                            label: _db(v.preampDb),
                            onChanged: (x) => notifier.set(v.copyWith(preampDb: x)),
                          ),
                          heading('${context.l10n.untaggedGain}  ${_db(v.untaggedGainDb)}'),
                          Text(context.l10n.untaggedGainHint, style: muted),
                          Slider(
                            value: v.untaggedGainDb,
                            min: -12,
                            max: 0,
                            divisions: 24,
                            label: _db(v.untaggedGainDb),
                            onChanged: (x) => notifier.set(v.copyWith(untaggedGainDb: x)),
                          ),
                          SwitchListTile(
                            contentPadding: EdgeInsets.zero,
                            activeThumbColor: palette.onInk,
                            activeTrackColor: palette.ink,
                            title: Text(context.l10n.preventClipping, style: TextStyle(fontWeight: FontWeight.w600)),
                            subtitle: Text(context.l10n.preventClippingHint),
                            value: v.preventClipping,
                            onChanged: (x) => notifier.set(v.copyWith(preventClipping: x)),
                          ),
                        ],
                      ),
              ),
              heading(context.l10n.tabLibrary),
              Text(
                [
                  context.l10n.songsWithTags(tagged),
                  context.l10n.songsMeasured(scanned),
                  if (failed > 0) context.l10n.cantBeAnalysed(failed),
                  context.l10n.notAnalysedYet(missing),
                ].join(' · '),
                style: muted,
              ),
              const SizedBox(height: 4),
              Text(context.l10n.upcomingAnalysed, style: muted),
              const SizedBox(height: 12),
              if (scan.running) ...[
                LinearProgressIndicator(value: scan.total == 0 ? null : scan.done / scan.total),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(child: Text(context.l10n.analysingProgress(scan.done, scan.total), style: muted)),
                    TextButton(
                      onPressed: () => ref.read(loudnessProvider.notifier).cancelLibrary(),
                      child: Text(context.l10n.stop),
                    ),
                  ],
                ),
              ] else
                FilledButton.tonal(
                  onPressed: missing == 0 ? null : () => ref.read(loudnessProvider.notifier).analyseLibrary(),
                  child: Text(missing == 0 ? context.l10n.wholeLibraryAnalysed : context.l10n.analyseNow(missing)),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
