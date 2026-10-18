import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hugeicons/hugeicons.dart';

import '../../core/theme/app_colors.dart';
import '../../providers/audio_info_providers.dart';
import '../../providers/eq_providers.dart';
import '../../providers/loudness_providers.dart';
import '../equalizer/quick_eq_sheet.dart';
import '../../providers/library_providers.dart';
import '../../providers/player_providers.dart';
import '../../providers/session_controller.dart';
import '../../widgets/mini_player.dart';
import '../favorites/favorites_screen.dart';
import '../home/home_screen.dart';
import '../library/library_screen.dart';
import '../search/search_screen.dart';

/// Bottom navigation + docked mini player. Each tab has its own navigator so
/// album/artist pages open inside the tab and the mini player stays visible.
class AppShell extends ConsumerStatefulWidget {
  const AppShell({super.key});

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell> {
  static const _tabs = [
    (icon: HugeIcons.strokeRoundedHome03, label: 'Home', root: HomeScreen()),
    (icon: HugeIcons.strokeRoundedLibrary, label: 'Library', root: LibraryScreen()),
    (icon: HugeIcons.strokeRoundedSearch01, label: 'Search', root: SearchScreen()),
    (icon: HugeIcons.strokeRoundedFavourite, label: 'Favorites', root: FavoritesScreen()),
  ];

  final _navigatorKeys = List.generate(_tabs.length, (_) => GlobalKey<NavigatorState>());
  int _index = 0;

  // Back in the app (e.g. after downloading music): rescan if it's been a while.
  late final _lifecycle = AppLifecycleListener(
    onResume: () => ref.read(libraryProvider.notifier).scanStorage(onlyIfStale: true),
  );

  @override
  void initState() {
    super.initState();
    _lifecycle; // Start listening.
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  void _onDestinationSelected(int index) {
    HapticFeedback.selectionClick();
    if (index == _index) {
      // Re-tapping the current tab goes back to its root.
      _navigatorKeys[index].currentState?.popUntil((route) => route.isFirst);
      return;
    }
    setState(() => _index = index);
  }

  void _onBack() {
    final navigator = _navigatorKeys[_index].currentState;
    if (navigator != null && navigator.canPop()) {
      navigator.pop();
    } else if (_index != 0) {
      setState(() => _index = 0);
    } else {
      SystemNavigator.pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    // Restores / saves the playback session and records history.
    ref.watch(sessionControllerProvider);
    // Starts (and keeps alive) the background codec analysis, without
    // rebuilding the shell on every batch.
    ref.listen(audioInfoProvider, (_, _) {});
    // Keeps the native DSP in sync with presets, rules and the output device.
    ref.listen(dspSyncProvider, (_, _) {});
    // Volume matching settings and per-song gains for the queue.
    ref.listen(volumeSyncProvider, (_, _) {});
    // A new queue started and no rule decides its sound: offer a choice.
    ref.listen(eqPromptProvider, (_, song) {
      if (song == null) return;
      ref.read(eqPromptProvider.notifier).clear();
      QuickEqSheet.show(context, song: song, prompt: true);
    });

    ref.listen(playbackErrorsProvider, (_, next) {
      final message = next.value;
      if (message == null) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(message)));
    });

    final palette = context.palette;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _onBack();
      },
      child: Scaffold(
        body: IndexedStack(
          index: _index,
          children: [
            for (var i = 0; i < _tabs.length; i++)
              HeroControllerScope.none(
                child: Navigator(
                  key: _navigatorKeys[i],
                  onGenerateRoute: (_) => MaterialPageRoute<void>(
                    builder: (_) => _tabs[i].root,
                  ),
                ),
              ),
          ],
        ),
        bottomNavigationBar: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const MiniPlayer(),
            NavigationBar(
              selectedIndex: _index,
              onDestinationSelected: _onDestinationSelected,
              destinations: [
                for (final tab in _tabs)
                  NavigationDestination(
                    label: tab.label,
                    tooltip: tab.label,
                    icon: HugeIcon(icon: tab.icon, color: palette.inkMuted, size: 24),
                    selectedIcon: HugeIcon(icon: tab.icon, color: palette.ink, size: 24),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
