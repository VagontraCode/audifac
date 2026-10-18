import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hugeicons/hugeicons.dart';
import '../../l10n/l10n.dart';

import '../../core/theme/app_colors.dart';
import '../../models/app_settings.dart';
import '../../models/audio_info.dart';
import '../../models/song_source.dart';
import '../../providers/audio_info_providers.dart';
import '../../providers/user_data_providers.dart';
import '../../widgets/song_labels.dart';
import '../../l10n/labels.dart';

/// Quality, codec and source chips for the Songs tab.
class SongFilterBar extends ConsumerWidget {
  const SongFilterBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filter = ref.watch(settingsProvider.select((s) => s.songFilter));
    final counts = ref.watch(filterCountsProvider);
    final notifier = ref.read(settingsProvider.notifier);
    final palette = context.palette;

    void set(SongFilter next) {
      HapticFeedback.selectionClick();
      notifier.setSongFilter(next);
    }

    final codecs = counts.codecs.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    final categories = counts.categories.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    final showCodecs = codecs.length > 1 || filter.codecs.isNotEmpty;
    final showCategories = categories.length > 1 || filter.categories.isNotEmpty;

    Widget row(List<Widget> chips) => SizedBox(
          height: 40,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 20),
            children: [
              for (final (i, chip) in chips.indexed) ...[
                if (i > 0) const SizedBox(width: 8),
                chip,
              ],
            ],
          ),
        );

    final qualityChips = <Widget>[
      _Chip(
        label: context.l10n.all,
        selected: filter.quality == null,
        onTap: () => set(filter.copyWith(quality: () => null)),
      ),
      for (final q in [AudioQuality.hiRes, AudioQuality.lossless, AudioQuality.lossy])
        if ((counts.quality[q] ?? 0) > 0 || filter.quality == q)
          _Chip(
            label: context.l10n.quality(q),
            count: counts.quality[q] ?? 0,
            color: q.color(palette),
            icon: q == AudioQuality.hiRes ? HugeIcons.strokeRoundedDiamond01 : null,
            selected: filter.quality == q,
            onTap: () => set(filter.copyWith(quality: () => filter.quality == q ? null : q)),
          ),
    ];

    final codecChips = <Widget>[
      for (final e in codecs)
        _Chip(
          label: e.key,
          count: e.value,
          color: AudioInfo.losslessCodecs.contains(e.key) ? palette.lossless : null,
          selected: filter.codecs.contains(e.key),
          onTap: () => set(filter.copyWith(codecs: _toggle(filter.codecs, e.key))),
        ),
    ];

    final categoryChips = <Widget>[
      for (final e in categories)
        _Chip(
          label: context.l10n.sourceCategory(e.key),
          count: e.value,
          icon: e.key.icon,
          selected: filter.categories.contains(e.key),
          onTap: () => set(filter.copyWith(categories: _toggle<SourceCategory>(filter.categories, e.key))),
        ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        row([...qualityChips, if (showCodecs) const _Divider(), if (showCodecs) ...codecChips]),
        if (showCategories) ...[const SizedBox(height: 6), row(categoryChips)],
      ],
    );
  }

  static Set<T> _toggle<T>(Set<T> set, T value) =>
      set.contains(value) ? ({...set}..remove(value)) : {...set, value};
}

class _Divider extends StatelessWidget {
  const _Divider();

  @override
  Widget build(BuildContext context) => Center(
        child: Container(width: 1, height: 20, color: context.palette.line),
      );
}

class _Chip extends StatelessWidget {
  const _Chip({
    required this.label,
    required this.selected,
    required this.onTap,
    this.count,
    this.color,
    this.icon,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final int? count;

  /// Accent for quality chips (lossless green, Hi-Res gold).
  final Color? color;
  final List<List<dynamic>>? icon;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final accent = color ?? palette.ink;
    final fg = selected ? (color == null ? palette.onInk : palette.background) : (color ?? palette.ink);
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? accent : palette.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: selected ? accent : palette.line),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              HugeIcon(icon: icon!, color: fg, size: 14),
              const SizedBox(width: 6),
            ],
            Text(label, style: TextStyle(color: fg, fontWeight: FontWeight.w700, fontSize: 13)),
            if (count != null) ...[
              const SizedBox(width: 6),
              Text(
                '$count',
                style: TextStyle(
                  color: fg.withValues(alpha: 0.65),
                  fontWeight: FontWeight.w600,
                  fontSize: 12,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
