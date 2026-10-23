import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hugeicons/hugeicons.dart';

import '../../core/theme/app_colors.dart';
import '../../data/autoeq_database.dart';
import '../../l10n/l10n.dart';
import '../../providers/eq_providers.dart';

/// Search the AutoEQ database for a headphone model; returns the chosen
/// correction (name + ParametricEQ text), or null.
class AutoEqSearchScreen extends ConsumerStatefulWidget {
  const AutoEqSearchScreen({super.key});

  static Future<({String name, String text})?> open(BuildContext context) =>
      Navigator.of(context, rootNavigator: true).push(
        MaterialPageRoute(builder: (_) => const AutoEqSearchScreen()),
      );

  @override
  ConsumerState<AutoEqSearchScreen> createState() => _AutoEqSearchScreenState();
}

class _AutoEqSearchScreenState extends ConsumerState<AutoEqSearchScreen> {
  List<AutoEqEntry>? _index;
  Object? _error;
  String _query = '';
  bool _downloading = false;
  final _focus = FocusNode();

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final index = await ref.read(autoEqDatabaseProvider).index();
      if (!mounted) return;
      setState(() => _index = index);
      // The field was disabled while loading: ready to type now.
      WidgetsBinding.instance.addPostFrameCallback((_) => _focus.requestFocus());
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  Future<void> _pick(AutoEqEntry entry) async {
    final messenger = ScaffoldMessenger.of(context);
    final l10n = context.l10n;
    setState(() => _downloading = true);
    try {
      final text = await ref.read(autoEqDatabaseProvider).parametricEq(entry);
      if (mounted) Navigator.of(context).pop((name: entry.name, text: text));
    } catch (_) {
      messenger.showSnackBar(SnackBar(content: Text(l10n.autoEqDownloadFailed)));
    } finally {
      if (mounted) setState(() => _downloading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final theme = Theme.of(context);
    final index = _index;
    final results = index == null ? const <AutoEqEntry>[] : AutoEqDatabase.search(index, _query);

    Widget body;
    if (_error != null) {
      body = Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(context.l10n.autoEqOffline, textAlign: TextAlign.center),
              const SizedBox(height: 12),
              FilledButton(onPressed: _load, child: Text(context.l10n.tryAgain)),
            ],
          ),
        ),
      );
    } else if (index == null) {
      body = const Center(child: CircularProgressIndicator());
    } else if (_query.trim().isEmpty) {
      body = Padding(
        padding: const EdgeInsets.all(24),
        child: Text(context.l10n.autoEqIntro(index.length), style: theme.textTheme.bodyMedium?.copyWith(color: palette.inkMuted)),
      );
    } else if (results.isEmpty) {
      body = Padding(
        padding: const EdgeInsets.all(24),
        child: Text(context.l10n.nothingMatches(_query), style: theme.textTheme.bodyMedium?.copyWith(color: palette.inkMuted)),
      );
    } else {
      body = ListView.builder(
        itemCount: results.length,
        itemBuilder: (context, i) {
          final e = results[i];
          return ListTile(
            leading: HugeIcon(icon: HugeIcons.strokeRoundedHeadphones, color: palette.ink, size: 22),
            title: Text(e.name, style: const TextStyle(fontWeight: FontWeight.w600)),
            subtitle: Text([context.l10n.measuredBy(e.source), if (e.form.isNotEmpty) e.form].join(' · ')),
            onTap: _downloading ? null : () => _pick(e),
          );
        },
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(context.l10n.findHeadphones, style: const TextStyle(fontWeight: FontWeight.w800)),
        bottom: _downloading ? const PreferredSize(preferredSize: Size.fromHeight(2), child: LinearProgressIndicator()) : null,
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: TextField(
              focusNode: _focus,
              enabled: index != null,
              decoration: InputDecoration(
                hintText: context.l10n.headphoneModelHint,
                prefixIcon: Padding(
                  padding: const EdgeInsets.all(12),
                  child: HugeIcon(icon: HugeIcons.strokeRoundedSearch01, color: palette.inkMuted, size: 20),
                ),
              ),
              onChanged: (v) => setState(() => _query = v),
            ),
          ),
          Expanded(child: body),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
            child: Text(context.l10n.autoEqCredit, style: theme.textTheme.bodySmall?.copyWith(color: palette.inkMuted)),
          ),
        ],
      ),
    );
  }
}
