import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../core/session.dart';
import '../core/vault.dart';
import '../platform/android_bridge.dart';
import 'editor.dart';

void showError(BuildContext context, Object error) =>
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          error is VaultException
              ? error.message
              : error is PlatformException
              ? error.message ?? 'Operation failed.'
              : 'Operation failed. The last saved vault is unchanged.',
        ),
      ),
    );

class VaultPage extends StatefulWidget {
  const VaultPage({
    super.key,
    required this.session,
    required this.bridge,
    required this.status,
    required this.settings,
  });
  final VaultSession session;
  final AndroidBridge bridge;
  final Map<String, dynamic> status;
  final Future<void> Function() settings;
  @override
  State<VaultPage> createState() => _VaultPageState();
}

class _VaultPageState extends State<VaultPage> {
  String query = '';
  final revealed = <String>{};
  String backupLabel() {
    if (widget.status['configured'] != true) {
      return 'Local only · Configure backup in Settings';
    }
    if (widget.status['error'] != null) {
      return 'Backup needs attention · Open Settings';
    }
    if (widget.status['pending'] == true) {
      return 'Backup pending · Saved on this phone';
    }
    return 'Backed up to ${widget.status['provider']}';
  }

  @override
  Widget build(BuildContext context) {
    final records =
        widget.session.records
            .where((r) => r.service.toLowerCase().contains(query.toLowerCase()))
            .toList()
          ..sort(
            (a, b) =>
                a.service.toLowerCase().compareTo(b.service.toLowerCase()),
          );
    return Scaffold(
      appBar: AppBar(
        title: const Text('Secrets'),
        actions: [
          IconButton(
            onPressed: widget.settings,
            tooltip: 'Settings and backups',
            icon: const Icon(Icons.settings_outlined),
          ),
          IconButton(
            onPressed: widget.session.lock,
            tooltip: 'Lock vault',
            icon: const Icon(Icons.lock_outline),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: widget.session.busy ? null : () => edit(),
        icon: const Icon(Icons.add),
        label: const Text('Add secret'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: TextField(
              onChanged: (v) => setState(() => query = v),
              decoration: const InputDecoration(
                hintText: 'Search services',
                prefixIcon: Icon(Icons.search),
              ),
            ),
          ),
          InkWell(
            onTap: widget.settings,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Icon(
                    widget.status['error'] != null
                        ? Icons.cloud_off_outlined
                        : widget.status['configured'] == true
                        ? Icons.cloud_done_outlined
                        : Icons.phone_android,
                    size: 18,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      backupLabel(),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (widget.session.busy) const LinearProgressIndicator(),
          Expanded(
            child: records.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Text(
                        query.isEmpty
                            ? 'Your vault is ready.\nAdd your first secret.'
                            : 'No matching services.',
                        textAlign: TextAlign.center,
                      ),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 100),
                    itemCount: records.length,
                    itemBuilder: (context, i) {
                      final r = records[i];
                      return Card(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      r.service.isEmpty
                                          ? '(Unnamed service)'
                                          : r.service,
                                      style: Theme.of(
                                        context,
                                      ).textTheme.titleMedium,
                                    ),
                                  ),
                                  IconButton(
                                    onPressed: () => edit(r),
                                    tooltip: 'Edit secret',
                                    icon: const Icon(Icons.edit_outlined),
                                  ),
                                ],
                              ),
                              if (r.username.isNotEmpty)
                                SelectableText(r.username),
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      revealed.contains(r.id)
                                          ? r.secret
                                          : '••••••••••••',
                                      style: const TextStyle(
                                        fontFamily: 'monospace',
                                      ),
                                    ),
                                  ),
                                  IconButton(
                                    onPressed: () => setState(() {
                                      if (!revealed.remove(r.id)) {
                                        revealed.add(r.id);
                                      }
                                    }),
                                    tooltip: revealed.contains(r.id)
                                        ? 'Hide secret'
                                        : 'Reveal secret',
                                    icon: Icon(
                                      revealed.contains(r.id)
                                          ? Icons.visibility_off_outlined
                                          : Icons.visibility_outlined,
                                    ),
                                  ),
                                  IconButton(
                                    onPressed: () async {
                                      try {
                                        await widget.bridge.copy(r.secret);
                                        if (context.mounted) {
                                          ScaffoldMessenger.of(
                                            context,
                                          ).showSnackBar(
                                            const SnackBar(
                                              content: Text(
                                                'Copied. Clipboard clearing will be attempted in 30 seconds.',
                                              ),
                                            ),
                                          );
                                        }
                                      } on PlatformException catch (e) {
                                        if (context.mounted) {
                                          showError(context, e);
                                        }
                                      }
                                    },
                                    tooltip: 'Copy secret',
                                    icon: const Icon(Icons.copy_outlined),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Future<void> edit([SecretRecord? record]) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => EditorPage(session: widget.session, record: record),
      ),
    );
    if (mounted) setState(() {});
  }
}
