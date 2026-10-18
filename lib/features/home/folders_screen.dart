import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hugeicons/hugeicons.dart';

import '../../core/format.dart';
import '../../core/theme/app_colors.dart';
import '../../providers/library_providers.dart';
import '../../providers/user_data_providers.dart';

/// Every folder that contains audio (untick one to hide it and skip it in
/// scans), plus hidden folders granted through the system folder picker.
class FoldersScreen extends ConsumerWidget {
  const FoldersScreen({super.key});

  static Future<void> open(BuildContext context) => Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => const FoldersScreen()),
      );

  /// `/storage/emulated/0/Music/Rock` → `Internal storage › Music › Rock`.
  static String label(String path) {
    const internal = '/storage/emulated/0';
    if (path == internal) return 'Internal storage';
    if (path.startsWith('$internal/')) {
      return 'Internal storage › ${path.substring(internal.length + 1).replaceAll('/', ' › ')}';
    }
    final sd = RegExp(r'^/storage/([0-9A-Fa-f]{4}-[0-9A-Fa-f]{4})(/.*)?$').firstMatch(path);
    if (sd != null) {
      final rest = sd.group(2);
      return rest == null ? 'SD card' : 'SD card${rest.replaceAll('/', ' › ')}';
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
          SnackBar(content: Text('Scanning ${label(folder.path ?? 'folder')}…')),
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
        title: const Text('Folders', style: TextStyle(fontWeight: FontWeight.w800)),
        leading: IconButton(
          tooltip: 'Back',
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
              'audifac scans your whole phone and SD card automatically. '
              'Untick a folder to hide its audio and skip it when scanning.',
              style: theme.textTheme.bodyMedium,
            ),
          ),
          section('Folders with audio'),
          if (folders.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              child: Text('None found yet.', style: theme.textTheme.bodyMedium),
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
              title: Text(label(folder.path), style: const TextStyle(fontWeight: FontWeight.w600)),
              subtitle: Text(pluralize(folder.count, 'file')),
            ),
          section('Hidden folders'),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Text(
              'Android hides some folders from apps (those with a ".nomedia" file, '
              'like WhatsApp voice notes). Add one here to include its audio.',
              style: theme.textTheme.bodyMedium,
            ),
          ),
          for (final folder in granted)
            ListTile(
              contentPadding: const EdgeInsets.only(left: 20, right: 8),
              leading: HugeIcon(icon: HugeIcons.strokeRoundedFolderMusic, color: palette.ink, size: 22),
              title: Text(
                label(folder.path ?? folder.uri),
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              trailing: IconButton(
                tooltip: 'Remove',
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
                label: const Text('Add a folder', style: TextStyle(fontWeight: FontWeight.w700)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
