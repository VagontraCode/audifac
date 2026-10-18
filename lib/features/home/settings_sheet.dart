import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hugeicons/hugeicons.dart';

import '../../core/format.dart';
import '../../core/theme/app_colors.dart';
import '../../models/app_settings.dart';
import '../../models/backup.dart';
import '../../providers/backup_provider.dart';
import '../../providers/audio_info_providers.dart';
import '../../providers/eq_providers.dart';
import '../equalizer/equalizer_screen.dart';
import '../../providers/library_providers.dart';
import '../../providers/loudness_providers.dart';
import '../../providers/user_data_providers.dart';
import 'folders_screen.dart';
import 'volume_matching_sheet.dart';

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
        ? 'Scanning internal storage and SD card…'
        : [
            if (totalCount != null)
              '$visibleCount shown${totalCount != visibleCount ? ' of $totalCount found' : ''}',
            if (scan.last case final last?)
              '${pluralize(last.found, 'file')} on storage, scanned in ${(last.elapsed.inMilliseconds / 1000).toStringAsFixed(1)} s',
            if (scan.error != null) 'Last scan failed: ${scan.error}',
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
              Text('Settings', style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
              heading('Appearance'),
              SizedBox(
                width: double.infinity,
                child: SegmentedButton<ThemeMode>(
                  showSelectedIcon: false,
                  style: segmentedStyle,
                  segments: const [
                    ButtonSegment(value: ThemeMode.system, label: Text('System')),
                    ButtonSegment(value: ThemeMode.light, label: Text('Light')),
                    ButtonSegment(value: ThemeMode.dark, label: Text('Dark')),
                  ],
                  selected: {settings.themeMode},
                  onSelectionChanged: (s) => notifier.setThemeMode(s.first),
                ),
              ),
              heading('Sound'),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: HugeIcon(icon: HugeIcons.strokeRoundedSlidersHorizontal, color: palette.ink, size: 22),
                title: const Text('Equalizer', style: TextStyle(fontWeight: FontWeight.w600)),
                subtitle: Text(ref.watch(eqSettingsProvider.select((s) => s.enabled))
                    ? 'On · presets, headphone correction, rules'
                    : 'Off'),
                trailing: HugeIcon(icon: HugeIcons.strokeRoundedArrowRight01, color: palette.inkMuted, size: 20),
                onTap: () {
                  Navigator.of(context).pop();
                  EqualizerScreen.open(context);
                },
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: HugeIcon(icon: HugeIcons.strokeRoundedVolumeHigh, color: palette.ink, size: 22),
                title: const Text('Volume matching', style: TextStyle(fontWeight: FontWeight.w600)),
                subtitle: Text(VolumeMatchingSheet.describe(ref.watch(volumeMatchingProvider))),
                trailing: HugeIcon(icon: HugeIcons.strokeRoundedArrowRight01, color: palette.inkMuted, size: 20),
                onTap: () {
                  Navigator.of(context).pop();
                  VolumeMatchingSheet.show(context);
                },
              ),
              const SizedBox(height: 8),
              const Text('Crossfade', style: TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: SegmentedButton<int>(
                  showSelectedIcon: false,
                  style: segmentedStyle,
                  segments: [
                    for (final s in AppSettings.crossfadeChoices)
                      ButtonSegment(value: s, label: Text(s == 0 ? 'Off' : '$s s')),
                  ],
                  selected: {settings.crossfadeSeconds},
                  onSelectionChanged: (s) => notifier.setCrossfade(s.first),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                settings.crossfadeSeconds == 0
                    ? 'Off: songs play gaplessly, exactly as mastered.'
                    : 'Songs blend into each other — except tracks of the same album, which stay gapless.',
                style: theme.textTheme.bodySmall?.copyWith(color: palette.inkMuted),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                activeThumbColor: palette.onInk,
                activeTrackColor: palette.ink,
                title: const Text('Keep albums together when shuffling', style: TextStyle(fontWeight: FontWeight.w600)),
                subtitle: const Text('Shuffles whole albums; each plays in order'),
                value: settings.keepAlbumsTogether,
                onChanged: notifier.setKeepAlbumsTogether,
              ),
              heading('Library'),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: scan.running
                    ? const SizedBox.square(
                        dimension: 22,
                        child: CircularProgressIndicator(strokeWidth: 2.5),
                      )
                    : HugeIcon(icon: HugeIcons.strokeRoundedRefresh, color: palette.ink, size: 22),
                title: const Text('Scan device for audio', style: TextStyle(fontWeight: FontWeight.w600)),
                subtitle: scanSubtitle.isEmpty ? null : Text(scanSubtitle),
                onTap: scan.running ? null : () => ref.read(libraryProvider.notifier).refresh(),
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: HugeIcon(icon: HugeIcons.strokeRoundedFolderMusic, color: palette.ink, size: 22),
                title: const Text('Folders', style: TextStyle(fontWeight: FontWeight.w600)),
                subtitle: Text(
                  settings.excludedFolders.isEmpty
                      ? 'All folders included'
                      : '${pluralize(settings.excludedFolders.length, 'folder')} excluded',
                ),
                trailing: HugeIcon(icon: HugeIcons.strokeRoundedArrowRight01, color: palette.inkMuted, size: 20),
                onTap: () => FoldersScreen.open(context),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                activeThumbColor: palette.onInk,
                activeTrackColor: palette.ink,
                title: const Text('Show labels on songs', style: TextStyle(fontWeight: FontWeight.w600)),
                subtitle: Text(
                  analysis.running
                      ? 'Source & codec · analysing audio ${analysis.done} / ${analysis.total}…'
                      : 'Source folder & codec (e.g. Downloads · FLAC 24/96)',
                ),
                value: settings.showLabels,
                onChanged: notifier.setShowLabels,
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                activeThumbColor: palette.onInk,
                activeTrackColor: palette.ink,
                title: const Text('Show recordings & voice notes', style: TextStyle(fontWeight: FontWeight.w600)),
                subtitle: const Text('Voice recorder, call recordings, WhatsApp voice notes'),
                value: settings.includeRecordings,
                onChanged: notifier.setIncludeRecordings,
              ),
              const SizedBox(height: 8),
              const Text('Hide audio shorter than', style: TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: SegmentedButton<int>(
                  showSelectedIcon: false,
                  style: segmentedStyle,
                  segments: [
                    for (final s in AppSettings.minDurationChoices)
                      ButtonSegment(value: s, label: Text(s == 0 ? 'Off' : '$s s')),
                  ],
                  selected: {settings.minDurationSeconds},
                  onSelectionChanged: (s) => notifier.setMinDuration(s.first),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Ringtones, alarms and notification sounds are always hidden.',
                style: theme.textTheme.bodySmall?.copyWith(color: palette.inkMuted),
              ),
              heading('Backup'),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: HugeIcon(icon: HugeIcons.strokeRoundedCloudUpload, color: palette.ink, size: 22),
                title: const Text('Back up to a file', style: TextStyle(fontWeight: FontWeight.w600)),
                subtitle: const Text('Favorites, playlists, history & play counts, EQ, settings'),
                onTap: () => _backup(context, ref),
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: HugeIcon(icon: HugeIcons.strokeRoundedCloudDownload, color: palette.ink, size: 22),
                title: const Text('Restore from a file', style: TextStyle(fontWeight: FontWeight.w600)),
                subtitle: const Text('Merges with what you have — nothing is deleted'),
                onTap: () => _restore(context, ref),
              ),
              heading('About'),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: HugeIcon(icon: HugeIcons.strokeRoundedInformationCircle, color: palette.ink, size: 22),
                title: const Text('About audifac', style: TextStyle(fontWeight: FontWeight.w600)),
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
        content: Text('Backed up ${pluralize(data.favorites.length, 'favorite')}, '
            '${pluralize(data.playlists.length, 'playlist')}, ${pluralize(data.eqPresets.length, 'EQ preset')}'),
      ));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Backup failed: $e')));
    }
  }

  Future<void> _restore(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
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
      messenger.showSnackBar(SnackBar(content: Text('Can\'t restore: ${e.message}')));
      return;
    }
    final report = await backup.restore(data);
    if (!root.mounted) return;
    await showDialog<void>(
      context: root.context,
      builder: (context) => AlertDialog(
        title: const Text('Restored'),
        content: Text([
          'From a backup of ${data.exportedAt.toLocal().toString().substring(0, 16)} (audifac ${data.appVersion}):',
          '',
          '• ${pluralize(report.favorites, 'new favorite')}',
          '• ${pluralize(report.playlists, 'playlist')} (${pluralize(report.playlistSongs, 'song')})',
          '• ${pluralize(report.presets, 'EQ preset')}, ${pluralize(report.rules, 'rule')}',
          '• ${pluralize(report.recent, 'history entry', 'history entries')}',
          if (report.plays > 0) '• ${pluralize(report.plays, 'listen')} (play counts & stats)',
          if (report.settings) '• Settings',
          if (report.missingSongs > 0)
            '\n${pluralize(report.missingSongs, 'song')} from the backup aren\'t on this device and were skipped.',
        ].join('\n')),
        actions: [FilledButton(onPressed: () => Navigator.pop(context), child: const Text('OK'))],
      ),
    );
  }
}
