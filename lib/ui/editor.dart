import 'package:flutter/material.dart';
import '../core/session.dart';
import '../core/vault.dart';
import 'vault_page.dart';

class EditorPage extends StatefulWidget {
  const EditorPage({super.key, required this.session, this.record});
  final VaultSession session;
  final SecretRecord? record;
  @override
  State<EditorPage> createState() => _EditorPageState();
}

class _EditorPageState extends State<EditorPage> {
  late final service = TextEditingController(text: widget.record?.service);
  late final username = TextEditingController(text: widget.record?.username);
  late final secret = TextEditingController(text: widget.record?.secret);
  bool saving = false, visible = false;
  Future<void> save() async {
    setState(() => saving = true);
    try {
      final record = SecretRecord(
        id: widget.record?.id ?? SecretGenerator.token(bytes: 16, hex: true),
        service: service.text,
        username: username.text,
        secret: secret.text,
      );
      final records =
          widget.session.records.where((r) => r.id != record.id).toList()
            ..add(record);
      await widget.session.save(records);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        setState(() => saving = false);
        showError(context, e);
      }
    }
  }

  Future<void> delete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete secret?'),
        content: const Text(
          'This removes the record from this vault. Older encrypted backups may still contain it.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => saving = true);
    try {
      await widget.session.save(
        widget.session.records.where((r) => r.id != widget.record!.id).toList(),
      );
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        setState(() => saving = false);
        showError(context, e);
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(widget.record == null ? 'Add secret' : 'Edit secret'),
      actions: [
        if (widget.record != null)
          IconButton(
            onPressed: saving ? null : delete,
            tooltip: 'Delete secret',
            icon: const Icon(Icons.delete_outline),
          ),
      ],
    ),
    body: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        TextField(
          enableIMEPersonalizedLearning: false,
          controller: service,
          minLines: 1,
          maxLines: 5,
          decoration: const InputDecoration(labelText: 'Service'),
        ),
        const SizedBox(height: 20),
        TextField(
          enableIMEPersonalizedLearning: false,
          controller: username,
          minLines: 1,
          maxLines: 5,
          autocorrect: false,
          enableSuggestions: false,
          decoration: const InputDecoration(labelText: 'Username'),
        ),
        const SizedBox(height: 20),
        TextField(
          enableIMEPersonalizedLearning: false,
          controller: secret,
          minLines: 1,
          maxLines: visible ? 10 : 1,
          obscureText: !visible,
          autocorrect: false,
          enableSuggestions: false,
          decoration: InputDecoration(
            labelText: 'Secret',
            suffixIcon: IconButton(
              onPressed: () => setState(() => visible = !visible),
              tooltip: visible ? 'Hide secret' : 'Reveal secret',
              icon: Icon(
                visible
                    ? Icons.visibility_off_outlined
                    : Icons.visibility_outlined,
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: saving
              ? null
              : () async {
                  final generated = await showDialog<String>(
                    context: context,
                    builder: (_) => const GeneratorDialog(),
                  );
                  if (generated != null) secret.text = generated;
                },
          icon: const Icon(Icons.casino_outlined),
          label: const Text('Generate secret'),
        ),
        const SizedBox(height: 28),
        FilledButton(
          onPressed: saving ? null : save,
          child: Text(saving ? 'Saving…' : 'Save secret'),
        ),
        const SizedBox(height: 12),
        const Text(
          'All fields are free-form. To edit a multiline secret, reveal it first.',
        ),
      ],
    ),
  );
  @override
  void dispose() {
    service.dispose();
    username.dispose();
    secret.dispose();
    super.dispose();
  }
}

class GeneratorDialog extends StatefulWidget {
  const GeneratorDialog({super.key});
  @override
  State<GeneratorDialog> createState() => _GeneratorDialogState();
}

class _GeneratorDialogState extends State<GeneratorDialog> {
  bool token = false,
      hex = false,
      upper = true,
      lower = true,
      digits = true,
      symbols = true;
  double length = 24, bytes = 32;
  String? error;
  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Generate secret'),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SegmentedButton<bool>(
            segments: const [
              ButtonSegment(value: false, label: Text('Password')),
              ButtonSegment(value: true, label: Text('Token')),
            ],
            selected: {token},
            onSelectionChanged: (s) => setState(() => token = s.single),
          ),
          const SizedBox(height: 16),
          if (token) ...[
            Text('${bytes.round()} random bytes (${bytes.round() * 8} bits)'),
            Slider(
              value: bytes,
              min: 16,
              max: 128,
              divisions: 112,
              onChanged: (v) => setState(() => bytes = v),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Hex encoding'),
              subtitle: const Text('Otherwise Base64url'),
              value: hex,
              onChanged: (v) => setState(() => hex = v),
            ),
            const Text(
              'Creates an opaque random value, not a token issued by another service.',
            ),
          ] else ...[
            Text('${length.round()} characters'),
            Slider(
              value: length,
              min: 4,
              max: 128,
              divisions: 124,
              onChanged: (v) => setState(() => length = v),
            ),
            check('Uppercase', upper, (v) => upper = v),
            check('Lowercase', lower, (v) => lower = v),
            check('Digits', digits, (v) => digits = v),
            check('Symbols', symbols, (v) => symbols = v),
          ],
          if (error != null) Text(error!),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: () {
          try {
            Navigator.pop(
              context,
              token
                  ? SecretGenerator.token(bytes: bytes.round(), hex: hex)
                  : SecretGenerator.password(
                      length: length.round(),
                      upper: upper,
                      lower: lower,
                      digits: digits,
                      symbols: symbols,
                    ),
            );
          } catch (e) {
            setState(() => error = e.toString());
          }
        },
        child: const Text('Use generated secret'),
      ),
    ],
  );
  Widget check(String label, bool value, void Function(bool) change) =>
      CheckboxListTile(
        contentPadding: EdgeInsets.zero,
        dense: true,
        title: Text(label),
        value: value,
        onChanged: (v) => setState(() => change(v!)),
      );
}
