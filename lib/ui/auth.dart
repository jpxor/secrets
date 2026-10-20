import 'package:flutter/material.dart';
import '../core/vault.dart';

class UnlockPage extends StatefulWidget {
  const UnlockPage({
    super.key,
    required this.exists,
    required this.busy,
    required this.biometricEnabled,
    required this.error,
    required this.unlock,
    required this.create,
    required this.biometric,
    required this.importFile,
    required this.remoteRestore,
  });
  final bool exists, busy, biometricEnabled;
  final String? error;
  final Future<void> Function(String) unlock;
  final Future<void> Function() create, biometric, importFile, remoteRestore;
  @override
  State<UnlockPage> createState() => _UnlockPageState();
}

class _UnlockPageState extends State<UnlockPage> {
  final input = TextEditingController();
  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(28),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Icon(Icons.lock_outline_rounded, size: 64),
                const SizedBox(height: 20),
                Text(
                  'Secrets',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.displaySmall,
                ),
                const SizedBox(height: 12),
                const Text(
                  'Your secrets. In your pocket.',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 36),
                if (widget.error != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: Text(widget.error!),
                  ),
                if (widget.exists) ...[
                  TextField(
                    enableIMEPersonalizedLearning: false,
                    controller: input,
                    obscureText: true,
                    enableSuggestions: false,
                    autocorrect: false,
                    decoration: const InputDecoration(
                      labelText: 'Master passphrase',
                    ),
                    onSubmitted: widget.busy ? null : (_) => submit(),
                  ),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: widget.busy ? null : submit,
                    icon: const Icon(Icons.lock_open),
                    label: const Text('Unlock vault'),
                  ),
                  if (widget.biometricEnabled)
                    OutlinedButton.icon(
                      onPressed: widget.busy ? null : widget.biometric,
                      icon: const Icon(Icons.fingerprint),
                      label: const Text('Use biometrics'),
                    ),
                ] else ...[
                  const Text(
                    'Create an encrypted vault, or restore one you already own.',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 20),
                  FilledButton(
                    onPressed: widget.busy ? null : widget.create,
                    child: const Text('Create vault'),
                  ),
                ],
                const SizedBox(height: 20),
                TextButton.icon(
                  onPressed: widget.busy ? null : widget.importFile,
                  icon: const Icon(Icons.file_open_outlined),
                  label: const Text('Restore from encrypted file'),
                ),
                TextButton.icon(
                  onPressed: widget.busy ? null : widget.remoteRestore,
                  icon: const Icon(Icons.cloud_download_outlined),
                  label: const Text('Restore from backup provider'),
                ),
                if (widget.busy)
                  const Padding(
                    padding: EdgeInsets.all(16),
                    child: LinearProgressIndicator(),
                  ),
                const SizedBox(height: 24),
                const Text(
                  'Offline first • Encrypted on your device',
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
  void submit() {
    final phrase = input.text;
    input.clear();
    widget.unlock(phrase);
  }

  @override
  void dispose() {
    input.dispose();
    super.dispose();
  }
}

class PassphraseDialog extends StatefulWidget {
  const PassphraseDialog({
    super.key,
    required this.title,
    this.confirm = false,
  });
  final String title;
  final bool confirm;
  @override
  State<PassphraseDialog> createState() => _PassphraseDialogState();
}

class _PassphraseDialogState extends State<PassphraseDialog> {
  final first = TextEditingController(), second = TextEditingController();
  String? error;
  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.title),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (widget.confirm)
            const Padding(
              padding: EdgeInsets.only(bottom: 16),
              child: Text(
                'Use at least 8 characters. We recommend a longer passphrase with several random words. There is no maximum length. You need it to recover your backup. There is no password reset.',
              ),
            ),
          TextField(
            enableIMEPersonalizedLearning: false,
            controller: first,
            autofocus: true,
            obscureText: true,
            enableSuggestions: false,
            autocorrect: false,
            decoration: InputDecoration(
              labelText: 'Master passphrase',
              errorText: error,
            ),
            onSubmitted: (_) {
              if (!widget.confirm) submit();
            },
          ),
          if (widget.confirm) ...[
            const SizedBox(height: 16),
            TextField(
              enableIMEPersonalizedLearning: false,
              controller: second,
              obscureText: true,
              enableSuggestions: false,
              autocorrect: false,
              decoration: const InputDecoration(
                labelText: 'Confirm passphrase',
              ),
              onSubmitted: (_) => submit(),
            ),
          ],
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: submit,
        child: Text(widget.confirm ? 'Create' : 'Decrypt'),
      ),
    ],
  );
  void submit() {
    if (widget.confirm &&
        (first.text.length < VaultCrypto.minimumPassphraseLength ||
            first.text != second.text)) {
      setState(
        () => error = first.text.length < VaultCrypto.minimumPassphraseLength
            ? 'Use at least 8 characters.'
            : 'Passphrases do not match.',
      );
      return;
    }
    if (first.text.isNotEmpty) Navigator.pop(context, first.text);
  }

  @override
  void dispose() {
    first.dispose();
    second.dispose();
    super.dispose();
  }
}
