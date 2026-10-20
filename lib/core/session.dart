import 'dart:async';
import 'dart:isolate';

import 'package:flutter/foundation.dart';

import 'vault.dart';

// Keep isolate closures outside instance methods: shared closure contexts can
// otherwise capture the session and its unsendable Flutter/platform listeners.
Future<OpenVault> _createInIsolate(String passphrase) =>
    Isolate.run(() => VaultCrypto.create(passphrase));

Future<OpenVault> _unlockInIsolate(VaultEnvelope envelope, String passphrase) =>
    Isolate.run(() => VaultCrypto.unlock(envelope, passphrase));

abstract interface class VaultStore {
  Future<String?> read();
  Future<void> write(String envelope, {bool replacement = false});
}

class VaultSession extends ChangeNotifier {
  VaultSession(this.store);
  final VaultStore store;
  OpenVault? _vault;
  bool exists = false;
  bool busy = false;
  int _epoch = 0;
  Timer? _lockTimer;
  DateTime? _backgroundAt;
  int backgroundSeconds = 30;
  bool get unlocked => _vault != null;
  int get epoch => _epoch;
  OpenVault get vault =>
      _vault ?? (throw const VaultException('Vault is locked.'));
  List<SecretRecord> get records => List.unmodifiable(vault.records);

  Future<void> initialize() async {
    // A read failure must never make a damaged existing vault look like an empty installation.
    try {
      exists = await store.read() != null;
    } catch (_) {
      exists = true;
      rethrow;
    }
    notifyListeners();
  }

  Future<void> _exclusive(Future<void> Function(int epoch) action) async {
    if (busy) {
      throw const VaultException('An operation is already in progress.');
    }
    busy = true;
    notifyListeners();
    final epoch = _epoch;
    try {
      await action(epoch);
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  Future<void> create(String passphrase) => _exclusive((epoch) async {
    if (exists) {
      throw const VaultException(
        'A vault already exists. Unlock or restore it.',
      );
    }
    final result = await _createInIsolate(passphrase);
    if (_epoch != epoch) {
      result.dispose();
      return;
    }
    try {
      await store.write(result.envelope.encode(), replacement: true);
      exists = true;
      if (_epoch == epoch) {
        _vault = result;
      } else {
        result.dispose();
      }
    } catch (_) {
      result.dispose();
      rethrow;
    }
  });

  Future<void> unlock(String passphrase) => _exclusive((epoch) async {
    final text = await store.read();
    if (text == null) {
      throw const VaultException('No local vault. Create or restore one.');
    }
    final envelope = VaultEnvelope.decode(text);
    final result = await _unlockInIsolate(envelope, passphrase);
    if (_epoch != epoch) {
      result.dispose();
      return;
    }
    _vault?.dispose();
    _vault = result;
  });

  Future<void> unlockWithKey(List<int> key) => _exclusive((epoch) async {
    final text = await store.read();
    if (text == null) throw const VaultException('No local vault.');
    final result = await VaultCrypto.unlockWithKey(
      VaultEnvelope.decode(text),
      key,
    );
    if (_epoch != epoch) {
      result.dispose();
      return;
    }
    _vault?.dispose();
    _vault = result;
  });

  Future<void> save(List<SecretRecord> records) => _exclusive((epoch) async {
    final current = vault;
    final next = await VaultCrypto.seal(current, records);
    if (_epoch != epoch) {
      throw const VaultException('Vault locked before saving.');
    }
    await store.write(next.encode());
    if (_epoch == epoch) {
      current.envelope = next;
      current.records = List.of(records);
    }
  });

  Future<void> restore(String text, String passphrase) =>
      _exclusive((epoch) async {
        final envelope = VaultEnvelope.decode(text);
        final result = await _unlockInIsolate(envelope, passphrase);
        if (_epoch != epoch) {
          result.dispose();
          return;
        }
        try {
          await store.write(envelope.encode(), replacement: true);
          exists = true;
          _vault?.dispose();
          if (_epoch == epoch) {
            _vault = result;
          } else {
            result.dispose();
          }
        } catch (_) {
          result.dispose();
          rethrow;
        }
      });

  void background({DateTime? now}) {
    final current = now ?? DateTime.now();
    _backgroundAt ??= current;
    _lockTimer?.cancel();
    final remaining =
        Duration(seconds: backgroundSeconds) -
        current.difference(_backgroundAt!);
    if (remaining <= Duration.zero) {
      lock();
    } else {
      _lockTimer = Timer(remaining, lock);
    }
  }

  void foreground({DateTime? now}) {
    final since = _backgroundAt;
    _backgroundAt = null;
    _lockTimer?.cancel();
    if (since != null &&
        (now ?? DateTime.now()).difference(since).inSeconds >=
            backgroundSeconds) {
      lock();
    }
  }

  void lock() {
    _epoch++;
    _lockTimer?.cancel();
    _backgroundAt = null;
    _vault?.dispose();
    _vault = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _lockTimer?.cancel();
    _vault?.dispose();
    super.dispose();
  }
}
