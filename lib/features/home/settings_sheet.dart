import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hugeicons/hugeicons.dart';

import '../../core/theme/app_colors.dart';
import '../../models/app_settings.dart';
import '../../models/backup.dart';
import '../../providers/backup_provider.dart';
import '../../providers/audio_info_providers.dart';
import '../../providers/eq_providers.dart';
import '../equalizer/equalizer_screen.dart';
import '../../providers/library_providers.dart';
import '../../providers/lastfm_provider.dart';
import '../../providers/loudness_providers.dart';
import '../../providers/user_data_providers.dart';
import '../../providers/widget_provider.dart';
import 'lastfm_sheet.dart';
import 'folders_screen.dart';
import 'volume_matching_sheet.dart';
import '../../l10n/l10n.dart';

class SettingsSheet extends ConsumerWidget {
  const SettingsSheet({super.key});

  static Future<void> show(BuildContext context) => showModalBottomSheet<void>(
        context: context,
        useRootNavigator: true,
        isScrollControlled: true,
        builder: (_) => const SettingsSheet(),
      );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final notifier = ref.read(settingsProvider.notifier);
    final visibleCount = ref.watch(songsProvider).length;
    final totalCount = ref.watch(libraryProvider).value?.length;
    final scan = ref.watch(scanStatusProvider);
    final analysis = ref.watch(analysisStatusProvider);
    final theme = Theme.of(context);
    final palette = context.palette;

