import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hugeicons/hugeicons.dart';

import '../../core/theme/app_colors.dart';
import '../../models/eq.dart';
import '../../models/eq_rules.dart';
import '../../providers/eq_providers.dart';
import '../../widgets/empty_state.dart';
import 'quick_eq_sheet.dart';
import '../../l10n/l10n.dart';
import '../../l10n/labels.dart';

/// Every rule (song / album / artist / genre / source → preset), the default
/// sound preset, and every known output with its correction.
class EqRulesScreen extends ConsumerWidget {
  const EqRulesScreen({super.key});

  static Future<void> open(BuildContext context) => Navigator.of(context, rootNavigator: true).push(
        MaterialPageRoute<void>(builder: (_) => const EqRulesScreen()),
      );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rules = ref.watch(eqRulesProvider);
    final settings = ref.watch(eqSettingsProvider);
    final presets = ref.watch(eqPresetsProvider);
    final output = ref.watch(outputDeviceProvider);
    final palette = context.palette;
    final theme = Theme.of(context);

    String presetName(String id) => switch (presets.where((p) => p.id == id).firstOrNull) { final p? => context.l10n.presetName(p), _ => context.l10n.deletedPreset };

    Widget section(String text) => Padding(
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 6),
          child: Text(
            text.toUpperCase(),
            style: theme.textTheme.labelSmall?.copyWith(letterSpacing: 1.4, fontWeight: FontWeight.w800, color: palette.inkMuted),
          ),
        );

    List<List<dynamic>> deviceIcon(String kind) => switch (kind) {
          'bluetooth' => HugeIcons.strokeRoundedBluetooth,
          'wired' || 'usb' => HugeIcons.strokeRoundedHeadphones,
          _ => HugeIcons.strokeRoundedSmartPhone01,
        };

    return Scaffold(
      appBar: AppBar(
        title: Text(context.l10n.rulesAndDevices, style: TextStyle(fontWeight: FontWeight.w800)),
        leading: IconButton(
          tooltip: context.l10n.back,
          onPressed: () => Navigator.of(context).pop(),
          icon: HugeIcon(icon: HugeIcons.strokeRoundedArrowLeft01, color: palette.ink, size: 26),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Text(
              context.l10n.rulesIntro,
              style: theme.textTheme.bodyMedium,
            ),
          ),
          section(context.l10n.allMusic),
          ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 20),
            leading: HugeIcon(icon: HugeIcons.strokeRoundedMusicNote01, color: palette.ink, size: 22),
            title: Text(presetName(settings.defaultSoundId), style: const TextStyle(fontWeight: FontWeight.w700)),
            subtitle: Text(context.l10n.defaultSoundPreset),
            trailing: TextButton(
              onPressed: () => QuickEqSheet.show(context, initialScope: ApplyScope.everything),
              child: Text(context.l10n.change),
            ),
          ),
          for (final scope in EqScope.values)
            if (rules.any((r) => r.scope == scope)) ...[
              section(switch (scope) {
                EqScope.song => context.l10n.songsTitle,
                EqScope.album => context.l10n.albumsTitle,
                EqScope.artist => context.l10n.artists,
                EqScope.genre => context.l10n.genres,
                EqScope.source => context.l10n.sources,
              }),
              for (final r in rules.where((r) => r.scope == scope))
                ListTile(
                  contentPadding: const EdgeInsets.only(left: 20, right: 8),
                  title: Text(r.label.isEmpty ? r.key : r.label,
                      maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700)),
                  subtitle: Text(presetName(r.presetId)),
                  trailing: IconButton(
                    tooltip: context.l10n.removeRule,
                    onPressed: () => ref.read(eqRulesProvider.notifier).remove(r.scope, r.key),
                    icon: HugeIcon(icon: HugeIcons.strokeRoundedCancel01, color: palette.inkMuted, size: 20),
                  ),
                ),
            ],
          if (rules.isEmpty)
            Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: EmptyState(
                icon: HugeIcons.strokeRoundedListView,
                title: context.l10n.noRulesYet,
                message: context.l10n.noRulesHint,
              ),
            ),
          section(context.l10n.devices),
          for (final d in settings.devices.values)
            ListTile(
              contentPadding: const EdgeInsets.only(left: 20, right: 8),
              leading: HugeIcon(icon: deviceIcon(d.kind), color: palette.ink, size: 22),
              title: Text(
                d.key == output.key ? context.l10n.deviceNowPlaying(context.l10n.deviceName(d)) : context.l10n.deviceName(d),
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              subtitle: Text(presetName(d.presetId)),
              trailing: PopupMenuButton<String>(
                icon: HugeIcon(icon: HugeIcons.strokeRoundedMoreVertical, color: palette.inkMuted, size: 20),
                onSelected: (value) {
                  if (value == 'forget') {
                    ref.read(eqSettingsProvider.notifier).forgetDevice(d.key);
                  } else {
                    ref.read(eqSettingsProvider.notifier).assignDevice(d, value);
                  }
                },
                itemBuilder: (_) => [
                  for (final p in presets.where((p) => p.kind == EqPresetKind.device))
                    CheckedPopupMenuItem(value: p.id, checked: p.id == d.presetId, child: Text(context.l10n.presetName(p))),
                  const PopupMenuDivider(),
                  PopupMenuItem(value: 'forget', child: Text(context.l10n.forgetDevice)),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
