import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'core/session.dart';
import 'core/vault.dart';
import 'platform/android_bridge.dart';
import 'ui/auth.dart';
import 'ui/vault_page.dart';
import 'ui/settings.dart';
import 'ui/provider_page.dart';

class SecretsApp extends StatefulWidget {
  const SecretsApp({super.key, this.bridge});
  final AndroidBridge? bridge;
  @override
  State<SecretsApp> createState() => _SecretsAppState();
}

class _SecretsAppState extends State<SecretsApp> with WidgetsBindingObserver {
  late final bridge = widget.bridge ?? AndroidBridge();
  late final session = VaultSession(bridge);
  final navigator = GlobalKey<NavigatorState>();
  Map<String, dynamic> status = {};
  Timer? poll;
  bool ready = false, working = false, wasUnlocked = false;
  String? startupError;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    session.addListener(changed);
    AndroidBridge.channel.setMethodCallHandler((call) async {
      if (call.method == 'screenLocked') session.lock();
    });
    initialize();
    poll = Timer.periodic(const Duration(seconds: 3), (_) => refreshStatus());
  }

  Future<void> initialize() async {
    try {
      await session.initialize();
      await refreshStatus();
    } catch (_) {
      startupError =
          'The local vault could not be read. Restore a valid encrypted backup or check device storage.';
    }
    if (mounted) setState(() => ready = true);
  }

  void changed() {
    if (!mounted) return;
    if (wasUnlocked && !session.unlocked) {
      navigator.currentState?.popUntil((r) => r.isFirst);
    }
    wasUnlocked = session.unlocked;
    setState(() {});
  }

  Future<void> refreshStatus() async {
    try {
      final next = await bridge.status();
      if (mounted) {
        session.backgroundSeconds = next['lockSeconds'] as int? ?? 30;
        setState(() => status = next);
      }
    } on PlatformException {
      /* Keep last known status; operations surface errors. */
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      session.foreground();
      refreshStatus();
    } else if (state == AppLifecycleState.hidden ||
        state == AppLifecycleState.paused) {
      session.background();
    }
  }

  void message(String text) {
    final context = navigator.currentContext;
    if (context != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
    }
  }

  Future<void> run(Future<void> Function() action) async {
    if (working) return;
    setState(() => working = true);
    try {
      await action();
    } catch (e) {
      message(
        e is PlatformException
            ? e.message ?? 'Operation failed.'
            : e is VaultException
            ? e.message
            : 'Operation failed. Your last saved vault has been preserved.',
      );
    } finally {
      if (mounted) setState(() => working = false);
      await refreshStatus();
    }
  }

  Future<String?> passphrase({required String title, bool confirm = false}) =>
      showDialog<String>(
        context: navigator.currentContext!,
        barrierDismissible: false,
        builder: (_) => PassphraseDialog(title: title, confirm: confirm),
      );
  Future<void> create() => run(() async {
    final phrase = await passphrase(title: 'Create your vault', confirm: true);
    if (phrase != null) await session.create(phrase);
  });
  Future<void> unlock(String phrase) => run(() => session.unlock(phrase));
  Future<void> biometric() => run(() async {
    final epoch = session.epoch;
    final platformKey = await bridge.biometricKey();
    if (platformKey != null) {
      // Platform response buffers can be read-only. Own the temporary buffer
      // before clearing it so cleanup cannot turn a successful unlock into an error.
      final key = Uint8List.fromList(platformKey);
      try {
        if (session.epoch == epoch) await session.unlockWithKey(key);
      } finally {
        key.fillRange(0, key.length, 0);
      }
    }
  });
  Future<bool> confirmReplacement() async {
    if (!session.exists || (session.unlocked && session.records.isEmpty)) {
      return true;
    }
    final choice = await showDialog<String>(
      context: navigator.currentContext!,
      builder: (context) => AlertDialog(
        title: const Text('Replace this vault?'),
        content: const Text(
          'Import replaces all current records. It also disconnects automatic backup and disables biometric unlock. Export your current vault first if you need to keep it.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, 'cancel'),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, 'export'),
            child: const Text('Export current'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, 'replace'),
            child: const Text('Replace'),
          ),
        ],
      ),
    );
    if (choice == 'export') await bridge.exportVault();
    return choice == 'replace';
  }

  Future<bool> restoreText(String text) async {
    if (!await confirmReplacement()) return false;
    final phrase = await passphrase(title: 'Decrypt backup');
    if (phrase == null) return false;
    await session.restore(text, phrase);
    if (!session.unlocked) return false;
    startupError = null;
    message('Vault restored. You can enable biometric unlock in Settings.');
    return true;
  }

  Future<void> importFile() => run(() async {
    final text = await bridge.importVault();
    if (text != null) await restoreText(text);
  });
  Future<void> backupSetup({bool restoring = false}) async {
    await navigator.currentState!.push(
      MaterialPageRoute<void>(
        builder: (_) => ProviderPage(
          bridge: bridge,
          restoring: restoring,
          onConnected: (result) async {
            var text = result['backup'] as String?;
            if ((restoring || result['matchesLocal'] != true) && text != null) {
              final names = List<String>.from(result['backups'] as List? ?? []);
              if (names.length > 1) {
                final chosen = await showDialog<String>(
                  context: navigator.currentContext!,
                  builder: (context) => SimpleDialog(
                    title: const Text('Choose backup to restore'),
                    children: names.map((name) {
                      final sequence = int.tryParse(name.split('-')[1]);
                      final date = sequence == null
                          ? name
                          : DateTime.fromMillisecondsSinceEpoch(
                              sequence,
                            ).toLocal().toString();
                      return SimpleDialogOption(
                        onPressed: () => Navigator.pop(context, name),
                        child: Text(
                          '${name == names.first ? 'Latest · ' : ''}$date',
                        ),
                      );
                    }).toList(),
                  ),
                );
                if (chosen == null) return false;
                text = await bridge.candidateBackup(chosen);
              }
            }
            if (restoring) {
              if (text == null) {
                throw const VaultException(
                  'No backup found at this destination.',
                );
              }
              if (!await restoreText(text)) return false;
            } else {
              if (!session.unlocked) {
                throw const VaultException(
                  'Unlock the vault before enabling backup.',
                );
              }
              if (text != null &&
                  result['matchesLocal'] != true &&
                  !await restoreText(text)) {
                return false;
              }
            }
            await bridge.activate();
            await refreshStatus();
            message('Automatic backup enabled.');
            return true;
          },
        ),
      ),
    );
  }

  Future<void> settings() async {
    await navigator.currentState!.push(
      MaterialPageRoute<void>(
        builder: (_) => SettingsPage(
          session: session,
          bridge: bridge,
          refresh: refreshStatus,
          setup: () => backupSetup(),
          importFile: importFile,
          remoteRestore: () => run(() async {
            final text = await bridge.downloadBackup();
            if (text != null) await restoreText(text);
          }),
        ),
      ),
    );
    await refreshStatus();
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Secrets',
    navigatorKey: navigator,
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xff527d66),
        brightness: Brightness.dark,
      ),
      useMaterial3: true,
      scaffoldBackgroundColor: const Color(0xff111916),
      inputDecorationTheme: const InputDecorationTheme(
        border: OutlineInputBorder(),
      ),
      cardTheme: const CardThemeData(margin: EdgeInsets.symmetric(vertical: 5)),
    ),
    home: !ready
        ? const Scaffold(body: Center(child: CircularProgressIndicator()))
        : session.unlocked
        ? VaultPage(
            session: session,
            bridge: bridge,
            status: status,
            settings: settings,
          )
        : UnlockPage(
            exists: session.exists,
            busy: working || session.busy,
            biometricEnabled: status['biometrics'] == true,
            error: startupError,
            unlock: unlock,
            create: create,
            biometric: biometric,
            importFile: importFile,
            remoteRestore: () => backupSetup(restoring: true),
          ),
  );
  @override
  void dispose() {
    poll?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    session.removeListener(changed);
    session.dispose();
    AndroidBridge.channel.setMethodCallHandler(null);
    super.dispose();
  }
}