    Widget heading(String text) => Padding(
          padding: const EdgeInsets.only(top: 20, bottom: 10),
          child: Text(text, style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
        );

    final segmentedStyle = SegmentedButton.styleFrom(
      selectedBackgroundColor: palette.ink,
      selectedForegroundColor: palette.onInk,
      foregroundColor: palette.ink,
      side: BorderSide(color: palette.line),
    );

    final scanSubtitle = scan.running
        ? context.l10n.scanningStorage
        : [
            if (totalCount != null)
              totalCount != visibleCount ? context.l10n.shownOfFound(totalCount, visibleCount) : context.l10n.shown(visibleCount),
            if (scan.last case final last?)
              context.l10n.scannedIn(last.found, (last.elapsed.inMilliseconds / 1000).toStringAsFixed(1)),
            if (scan.error != null) context.l10n.lastScanFailed('${scan.error}'),
          ].join('\n');

    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.85),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(context.l10n.settings, style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
              heading(context.l10n.appearance),
              SizedBox(
                width: double.infinity,
                child: SegmentedButton<ThemeMode>(
                  showSelectedIcon: false,
                  style: segmentedStyle,
                  segments: [
                    ButtonSegment(value: ThemeMode.system, label: Text(context.l10n.themeSystem)),
                    ButtonSegment(value: ThemeMode.light, label: Text(context.l10n.themeLight)),
                    ButtonSegment(value: ThemeMode.dark, label: Text(context.l10n.themeDark)),
                  ],
                  selected: {settings.themeMode},
                  onSelectionChanged: (s) => notifier.setThemeMode(s.first),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: SegmentedButton<String>(
                  showSelectedIcon: false,
                  style: segmentedStyle,
                  segments: [
                    ButtonSegment(value: '', label: Text(context.l10n.languageSystem)),
                    const ButtonSegment(value: 'en', label: Text('English')),
                    const ButtonSegment(value: 'fr', label: Text('Français')),
                  ],
                  selected: {settings.languageCode},
                  onSelectionChanged: (s) => notifier.setLanguage(s.first),
                ),
              ),
              heading(context.l10n.sound),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: HugeIcon(icon: HugeIcons.strokeRoundedSlidersHorizontal, color: palette.ink, size: 22),
                title: Text(context.l10n.equalizer, style: TextStyle(fontWeight: FontWeight.w600)),
                subtitle: Text(ref.watch(eqSettingsProvider.select((s) => s.enabled))
                    ? context.l10n.equalizerOnSummary
                    : context.l10n.off),
                trailing: HugeIcon(icon: HugeIcons.strokeRoundedArrowRight01, color: palette.inkMuted, size: 20),
                onTap: () {
                  Navigator.of(context).pop();
                  EqualizerScreen.open(context);
                },
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: HugeIcon(icon: HugeIcons.strokeRoundedVolumeHigh, color: palette.ink, size: 22),
                title: Text(context.l10n.volumeMatching, style: TextStyle(fontWeight: FontWeight.w600)),
                subtitle: Text(VolumeMatchingSheet.describe(context.l10n, ref.watch(volumeMatchingProvider))),
                trailing: HugeIcon(icon: HugeIcons.strokeRoundedArrowRight01, color: palette.inkMuted, size: 20),
                onTap: () {
                  Navigator.of(context).pop();
                  VolumeMatchingSheet.show(context);
                },
              ),
              const SizedBox(height: 8),
              Text(context.l10n.crossfade, style: TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: SegmentedButton<int>(
                  showSelectedIcon: false,
                  style: segmentedStyle,
                  segments: [
                    for (final s in AppSettings.crossfadeChoices)
                      ButtonSegment(value: s, label: Text(s == 0 ? context.l10n.offShort : context.l10n.seconds(s))),
                  ],
                  selected: {settings.crossfadeSeconds},
                  onSelectionChanged: (s) => notifier.setCrossfade(s.first),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                settings.crossfadeSeconds == 0
                    ? context.l10n.crossfadeOffHint
                    : context.l10n.crossfadeOnHint,
                style: theme.textTheme.bodySmall?.copyWith(color: palette.inkMuted),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                activeThumbColor: palette.onInk,
                activeTrackColor: palette.ink,
                title: Text(context.l10n.keepAlbumsTogether, style: TextStyle(fontWeight: FontWeight.w600)),
                subtitle: Text(context.l10n.keepAlbumsTogetherHint),
                value: settings.keepAlbumsTogether,
                onChanged: notifier.setKeepAlbumsTogether,
              ),
              heading(context.l10n.tabLibrary),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: scan.running
                    ? const SizedBox.square(
                        dimension: 22,
                        child: CircularProgressIndicator(strokeWidth: 2.5),
                      )
                    : HugeIcon(icon: HugeIcons.strokeRoundedRefresh, color: palette.ink, size: 22),
                title: Text(context.l10n.scanDevice, style: TextStyle(fontWeight: FontWeight.w600)),
                subtitle: scanSubtitle.isEmpty ? null : Text(scanSubtitle),
                onTap: scan.running ? null : () => ref.read(libraryProvider.notifier).refresh(),
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: HugeIcon(icon: HugeIcons.strokeRoundedFolderMusic, color: palette.ink, size: 22),
                title: Text(context.l10n.foldersTitle, style: TextStyle(fontWeight: FontWeight.w600)),
                subtitle: Text(
                  settings.excludedFolders.isEmpty
                      ? context.l10n.allFoldersIncluded
                      : context.l10n.foldersExcluded(settings.excludedFolders.length),
                ),
                trailing: HugeIcon(icon: HugeIcons.strokeRoundedArrowRight01, color: palette.inkMuted, size: 20),
                onTap: () => FoldersScreen.open(context),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                activeThumbColor: palette.onInk,
                activeTrackColor: palette.ink,
                title: Text(context.l10n.showLabels, style: TextStyle(fontWeight: FontWeight.w600)),
                subtitle: Text(
                  analysis.running
                      ? context.l10n.showLabelsAnalysing(analysis.done, analysis.total)
                      : context.l10n.showLabelsHint,
                ),
                value: settings.showLabels,
                onChanged: notifier.setShowLabels,
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                activeThumbColor: palette.onInk,
                activeTrackColor: palette.ink,
                title: Text(context.l10n.showRecordings, style: TextStyle(fontWeight: FontWeight.w600)),
                subtitle: Text(context.l10n.showRecordingsHint),
                value: settings.includeRecordings,
                onChanged: notifier.setIncludeRecordings,
              ),
              const SizedBox(height: 8),
              Text(context.l10n.hideShorterThan, style: TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: SegmentedButton<int>(
                  showSelectedIcon: false,
                  style: segmentedStyle,
                  segments: [
                    for (final s in AppSettings.minDurationChoices)
                      ButtonSegment(value: s, label: Text(s == 0 ? context.l10n.offShort : context.l10n.seconds(s))),
                  ],
                  selected: {settings.minDurationSeconds},
                  onSelectionChanged: (s) => notifier.setMinDuration(s.first),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                context.l10n.ringtonesHidden,
                style: theme.textTheme.bodySmall?.copyWith(color: palette.inkMuted),
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: HugeIcon(icon: HugeIcons.strokeRoundedDashboardSquare02, color: palette.ink, size: 22),
                title: Text(context.l10n.addWidget, style: TextStyle(fontWeight: FontWeight.w600)),
                onTap: () async {
                  final messenger = ScaffoldMessenger.of(context);
                  final hint = context.l10n.addWidgetManually;
                  if (!await pinHomeWidget()) {
                    messenger.showSnackBar(SnackBar(
                      content: Text(hint),
                    ));
                  }
                },
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: HugeIcon(icon: HugeIcons.strokeRoundedRadio01, color: palette.ink, size: 22),
                title: const Text('Last.fm', style: TextStyle(fontWeight: FontWeight.w600)),
                subtitle: Text(switch (ref.watch(lastFmProvider)) {
                  final s when s.account?.connected ?? false => context.l10n.lastFmConnectedAs(s.account!.username ?? ''),
                  _ => context.l10n.lastFmOff,
                }),
                trailing: HugeIcon(icon: HugeIcons.strokeRoundedArrowRight01, color: palette.inkMuted, size: 20),
                onTap: () {
                  Navigator.of(context).pop();
                  LastFmSheet.show(context);
                },
              ),
              heading(context.l10n.backup),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: HugeIcon(icon: HugeIcons.strokeRoundedCloudUpload, color: palette.ink, size: 22),
                title: Text(context.l10n.backUpToFile, style: TextStyle(fontWeight: FontWeight.w600)),
                subtitle: Text(context.l10n.backUpHint),
                onTap: () => _backup(context, ref),
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: HugeIcon(icon: HugeIcons.strokeRoundedCloudDownload, color: palette.ink, size: 22),
                title: Text(context.l10n.restoreFromFile, style: TextStyle(fontWeight: FontWeight.w600)),
                subtitle: Text(context.l10n.restoreHint),
                onTap: () => _restore(context, ref),
              ),
              heading(context.l10n.about),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: HugeIcon(icon: HugeIcons.strokeRoundedInformationCircle, color: palette.ink, size: 22),
                title: Text(context.l10n.aboutAudifac, style: TextStyle(fontWeight: FontWeight.w600)),
                onTap: () => showLicensePage(context: context, applicationName: 'audifac'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _backup(BuildContext context, WidgetRef ref) async {
    // Grab everything before closing the sheet (its ref dies with it), and
    // close it so the confirmation is visible.
    final messenger = ScaffoldMessenger.of(context);
    final l10n = context.l10n;
    final library = ref.read(mediaLibraryProvider);
    final backup = ref.read(backupServiceProvider);
    Navigator.of(context).pop();
    try {
      final data = backup.create(appVersion: await library.appVersion());
      final d = data.exportedAt;
      String two(int n) => n.toString().padLeft(2, '0');
      final saved = await library.saveTextDocument(
        name: 'audifac-backup-${d.year}-${two(d.month)}-${two(d.day)}.json',
        text: data.encode(),
      );
      if (saved == null) return; // Cancelled.
      messenger.showSnackBar(SnackBar(
        content: Text(l10n.backedUp(l10n.favoritesCount(data.favorites.length), l10n.playlistsCount(data.playlists.length), l10n.eqPresets(data.eqPresets.length))),
      ));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(l10n.backupFailed('$e'))));
    }
  }

