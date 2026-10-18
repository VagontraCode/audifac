import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format.dart';
import '../../core/theme/app_colors.dart';
import '../../models/loudness.dart';
import '../../providers/library_providers.dart';
import '../../providers/loudness_providers.dart';
import '../../providers/player_providers.dart';

/// Settings → Sound → Volume matching.
class VolumeMatchingSheet extends ConsumerWidget {
  const VolumeMatchingSheet({super.key});

  static Future<void> show(BuildContext context) => showModalBottomSheet<void>(
        context: context,
        useRootNavigator: true,
        isScrollControlled: true,
        builder: (_) => const VolumeMatchingSheet(),
      );

  static String describe(VolumeMatching v) => switch (v.mode) {
        VolumeMode.off => 'Off',
        VolumeMode.track => 'Track gain',
        VolumeMode.album => 'Album gain',
        VolumeMode.smart => 'Smart (album gain for whole albums)',
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
        LoudnessSource.tags => 'ReplayGain tags',
        LoudnessSource.scan => 'measured ${info!.lufs?.toStringAsFixed(1)} LUFS',
        _ => 'not analysed yet',
      };
      final which = v.mode == VolumeMode.smart ? (albumInOrder ? ' · album' : ' · track') : '';
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
              Text('Volume matching', style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
              const SizedBox(height: 6),
              Text(
                'Plays every song at the same loudness (ReplayGain 2.0, −18 LUFS), from its tags or an '
                'EBU R128 measurement. Applied before the equalizer; dynamics are untouched.',
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
                  segments: [for (final m in VolumeMode.values) ButtonSegment(value: m, label: Text(m.label))],
                  selected: {v.mode},
                  onSelectionChanged: (s) => notifier.set(v.copyWith(mode: s.first)),
                ),
              ),
              const SizedBox(height: 6),
              Text(switch (v.mode) {
                VolumeMode.off => 'Songs play at their mastered level.',
                VolumeMode.track => 'Every song at the same loudness — best for shuffle and mixes.',
                VolumeMode.album => 'Albums keep their quiet and loud songs as mastered.',
                VolumeMode.smart => 'Album gain while one album plays in order, track gain otherwise.',
              }, style: muted),
              if (nowPlaying != null) ...[
                const SizedBox(height: 10),
                Text('Now: $nowPlaying', style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600)),
              ],
              AnimatedSize(
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOutCubic,
                child: v.mode == VolumeMode.off
                    ? const SizedBox(width: double.infinity)
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          heading('Pre-amp  ${_db(v.preampDb)}'),
                          Text('−18 LUFS is quieter than most modern music; +3 to +6 dB is common.', style: muted),
                          Slider(
                            value: v.preampDb,
                            min: -6,
                            max: 12,
                            divisions: 36,
                            label: _db(v.preampDb),
                            onChanged: (x) => notifier.set(v.copyWith(preampDb: x)),
                          ),
                          heading('Songs without loudness data  ${_db(v.untaggedGainDb)}'),
                          Text('Used until a song is analysed, and for formats that can\'t be.', style: muted),
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
                            title: const Text('Prevent clipping', style: TextStyle(fontWeight: FontWeight.w600)),
                            subtitle: const Text('Never raise a song above its peak level'),
                            value: v.preventClipping,
                            onChanged: (x) => notifier.set(v.copyWith(preventClipping: x)),
                          ),
                        ],
                      ),
              ),
              heading('Library'),
              Text(
                [
                  '${pluralize(tagged, 'song')} with tags',
                  '${pluralize(scanned, 'song')} measured',
                  if (failed > 0) '$failed can\'t be analysed',
                  '$missing not analysed yet',
                ].join(' · '),
                style: muted,
              ),
              const SizedBox(height: 4),
              Text('Upcoming songs are analysed automatically while volume matching is on.', style: muted),
              const SizedBox(height: 12),
              if (scan.running) ...[
                LinearProgressIndicator(value: scan.total == 0 ? null : scan.done / scan.total),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(child: Text('Analysing ${scan.done} / ${scan.total}…', style: muted)),
                    TextButton(
                      onPressed: () => ref.read(loudnessProvider.notifier).cancelLibrary(),
                      child: const Text('Stop'),
                    ),
                  ],
                ),
              ] else
                FilledButton.tonal(
                  onPressed: missing == 0 ? null : () => ref.read(loudnessProvider.notifier).analyseLibrary(),
                  child: Text(missing == 0 ? 'Whole library analysed' : 'Analyse ${pluralize(missing, 'song')} now'),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
