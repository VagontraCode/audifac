import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hugeicons/hugeicons.dart';

import '../../core/theme/app_colors.dart';
import '../../l10n/l10n.dart';
import '../../providers/player_providers.dart';
import '../../providers/soiree_plan_provider.dart';

/// Where the soirée is: the index of the song playing in the plan, or null
/// when what plays isn't the soirée.
final soireeNowProvider = Provider<int?>((ref) {
  final s = ref.watch(soireeProvider);
  if (!s.live) return null;
  final id = ref.watch(currentSongIdProvider);
  if (id == null) return null;
  final i = s.plan.indexWhere((slot) => slot.song.id == id);
  return i < 0 ? null : i;
});

/// Player chip while a soirée plays: tap to read the room.
class SoireeLiveChip extends ConsumerWidget {
  const SoireeLiveChip({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (ref.watch(soireeNowProvider) == null) return const SizedBox.shrink();
    final palette = context.palette;
    return Padding(
      padding: const EdgeInsets.only(left: 8),
      child: GestureDetector(
        onTap: () => SoireeLiveSheet.show(context),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: palette.ink.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: palette.line),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              HugeIcon(icon: HugeIcons.strokeRoundedParty, color: palette.ink, size: 16),
              const SizedBox(width: 6),
              Text(context.l10n.soireeTitle, style: TextStyle(color: palette.ink, fontWeight: FontWeight.w700, fontSize: 13)),
            ],
          ),
        ),
      ),
    );
  }
}

/// "More energy" / "Keep it here" / "Calm it down": the rest of the soirée
/// is rebuilt from the next song on; the song playing carries on.
class SoireeLiveSheet extends ConsumerStatefulWidget {
  const SoireeLiveSheet({super.key});

  static Future<void> show(BuildContext context) =>
      showModalBottomSheet<void>(context: context, useRootNavigator: true, builder: (_) => const SoireeLiveSheet());

  @override
  ConsumerState<SoireeLiveSheet> createState() => _SoireeLiveSheetState();
}

class _SoireeLiveSheetState extends ConsumerState<SoireeLiveSheet> {
  bool _busy = false;

  Future<void> _reshape(double? delta, String done) async {
    final now = ref.read(soireeNowProvider);
    if (now == null) return;
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    final upcoming = await ref.read(soireeProvider.notifier).reshape(now + 1, delta);
    await ref.read(audioHandlerProvider).replaceUpcoming([for (final s in upcoming) s.song]);
    if (!mounted) return;
    Navigator.pop(context);
    messenger.showSnackBar(SnackBar(content: Text(done)));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final palette = context.palette;
    final s = ref.watch(soireeProvider);
    final now = ref.watch(soireeNowProvider);
    final level = now == null ? null : s.plan[now].level.round();

    Widget action(List<List<dynamic>> icon, String title, String hint, double? delta, String done) => ListTile(
          contentPadding: EdgeInsets.zero,
          enabled: !_busy,
          leading: HugeIcon(icon: icon, color: palette.ink, size: 26),
          title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
          subtitle: Text(hint),
          onTap: () => _reshape(delta, done),
        );

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l10n.readTheRoom, style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
            if (now != null)
              Text(
                l10n.soireeNow(s.plan.length, now + 1, level ?? 0),
                style: theme.textTheme.bodySmall?.copyWith(color: palette.inkMuted),
              ),
            const SizedBox(height: 8),
            if (_busy) const LinearProgressIndicator(minHeight: 2),
            action(HugeIcons.strokeRoundedFire, l10n.moreEnergy, l10n.moreEnergyHint, 15, l10n.moreEnergyDone),
            action(HugeIcons.strokeRoundedPause, l10n.keepItHere, l10n.keepItHereHint, null, l10n.keepItHereDone),
            action(HugeIcons.strokeRoundedMoon02, l10n.calmItDown, l10n.calmItDownHint, -15, l10n.calmItDownDone),
            const Divider(),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: HugeIcon(icon: HugeIcons.strokeRoundedLogout03, color: palette.inkMuted, size: 24),
              title: Text(l10n.endSoiree),
              subtitle: Text(l10n.endSoireeHint),
              onTap: () {
                ref.read(soireeProvider.notifier).setLive(false);
                Navigator.pop(context);
              },
            ),
          ],
        ),
      ),
    );
  }
}
