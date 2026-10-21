import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../core/session.dart';
import '../platform/android_bridge.dart';
import 'vault_page.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({
    super.key,
    required this.session,
    required this.bridge,
    required this.refresh,
    required this.setup,
    required this.importFile,
    required this.remoteRestore,
  });
  final VaultSession session;
  final AndroidBridge bridge;
  final Future<void> Function() refresh, setup, importFile, remoteRestore;
  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  Map<String, dynamic> status = {};
  bool busy = false;
  Timer? poll;
  @override
  void initState() {
    super.initState();
    load();
    poll = Timer.periodic(const Duration(seconds: 3), (_) => load());
  }

  Future<void> load() async {
    try {
      final next = await widget.bridge.status();
      if (mounted) setState(() => status = next);
    } on PlatformException {
      /* Preserve last status. */
    }
  }

  Future<void> run(Future<void> Function() action) async {
    if (busy) return;
    setState(() => busy = true);
    try {
      await action();
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      await widget.refresh();
      await load();
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Settings')),
    body: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        if (busy) const LinearProgressIndicator(),
        Text('Unlock & privacy', style: Theme.of(context).textTheme.titleLarge),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Biometric unlock'),
          subtitle: const Text(
            'Master passphrase remains necessary for recovery',
          ),
          value: status['biometrics'] == true,
          onChanged: busy
              ? null
              : (enable) => run(() async {
                  if (enable) {
                    final vault = widget.session.vault;
                    await widget.bridge.enableBiometrics(
                      Uint8List.fromList(vault.key),
                      vault.envelope.id,
                    );
                  } else {
                    await widget.bridge.disableBiometrics();
                  }
                }),
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<int>(
          initialValue: (status['lockSeconds'] as int?) ?? 30,
          decoration: const InputDecoration(
            labelText: 'Lock after time in background',
          ),
          items: const [
            DropdownMenuItem(value: 0, child: Text('Immediately')),
            DropdownMenuItem(value: 15, child: Text('15 seconds')),
            DropdownMenuItem(value: 30, child: Text('30 seconds')),
            DropdownMenuItem(value: 60, child: Text('1 minute')),
            DropdownMenuItem(value: 120, child: Text('2 minutes')),
            DropdownMenuItem(value: 300, child: Text('5 minutes')),
          ],
          onChanged: busy
              ? null
              : (v) => run(() async {
                  await widget.bridge.setLockDelay(v!);
                  widget.session.backgroundSeconds = v;
                }),
        ),
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 16),
          child: Text(
            'Screen locking locks the vault immediately. Foreground reading and scrolling never trigger the background timer.',
          ),
        ),
        const Divider(),
        const SizedBox(height: 12),
        Text('Automatic backup', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 12),
        Text(
          status['configured'] == true
              ? '${status['provider']} · ${status['error'] != null
                    ? 'Needs attention'
                    : status['pending'] == true
                    ? 'Pending upload'
                    : 'Backed up'}'
              : 'Local only · No backup configured',
        ),
        if ((status['lastBackup'] as int? ?? 0) > 0)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              'Last successful backup: ${DateTime.fromMillisecondsSinceEpoch(status['lastBackup'] as int).toLocal()}',
            ),
          ),
        if (status['error'] != null)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text(
              status['error'] as String,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        const SizedBox(height: 12),
        OutlinedButton(
          onPressed: busy ? null : () => run(widget.setup),
          child: Text(
            status['configured'] == true
                ? 'Change / reconnect provider'
                : 'Set up automatic backup',
          ),
        ),
        if (status['configured'] == true) ...[
          OutlinedButton(
            onPressed: busy ? null : () => run(widget.bridge.backupNow),
            child: const Text('Retry backup now'),
          ),
          TextButton(
            onPressed: busy ? null : () => run(widget.remoteRestore),
            child: const Text('Restore latest remote backup'),
          ),
          TextButton(
            onPressed: busy
                ? null
                : () => run(() async {
                    await widget.bridge.disconnect();
                  }),
            child: const Text('Disconnect backup (keep remote copies)'),
          ),
        ],
        const Divider(),
        const SizedBox(height: 12),
        Text(
          'Manual backup & restore',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: busy ? null : () => run(widget.bridge.exportVault),
          icon: const Icon(Icons.save_alt),
          label: const Text('Export encrypted vault'),
        ),
        OutlinedButton.icon(
          onPressed: busy ? null : () => run(widget.importFile),
          icon: const Icon(Icons.file_open_outlined),
          label: const Text('Import encrypted vault'),
        ),
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 16),
          child: Text(
            'Keep your master passphrase somewhere safe. Biometrics cannot recover a vault on another phone. Older backups may retain deleted records.',
          ),
        ),
        const Divider(),
        const ListTile(
          contentPadding: EdgeInsets.zero,
          title: Text('Secrets · 0.1.0'),
          subtitle: Text('Open source · Apache-2.0'),
        ),
      ],
    ),
  );
  @override
  void dispose() {
    poll?.cancel();
    super.dispose();
  }
}
