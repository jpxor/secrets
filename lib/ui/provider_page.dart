import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../core/vault.dart';
import '../platform/android_bridge.dart';

class ProviderPage extends StatefulWidget {
  const ProviderPage({
    super.key,
    required this.bridge,
    required this.restoring,
    required this.onConnected,
  });
  final AndroidBridge bridge;
  final bool restoring;
  final Future<bool> Function(Map<String, dynamic>) onConnected;
  @override
  State<ProviderPage> createState() => _ProviderPageState();
}

class _ProviderPageState extends State<ProviderPage> {
  String provider = 'Google Drive';
  bool busy = false;
  bool showPrivateKey = false;
  String? error;
  final fields = <String, TextEditingController>{};
  TextEditingController controller(String key, [String value = '']) =>
      fields.putIfAbsent(key, () => TextEditingController(text: value));
  String value(String key, [String fallback = '']) =>
      fields[key]?.text ?? fallback;
  Future<void> connect() async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final config = <String, String>{'type': provider};
      if (provider == 'OneDrive' || provider == 'Dropbox') {
        config['clientId'] = value('clientId').trim();
      }
      if (provider == 'SFTP' || provider == 'Git') {
        for (final key in [
          'username',
          'password',
          'privateKey',
          'keyPassphrase',
          'fingerprint',
        ]) {
          config[key] = value(key);
        }
        config['directory'] = value('directory', 'Secrets').trim();
        if (provider == 'SFTP') {
          config['host'] = value('host').trim();
          config['port'] = value('port', '22').trim();
          final port = int.tryParse(config['port']!);
          if (config['host']!.isEmpty ||
              config['username']!.isEmpty ||
              port == null ||
              port < 1 ||
              port > 65535) {
            throw const VaultException(
              'Enter a host, username and valid port.',
            );
          }
        } else {
          config['url'] = value('url').trim();
          config['branch'] = value('branch', 'main').trim();
          if (!config['url']!.startsWith('https://') &&
              !config['url']!.startsWith('ssh://')) {
            throw const VaultException('Use an https:// or ssh:// Git URL.');
          }
        }
      }
      final result = await widget.bridge.connect(config);
      if (!mounted) return;
      final done = await widget.onConnected(result);
      if (done && mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        setState(
          () => error = e is PlatformException
              ? e.message
              : e is VaultException
              ? e.message
              : 'Connection failed. Check the provider settings.',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(widget.restoring ? 'Restore from provider' : 'Set up backup'),
    ),
    body: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const Text(
          'Only encrypted vault data is uploaded. You need your master passphrase to restore it.',
        ),
        const SizedBox(height: 20),
        DropdownButtonFormField<String>(
          initialValue: provider,
          decoration: const InputDecoration(labelText: 'Backup provider'),
          items: [
            'Google Drive',
            'OneDrive',
            'Dropbox',
            'SFTP',
            'Git',
          ].map((p) => DropdownMenuItem(value: p, child: Text(p))).toList(),
          onChanged: busy
              ? null
              : (v) => setState(() {
                  provider = v!;
                  error = null;
                  showPrivateKey = false;
                  final previous = fields.values.toList();
                  fields.clear();
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    for (final controller in previous) {
                      controller.dispose();
                    }
                  });
                }),
        ),
        const SizedBox(height: 20),
        if (provider == 'Google Drive')
          const Text(
            'Sign in with Google and allow access to the app’s backup folder. This APK must be registered with Google before sign-in can work.',
          ),
        if (provider == 'OneDrive' || provider == 'Dropbox') ...[
          field(
            'clientId',
            provider == 'OneDrive'
                ? 'Microsoft public application ID'
                : 'Dropbox app key',
            initial: provider == 'OneDrive'
                ? const String.fromEnvironment('SECRETS_MICROSOFT_CLIENT_ID')
                : const String.fromEnvironment('SECRETS_DROPBOX_APP_KEY'),
          ),
          const Text(
            'A distributor can preconfigure this public ID. Self-builders can enter their own app registration; no client secret is needed.',
          ),
        ],
        if (provider == 'SFTP') ...[
          field('host', 'Server host'),
          field('port', 'Port', initial: '22'),
          field('directory', 'Backup directory', initial: 'Secrets'),
        ],
        if (provider == 'Git') ...[
          field('url', 'Repository URL (HTTPS or SSH)'),
          field('branch', 'Branch', initial: 'main'),
          field(
            'directory',
            'Backup directory within repository',
            initial: 'Secrets',
          ),
          const Text(
            'Use a dedicated repository. An existing branch or an empty repository is supported. Git history retains previous encrypted copies.',
          ),
        ],
        if (provider == 'SFTP' || provider == 'Git') ...[
          field('username', 'Username'),
          field(
            'password',
            provider == 'Git'
                ? 'Password / access token (optional)'
                : 'Password (optional)',
            secret: true,
          ),
          field(
            'privateKey',
            'SSH private key (optional)',
            secret: true,
            multiline: true,
          ),
          field('keyPassphrase', 'SSH key passphrase (optional)', secret: true),
          field('fingerprint', 'SSH host fingerprint (SHA256:…)'),
          const Text(
            'For SSH/SFTP, verify the host fingerprint independently and enter it here. An unknown or changed server key is rejected.',
          ),
        ],
        if (error != null)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: SelectableText(
              error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        const SizedBox(height: 20),
        if (busy) const LinearProgressIndicator(),
        FilledButton(
          onPressed: busy ? null : connect,
          child: Text(
            busy
                ? 'Connecting…'
                : widget.restoring
                ? 'Connect and find backup'
                : 'Connect and enable backup',
          ),
        ),
        const SizedBox(height: 16),
        const Text(
          'One active provider at a time. Existing remote vaults must be restored before enabling backup from a different vault.',
        ),
      ],
    ),
  );
  Widget field(
    String key,
    String label, {
    String initial = '',
    bool secret = false,
    bool multiline = false,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: TextField(
      enableIMEPersonalizedLearning: false,
      controller: controller(key, initial),
      obscureText: secret && (!multiline || !showPrivateKey),
      autocorrect: false,
      enableSuggestions: false,
      minLines: 1,
      maxLines: multiline && (!secret || showPrivateKey) ? 6 : 1,
      decoration: InputDecoration(
        labelText: label,
        suffixIcon: secret && multiline
            ? IconButton(
                tooltip: showPrivateKey
                    ? 'Hide private key'
                    : 'Reveal private key',
                onPressed: () =>
                    setState(() => showPrivateKey = !showPrivateKey),
                icon: Icon(
                  showPrivateKey
                      ? Icons.visibility_off_outlined
                      : Icons.visibility_outlined,
                ),
              )
            : null,
      ),
      enabled: !busy,
    ),
  );
  @override
  void dispose() {
    for (final c in fields.values) {
      c.dispose();
    }
    super.dispose();
  }
}
