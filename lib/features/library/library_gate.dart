import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hugeicons/hugeicons.dart';
import '../../l10n/l10n.dart';

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
              title: context.l10n.couldNotReadMusic,
              message: '$error',
              actionLabel: context.l10n.tryAgain,
              onAction: notifier.rescan,
            ),
      data: (all) {
        if (visible.isNotEmpty) return builder(context, visible);
        if (all.isEmpty && scanning) return const _Searching();
        if (all.isEmpty) {
          return EmptyState(
            icon: HugeIcons.strokeRoundedFolderMusic,
            title: context.l10n.noAudioFound,
            message: context.l10n.noAudioFoundHint,
            actionLabel: context.l10n.scanAgain,
            onAction: notifier.refresh,
          );
        }
        return EmptyState(
          icon: HugeIcons.strokeRoundedFolderMusic,
          title: context.l10n.everythingHidden,
          message: context.l10n.everythingHiddenHint(all.length),
          actionLabel: context.l10n.librarySettings,
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
      title: context.l10n.allowAccessTitle,
      message: widget.permanent
          ? context.l10n.accessTurnedOff
          : context.l10n.accessNeeded,
      actionLabel: widget.permanent ? context.l10n.openSettings : context.l10n.allowAccess,
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
              context.l10n.searchingPhone,
              textAlign: TextAlign.center,
              style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Text(
              context.l10n.searchingPhoneHint,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium,
            ),
          ],
        ),
      ),
    );
  }
}
