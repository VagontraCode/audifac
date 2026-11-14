import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hugeicons/hugeicons.dart';

import '../../core/theme/app_colors.dart';
import '../../l10n/l10n.dart';
import '../../models/soiree.dart';
import '../../providers/library_providers.dart';
import '../../providers/soiree_plan_provider.dart';

/// Soirée → Keep apart: artist pairs never played close together.
class KeepApartSheet extends ConsumerWidget {
  const KeepApartSheet({super.key});

  static Future<void> show(BuildContext context) => showModalBottomSheet<void>(
        context: context,
        useRootNavigator: true,
        isScrollControlled: true,
        builder: (_) => const KeepApartSheet(),
      );

  /// The artist names as the library spells them (keys are lowercase).
  static Map<String, String> _names(WidgetRef ref) =>
      {for (final a in ref.read(artistsProvider)) a.name.trim().toLowerCase(): a.name};

  Future<void> _add(BuildContext context, WidgetRef ref) async {
    final l10n = context.l10n;
    final first = await _ArtistPicker.pick(context, l10n.keepApartFirst);
    if (first == null || !context.mounted) return;
    final second = await _ArtistPicker.pick(context, l10n.keepApartSecond(first), exclude: first);
    if (second == null) return;
    ref.read(soireeProvider.notifier).keepApart(first, second);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final palette = context.palette;
    final pairs = ref.watch(soireeProvider.select((s) => s.keepApart)).toList()..sort();
    final names = _names(ref);
    String name(String key) => names[key] ?? key;

    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.8),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 4),
              child: Text(l10n.keepApart, style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
              child: Text(l10n.keepApartHint, style: theme.textTheme.bodySmall?.copyWith(color: palette.inkMuted)),
            ),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final key in pairs)
                    () {
                      final (a, b) = KeepApart.artists(key);
                      return ListTile(
                        contentPadding: const EdgeInsets.only(left: 24, right: 12),
                        title: Text('${name(a)}  ↮  ${name(b)}', style: const TextStyle(fontWeight: FontWeight.w600)),
                        trailing: IconButton(
                          tooltip: l10n.remove,
                          onPressed: () => ref.read(soireeProvider.notifier).allowTogether(key),
                          icon: HugeIcon(icon: HugeIcons.strokeRoundedCancel01, color: palette.inkMuted, size: 18),
                        ),
                      );
                    }(),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
              child: FilledButton.icon(
                onPressed: () => _add(context, ref),
                icon: HugeIcon(icon: HugeIcons.strokeRoundedAdd01, color: palette.onInk, size: 18),
                label: Text(l10n.keepApartAdd),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A searchable list of the library's artists.
class _ArtistPicker extends ConsumerStatefulWidget {
  const _ArtistPicker({required this.title, this.exclude});

  final String title;
  final String? exclude;

  static Future<String?> pick(BuildContext context, String title, {String? exclude}) => showModalBottomSheet<String>(
        context: context,
        useRootNavigator: true,
        isScrollControlled: true,
        builder: (_) => _ArtistPicker(title: title, exclude: exclude),
      );

  @override
  ConsumerState<_ArtistPicker> createState() => _ArtistPickerState();
}

class _ArtistPickerState extends ConsumerState<_ArtistPicker> {
  var _query = '';

  @override
  Widget build(BuildContext context) {
    final q = _query.trim().toLowerCase();
    final artists = [
      for (final a in ref.watch(artistsProvider))
        if (a.name != widget.exclude && (q.isEmpty || a.name.toLowerCase().contains(q))) a,
    ];
    return SizedBox(
      height: MediaQuery.sizeOf(context).height * 0.8,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
              child: Text(widget.title, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: TextField(
                autofocus: true,
                decoration: InputDecoration(hintText: context.l10n.searchArtists),
                onChanged: (v) => setState(() => _query = v),
              ),
            ),
            Expanded(
              child: ListView.builder(
                itemCount: artists.length,
                itemBuilder: (context, i) => ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 24),
                  title: Text(artists[i].name),
                  subtitle: Text(context.l10n.songs(artists[i].songs.length)),
                  onTap: () => Navigator.pop(context, artists[i].name),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
