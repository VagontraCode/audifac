import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hugeicons/hugeicons.dart';

import '../core/format.dart';
import '../core/theme/app_colors.dart';
import '../providers/sleep_timer_provider.dart';
import '../l10n/l10n.dart';

/// Stop playback after a while, at the end of the song or of the queue,
/// fading out gently.
class SleepTimerSheet extends ConsumerWidget {
  const SleepTimerSheet({super.key});

  static Future<void> show(BuildContext context) => showModalBottomSheet<void>(
        context: context,
        useRootNavigator: true,
        builder: (_) => const SleepTimerSheet(),
      );

  static const presets = [5, 15, 30, 45, 60, 90];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final timer = ref.watch(sleepTimerProvider);
    final notifier = ref.read(sleepTimerProvider.notifier);
    final theme = Theme.of(context);
    final palette = context.palette;

    void pick(VoidCallback start) {
      start();
      Navigator.of(context).pop();
    }

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(context.l10n.sleepTimer, style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            Text(
              timer.active ? SleepChip.describe(context.l10n, timer) : context.l10n.sleepHint,
              style: theme.textTheme.bodyMedium?.copyWith(color: palette.inkMuted),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final m in presets)
                  ActionChip(
                    label: Text(m < 60 ? context.l10n.minutesShort(m) : '${m ~/ 60} h${m % 60 == 0 ? '' : ' ${m % 60}'}'),
                    onPressed: () => pick(() => notifier.start(Duration(minutes: m))),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: HugeIcon(icon: HugeIcons.strokeRoundedMusicNote03, color: palette.ink, size: 22),
              title: Text(context.l10n.endOfSong, style: TextStyle(fontWeight: FontWeight.w600)),
              selected: timer.mode == SleepMode.endOfTrack,
              onTap: () => pick(notifier.startEndOfTrack),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: HugeIcon(icon: HugeIcons.strokeRoundedPlaylist02, color: palette.ink, size: 22),
              title: Text(context.l10n.endOfQueue, style: TextStyle(fontWeight: FontWeight.w600)),
              selected: timer.mode == SleepMode.endOfQueue,
              onTap: () => pick(notifier.startEndOfQueue),
            ),
            if (timer.active)
              Row(
                children: [
                  if (timer.mode == SleepMode.minutes)
                    TextButton(
                      onPressed: () => notifier.extend(const Duration(minutes: 10)),
                      child: Text('+${context.l10n.minutesShort(10)}'),
                    ),
                  const Spacer(),
                  FilledButton.tonal(
                    onPressed: () => pick(notifier.cancel),
                    child: Text(context.l10n.turnOff),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

/// Moon chip under the player controls; shows the time left when on.
class SleepChip extends ConsumerWidget {
  const SleepChip({super.key});

  static String describe(AppLocalizations l10n, SleepTimerState t) => switch (t.mode) {
        SleepMode.off => '',
        SleepMode.minutes => l10n.stopsIn(_left(t.remaining ?? Duration.zero)),
        SleepMode.endOfTrack => l10n.stopsAtSongEnd,
        SleepMode.endOfQueue => l10n.stopsAtQueueEnd,
      };

  static String _left(Duration d) {
    if (d.inMinutes >= 1) return formatTotalDuration(d + const Duration(seconds: 59));
    return '${d.inSeconds.clamp(0, 59)} s';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final timer = ref.watch(sleepTimerProvider);
    final palette = context.palette;
    final label = switch (timer.mode) {
      SleepMode.off => null,
      SleepMode.minutes => _left(timer.remaining ?? Duration.zero),
      SleepMode.endOfTrack => context.l10n.songEnd,
      SleepMode.endOfQueue => context.l10n.queueEnd,
    };
    return Tooltip(
      message: context.l10n.sleepTimer,
      child: GestureDetector(
        onTap: () => SleepTimerSheet.show(context),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          padding: EdgeInsets.symmetric(horizontal: label == null ? 9 : 12, vertical: 8),
          decoration: BoxDecoration(
            color: timer.active ? palette.ink.withValues(alpha: 0.08) : Colors.transparent,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: palette.line),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              HugeIcon(
                icon: HugeIcons.strokeRoundedMoon02,
                color: timer.active ? palette.ink : palette.inkMuted,
                size: 16,
              ),
              if (label != null) ...[
                const SizedBox(width: 6),
                Text(label, style: TextStyle(color: palette.ink, fontWeight: FontWeight.w700, fontSize: 13)),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
