import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_colors.dart';
import '../../l10n/l10n.dart';
import '../../providers/lastfm_provider.dart';

/// Settings → Last.fm: connect with your own API key, scrobble listens.
class LastFmSheet extends ConsumerStatefulWidget {
  const LastFmSheet({super.key});

  static Future<void> show(BuildContext context) => showModalBottomSheet<void>(
        context: context,
        useRootNavigator: true,
        isScrollControlled: true,
        // The sheet's own context: the caller (Settings) is already closed.
        builder: (sheet) => Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(sheet).bottom),
          child: const LastFmSheet(),
        ),
      );

  @override
  ConsumerState<LastFmSheet> createState() => _LastFmSheetState();
}

class _LastFmSheetState extends ConsumerState<LastFmSheet> {
  late final _apiKey = TextEditingController(text: ref.read(lastFmProvider).account?.apiKey ?? '');
  late final _secret = TextEditingController(text: ref.read(lastFmProvider).account?.secret ?? '');
  final _user = TextEditingController();
  final _password = TextEditingController();

  @override
  void dispose() {
    for (final c in [_apiKey, _secret, _user, _password]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _connect() async {
    try {
      await ref.read(lastFmProvider.notifier).connect(
            apiKey: _apiKey.text,
            secret: _secret.text,
            username: _user.text,
            password: _password.text,
          );
      _password.clear();
    } catch (_) {
      // Shown from the state.
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final s = ref.watch(lastFmProvider);
    final notifier = ref.read(lastFmProvider.notifier);
    final theme = Theme.of(context);
    final palette = context.palette;
    final muted = theme.textTheme.bodySmall?.copyWith(color: palette.inkMuted);
    final connected = s.account?.connected ?? false;

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Last.fm', style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 6),
            Text(l10n.lastFmIntro, style: muted),
            const SizedBox(height: 16),
            if (connected) ...[
              Text(l10n.lastFmConnectedAs(s.account!.username ?? ''), style: const TextStyle(fontWeight: FontWeight.w700)),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                activeThumbColor: palette.onInk,
                activeTrackColor: palette.ink,
                title: Text(l10n.lastFmScrobble, style: const TextStyle(fontWeight: FontWeight.w600)),
                subtitle: Text(s.pending == 0 ? l10n.lastFmAllSent : l10n.lastFmPending(s.pending)),
                value: s.enabled,
                onChanged: notifier.setEnabled,
              ),
              if (s.pending > 0) TextButton(onPressed: notifier.flush, child: Text(l10n.lastFmSendNow)),
              const SizedBox(height: 8),
              OutlinedButton(onPressed: notifier.disconnect, child: Text(l10n.lastFmDisconnect)),
            ] else ...[
              Text(l10n.lastFmKeyHint, style: muted),
              const SizedBox(height: 8),
              TextField(controller: _apiKey, decoration: InputDecoration(labelText: l10n.lastFmApiKey)),
              TextField(controller: _secret, decoration: InputDecoration(labelText: l10n.lastFmSecret), obscureText: true),
              const SizedBox(height: 8),
              TextField(controller: _user, decoration: InputDecoration(labelText: l10n.lastFmUser), autocorrect: false),
              TextField(
                controller: _password,
                decoration: InputDecoration(labelText: l10n.lastFmPassword),
                obscureText: true,
                onSubmitted: (_) => _connect(),
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: s.busy ? null : _connect,
                child: s.busy
                    ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : Text(l10n.lastFmConnect),
              ),
            ],
            if (s.error != null) ...[
              const SizedBox(height: 10),
              Text(s.error!, style: theme.textTheme.bodySmall?.copyWith(color: const Color(0xFFD70015))),
            ],
          ],
        ),
      ),
    );
  }
}