  Future<void> _restore(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    final l10n = context.l10n;
    final root = Navigator.of(context, rootNavigator: true);
    final library = ref.read(mediaLibraryProvider);
    final backup = ref.read(backupServiceProvider);
    Navigator.of(context).pop();
    final doc = await library.openTextDocument();
    if (doc == null) return;
    final BackupData data;
    try {
      data = BackupData.decode(doc.text);
    } on FormatException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(l10n.cantRestore(e.message))));
      return;
    }
    final report = await backup.restore(data);
    if (!root.mounted) return;
    await showDialog<void>(
      context: root.context,
      builder: (context) => AlertDialog(
        title: Text(context.l10n.restored),
        content: Text([
          context.l10n.fromBackupOf(data.exportedAt.toLocal().toString().substring(0, 16), data.appVersion),
          '',
          '• ${context.l10n.newFavorites(report.favorites)}',
          '• ${context.l10n.playlistsCount(report.playlists)} (${context.l10n.songs(report.playlistSongs)})',
          '• ${context.l10n.eqPresets(report.presets)}, ${context.l10n.rules(report.rules)}',
          '• ${context.l10n.historyEntries(report.recent)}',
          if (report.plays > 0) '• ${context.l10n.listensRestored(report.plays)}',
          if (report.settings) '• ${context.l10n.settings}',
          if (report.missingSongs > 0)
            '\n${context.l10n.missingSongs(report.missingSongs)}',
        ].join('\n')),
        actions: [FilledButton(onPressed: () => Navigator.pop(context), child: Text(context.l10n.ok))],
      ),
    );
  }
}
