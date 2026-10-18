import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hugeicons/hugeicons.dart';

import '../../core/theme/app_colors.dart';
import '../../providers/library_providers.dart';
import '../../providers/user_data_providers.dart';
import '../../l10n/l10n.dart';

/// Every folder that contains audio (untick one to hide it and skip it in
/// scans), plus hidden folders granted through the system folder picker.
class FoldersScreen extends ConsumerWidget {
  const FoldersScreen({super.key});

  static Future<void> open(BuildContext context) => Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => const FoldersScreen()),
      );

  /// `/storage/emulated/0/Music/Rock` → `Internal storage › Music › Rock`.
  static String label(AppLocalizations l10n, String path) {
    const internal = '/storage/emulated/0';
    if (path == internal) return l10n.internalStorage;
    if (path.startsWith('$internal/')) {
      return '${l10n.internalStorage} › ${path.substring(internal.length + 1).replaceAll('/', ' › ')}';
    }
    final sd = RegExp(r'^/storage/([0-9A-Fa-f]{4}-[0-9A-Fa-f]{4})(/.*)?$').firstMatch(path);
    if (sd != null) {
      final rest = sd.group(2);
      return rest == null ? l10n.sdCard : '${l10n.sdCard}${rest.replaceAll('/', ' › ')}';
    }
    return path;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final folders = ref.watch(audioFoldersProvider);
    final granted = ref.watch(grantedFoldersProvider).value ?? const [];
    final settings = ref.watch(settingsProvider);
    final notifier = ref.read(settingsProvider.notifier);
    final library = ref.read(mediaLibraryProvider);
    final theme = Theme.of(context);
    final palette = context.palette;

    Future<void> addFolder() async {
      final folder = await library.pickFolder();
      if (folder == null) return;
      ref.invalidate(grantedFoldersProvider);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.l10n.scanningFolder(label(context.l10n, folder.path ?? '')))),
        );
      }
      await ref.read(libraryProvider.notifier).refresh();
    }

    Future<void> removeFolder(String uri) async {
      await library.removeFolder(uri);
      ref.invalidate(grantedFoldersProvider);
      await ref.read(libraryProvider.notifier).refresh();
    }

    Widget section(String text) => Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 6),
          child: Text(text, style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
        );

    return Scaffold(
      appBar: AppBar(
        title: Text(context.l10n.foldersTitle, style: TextStyle(fontWeight: FontWeight.w800)),
        leading: IconButton(
          tooltip: context.l10n.back,
          onPressed: () => Navigator.of(context).pop(),
          icon: HugeIcon(icon: HugeIcons.strokeRoundedArrowLeft01, color: palette.ink, size: 26),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Text(
              context.l10n.foldersIntro,
              style: theme.textTheme.bodyMedium,
            ),
          ),
          section(context.l10n.foldersWithAudio),
          if (folders.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              child: Text(context.l10n.noneFoundYet, style: theme.textTheme.bodyMedium),
            ),
          for (final folder in folders)
            CheckboxListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 20),
              activeColor: palette.ink,
              checkColor: palette.onInk,
              value: !settings.isExcluded(folder.path),
              // A folder whose parent is excluded can't be re-included on its own.
              enabled: !settings.excludedFolders.any((e) => folder.path.startsWith('$e/')),
              onChanged: (included) => notifier.setFolderExcluded(folder.path, !(included ?? true)),
              title: Text(label(context.l10n, folder.path), style: const TextStyle(fontWeight: FontWeight.w600)),
              subtitle: Text(context.l10n.files(folder.count)),
            ),
          section(context.l10n.hiddenFolders),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Text(
              context.l10n.hiddenFoldersIntro,
              style: theme.textTheme.bodyMedium,
            ),
          ),
          for (final folder in granted)
            ListTile(
              contentPadding: const EdgeInsets.only(left: 20, right: 8),
              leading: HugeIcon(icon: HugeIcons.strokeRoundedFolderMusic, color: palette.ink, size: 22),
              title: Text(
                label(context.l10n, folder.path ?? folder.uri),
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              trailing: IconButton(
                tooltip: context.l10n.remove,
                onPressed: () => removeFolder(folder.uri),
                icon: HugeIcon(icon: HugeIcons.strokeRoundedCancel01, color: palette.inkMuted, size: 20),
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
            child: Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                onPressed: addFolder,
                style: OutlinedButton.styleFrom(
                  foregroundColor: palette.ink,
                  side: BorderSide(color: palette.line, width: 1.5),
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                ),
                icon: HugeIcon(icon: HugeIcons.strokeRoundedAdd01, color: palette.ink, size: 18),
                label: Text(context.l10n.addFolder, style: TextStyle(fontWeight: FontWeight.w700)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
