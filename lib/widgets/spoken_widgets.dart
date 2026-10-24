import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hugeicons/hugeicons.dart';

import '../core/format.dart';
import '../core/theme/app_colors.dart';
import '../models/spoken.dart';
import '../providers/playback_memory_provider.dart';
import '../providers/player_providers.dart';
import '../providers/spoken_providers.dart';
import '../l10n/l10n.dart';

/// 1 → "1×", 1.25 → "1.25×", 1.5 → "1.5×".
String speedLabel(double s) => '${s.toStringAsFixed(2).replaceAll(RegExp(r'\.?0+$'), '')}×';

/// A small outlined chip like the EQ / sleep chips.
class _Chip extends StatelessWidget {
  const _Chip({required this.icon, required this.label, required this.onTap, this.tooltip, this.active = true});

  final List<List<dynamic>> icon;
  final String label;
  final VoidCallback onTap;
  final String? tooltip;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Padding(
      padding: const EdgeInsets.only(left: 8),
      child: Tooltip(
        message: tooltip ?? label,
        child: GestureDetector(
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: active ? palette.ink.withValues(alpha: 0.08) : Colors.transparent,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: palette.line),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                HugeIcon(icon: icon, color: palette.ink, size: 16),
                const SizedBox(width: 6),
                Text(
                  label,
                  style: TextStyle(color: palette.ink, fontWeight: FontWeight.w700, fontSize: 13),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Speed chip, shown for audiobooks & podcasts (and anything with a speed
/// remembered for its album / artist).
class SpeedChip extends ConsumerWidget {
  const SpeedChip({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final remembered = ref.watch(currentPlaybackMemoryProvider).speed != null;
    if (!ref.watch(currentIsLongFormProvider) && !remembered) return const SizedBox.shrink();
    final speed = ref.watch(effectiveSpeedProvider);
    return _Chip(
      icon: HugeIcons.strokeRoundedDashboardSpeed01,
      label: speedLabel(speed),
      tooltip: context.l10n.playbackSpeed,
      active: speed != 1.0,
      onTap: () => SpeedSheet.show(context),
    );
  }
}

class SpeedSheet extends ConsumerWidget {
  const SpeedSheet({super.key});

  static Future<void> show(BuildContext context) =>
      showModalBottomSheet<void>(context: context, useRootNavigator: true, builder: (_) => const SpeedSheet());

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final speed = ref.watch(effectiveSpeedProvider);
    final song = ref.watch(currentSongProvider);
    final memories = ref.watch(playbackMemoryProvider);
    final memory = ref.read(playbackMemoryProvider.notifier);
    final album = song == null ? null : memories.album(song.albumId);
    final artist = song == null ? null : memories.artist(song.artist);
    final theme = Theme.of(context);

    // Where a change goes: the album's remembered speed, the artist's, or
    // the spoken-word speed.
    void set(double s) {
      if (song != null && album?.speed != null) {
        memory.setAlbum(song.albumId, album!.copyWith(speed: () => s));
      } else if (song != null && artist?.speed != null) {
        memory.setArtist(song.artist, artist!.copyWith(speed: () => s));
      } else {
        ref.read(spokenSpeedProvider.notifier).set(s);
      }
    }

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(context.l10n.speed, style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
                ),
                Text(speedLabel(speed), style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
              ],
            ),
            Text(
              context.l10n.speedHint,
              style: theme.textTheme.bodySmall?.copyWith(color: context.palette.inkMuted),
            ),
            Slider(value: speed, min: 0.5, max: 3, divisions: 50, label: speedLabel(speed), onChanged: set),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final s in SpokenSpeedNotifier.choices)
                  ChoiceChip(label: Text(speedLabel(s)), selected: speed == s, onSelected: (_) => set(s)),
              ],
            ),
            if (song != null) ...[
              const SizedBox(height: 16),
              Text(context.l10n.rememberFor, style: const TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: [
                  FilterChip(
                    label: Text(context.l10n.thisAlbum),
                    selected: album?.speed != null,
                    onSelected: (on) => memory.setAlbum(song.albumId, album!.copyWith(speed: () => on ? speed : null)),
                  ),
                  FilterChip(
                    label: Text(context.l10n.thisArtist),
                    selected: artist?.speed != null,
                    onSelected: (on) => memory.setArtist(song.artist, artist!.copyWith(speed: () => on ? speed : null)),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Current chapter; tap for the list. Hidden without chapters.
class ChapterChip extends ConsumerWidget {
  const ChapterChip({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final song = ref.watch(currentSongProvider);
    if (song == null) return const SizedBox.shrink();
    final chapters = ref.watch(chaptersProvider(song)).value ?? const [];
    if (chapters.isEmpty) return const SizedBox.shrink();
    final position = ref.watch(positionProvider).value ?? Duration.zero;
    final i = chapterAt(chapters, position);
    return _Chip(
      icon: HugeIcons.strokeRoundedBookBookmark01,
      label: '${i + 1}/${chapters.length}',
      tooltip: chapters[i].title,
      onTap: () => ChaptersSheet.show(context),
    );
  }
}

class ChaptersSheet extends ConsumerWidget {
  const ChaptersSheet({super.key});

  static Future<void> show(BuildContext context) => showModalBottomSheet<void>(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    builder: (_) => const ChaptersSheet(),
  );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final song = ref.watch(currentSongProvider);
    final chapters = song == null ? const <Chapter>[] : ref.watch(chaptersProvider(song)).value ?? const [];
    final position = ref.watch(positionProvider).value ?? Duration.zero;
    final current = chapterAt(chapters, position);
    final theme = Theme.of(context);
    final palette = context.palette;
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.8),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
              child: Text(context.l10n.chapters, style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
            ),
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: chapters.length,
                itemBuilder: (context, i) {
                  final c = chapters[i];
                  final playing = i == current;
                  return ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 24),
                    leading: SizedBox(
                      width: 28,
                      child: playing
                          ? HugeIcon(icon: HugeIcons.strokeRoundedVolumeHigh, color: palette.ink, size: 20)
                          : Text('${i + 1}', style: theme.textTheme.titleSmall?.copyWith(color: palette.inkMuted)),
                    ),
                    title: Text(
                      c.title.isEmpty ? context.l10n.chapterN(i + 1) : c.title,
                      style: TextStyle(fontWeight: playing ? FontWeight.w800 : FontWeight.w500),
                    ),
                    trailing: Text(formatDuration(c.start), style: theme.textTheme.bodySmall),
                    onTap: () {
                      ref.read(audioHandlerProvider).seek(c.start);
                      Navigator.of(context).pop();
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
