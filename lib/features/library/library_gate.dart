import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hugeicons/hugeicons.dart';

import '../../models/song.dart';
import '../../providers/library_providers.dart';
import '../../widgets/empty_state.dart';
import '../home/settings_sheet.dart';

/// Shows loading / permission / empty states, and [builder] once the library
/// has songs.
class LibraryGate extends ConsumerWidget {
  const LibraryGate({super.key, required this.builder});

  final Widget Function(BuildContext context, List<Song> songs) builder;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final library = ref.watch(libraryProvider);
    final visible = ref.watch(songsProvider);
    final scanning = ref.watch(scanStatusProvider.select((s) => s.running));
    final notifier = ref.read(libraryProvider.notifier);

    return library.when(
      skipLoadingOnRefresh: true,
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => error is LibraryAccessDenied
          ? _AccessDenied(permanent: error.permanent)
          : EmptyState(
              icon: HugeIcons.strokeRoundedCancel01,
              title: 'Could not read your music',
              message: '$error',
              actionLabel: 'Try again',
              onAction: notifier.rescan,
            ),
      data: (all) {
        if (visible.isNotEmpty) return builder(context, visible);
        if (all.isEmpty && scanning) return const _Searching();
        if (all.isEmpty) {
          return EmptyState(
            icon: HugeIcons.strokeRoundedFolderMusic,
            title: 'No audio found',
            message: 'audifac looked through your whole phone and SD card. '
                'Copy some audio files to the device, then scan again.',
            actionLabel: 'Scan again',
            onAction: notifier.refresh,
          );
        }
        return EmptyState(
          icon: HugeIcons.strokeRoundedFolderMusic,
          title: 'Everything is hidden',
          message: '${all.length} audio files were found, but your library filters '
              '(minimum length, recordings, excluded folders) hide them all.',
          actionLabel: 'Library settings',
          onAction: () => SettingsSheet.show(context),
        );
      },
    );
  }
}

class _AccessDenied extends ConsumerStatefulWidget {
  const _AccessDenied({required this.permanent});

  final bool permanent;

  @override
  ConsumerState<_AccessDenied> createState() => _AccessDeniedState();
}

class _AccessDeniedState extends ConsumerState<_AccessDenied> {
  // Coming back from system settings: check whether access was granted.
  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(
      onResume: () => ref.read(libraryProvider.notifier).recheckAccess(),
    );
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return EmptyState(
      icon: HugeIcons.strokeRoundedMusicNoteSquare01,
      title: 'Allow access to your music',
      message: widget.permanent
          ? 'Access was turned off. Enable "Music and audio" for audifac in system settings.'
          : 'audifac needs permission to find the songs stored on this device.',
      actionLabel: widget.permanent ? 'Open settings' : 'Allow access',
      onAction: () => ref.read(libraryProvider.notifier).requestAccess(),
    );
  }
}

class _Searching extends StatelessWidget {
  const _Searching();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 24),
            Text(
              'Searching your phone for audio…',
              textAlign: TextAlign.center,
              style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Text(
              'Internal storage and SD card, every folder.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium,
            ),
          ],
        ),
      ),
    );
  }
}
