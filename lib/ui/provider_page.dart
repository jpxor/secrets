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
      if (provider == 'SFTP') {
        for (final key in [
          'username',
          'password',
          'privateKey',
          'keyPassphrase',
        ]) {
          config[key] = value(key);
        }
        config['directory'] = value('directory', 'Secrets').trim();
        config['host'] = value('host').trim();
        config['port'] = value('port', '22').trim();
        final port = int.tryParse(config['port']!);
        if (config['host']!.isEmpty ||
            config['username']!.isEmpty ||
            port == null ||
            port < 1 ||
            port > 65535) {
          throw const VaultException('Enter a host, username and valid port.');
        }
      }
      final result = await connectWithHostTrust(config);
      if (result == null) return;
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

  Future<Map<String, dynamic>?> connectWithHostTrust(
    Map<String, String> config,
  ) async {
    for (var attempt = 0; attempt < 3; attempt++) {
      try {
        return await widget.bridge.connect(config);
      } on PlatformException catch (e) {
        if (e.code != 'ssh_host_key' || config['type'] != 'SFTP') rethrow;
        final details = e.details;
        if (details is! Map || details['fingerprint'] is! String) rethrow;
        final fingerprint = details['fingerprint'] as String;
        final previous = details['previousFingerprint'] as String? ?? '';
        if (!RegExp(r'^SHA256:[A-Za-z0-9+/]{43}$').hasMatch(fingerprint)) {
          throw const VaultException(
            'The server returned an invalid host key.',
          );
        }
        if (!mounted) return null;
        final trusted = await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (context) => AlertDialog(
            title: Text(
              previous.isEmpty
                  ? 'Trust this SSH host?'
                  : 'SSH host key changed',
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('${config['host']}:${config['port']}'),
                  const SizedBox(height: 16),
                  Text(
                    previous.isEmpty
                        ? 'This is the first connection to this host. Compare its fingerprint with the server owner before trusting it.'
                        : 'This host has a different key than the one you trusted. This could mean the server was replaced or your connection is being intercepted. Confirm the change with the server owner before continuing.',
                  ),
                  if (previous.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    const Text('Previously trusted fingerprint'),
                    SelectableText(previous),
                  ],
                  const SizedBox(height: 16),
                  const Text('Server fingerprint'),
                  SelectableText(fingerprint),
                  const SizedBox(height: 16),
                  const Text(
                    'Your login credentials are not sent until the host key is trusted.',
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: Text(
                  previous.isEmpty ? 'Trust and connect' : 'Trust new key',
                ),
              ),
            ],
          ),
        );
        if (trusted != true || !mounted) return null;
        config['fingerprint'] = fingerprint;
      }
    }
    throw const VaultException(
      'The server key changed repeatedly. Connect again after checking the server.',
    );
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
            'SFTP',
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
            'Sign in with Google and allow access to Secrets’ encrypted backup folder.',
          ),
        if (provider == 'SFTP') ...[
          field('host', 'Server host'),
          field('port', 'Port', initial: '22'),
          field('directory', 'Backup directory', initial: 'Secrets'),
        ],
        if (provider == 'SFTP') ...[
          field('username', 'Username'),
          field('password', 'Password (optional)', secret: true),
          field(
            'privateKey',
            'SSH private key (optional)',
            secret: true,
            multiline: true,
          ),
          field('keyPassphrase', 'SSH key passphrase (optional)', secret: true),
          const Text(
            'When connecting, review and approve the server’s SSH fingerprint. The trusted key is saved with this backup destination; a changed key is rejected until you explicitly approve it.',
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
