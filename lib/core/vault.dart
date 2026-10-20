import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

const maxVaultBytes = 8 * 1024 * 1024;

Uint8List randomBytes(int length) {
  final random = Random.secure();
  return Uint8List.fromList(List.generate(length, (_) => random.nextInt(256)));
}

class VaultException implements Exception {
  const VaultException(this.message);
  final String message;
  @override
  String toString() => message;
}

class SecretRecord {
  const SecretRecord({
    required this.id,
    required this.service,
    required this.username,
    required this.secret,
  });
  final String id;
  final String service;
  final String username;
  final String secret;
  Map<String, Object> toJson() => {
    'id': id,
    'service': service,
    'username': username,
    'secret': secret,
  };
  factory SecretRecord.fromJson(Map<String, dynamic> json) {
    for (final field in ['id', 'service', 'username', 'secret']) {
      if (json[field] is! String) throw const VaultException('Invalid record.');
    }
    return SecretRecord(
      id: json['id'] as String,
      service: json['service'] as String,
      username: json['username'] as String,
      secret: json['secret'] as String,
    );
  }
}

/// Portable, versioned authenticated envelope. No device credentials are included.
class VaultEnvelope {
  VaultEnvelope(this.header, this.wrappedKey, this.payload);
  final Map<String, dynamic> header;
  final Map<String, dynamic> wrappedKey;
  final Map<String, dynamic> payload;
  String get id => header['id'] as String;
  List<int> get aad => utf8.encode(
    jsonEncode({
      'format': 'Secrets',
      'version': 1,
      'id': header['id'],
      'kdf': 'argon2id',
      'memory': header['memory'],
      'iterations': header['iterations'],
      'parallelism': 1,
      'salt': header['salt'],
    }),
  );
  String encode() => jsonEncode({
    'header': header,
    'wrappedKey': wrappedKey,
    'payload': payload,
  });
  factory VaultEnvelope.decode(String text) {
    try {
      if (utf8.encode(text).length > maxVaultBytes)
        throw const FormatException();
      final root = jsonDecode(text) as Map<String, dynamic>;
      final h = root['header'] as Map<String, dynamic>;
      if (h['format'] != 'Secrets' ||
          h['version'] != 1 ||
          h['kdf'] != 'argon2id' ||
          h['parallelism'] != 1 ||
          h['memory'] != 19456 ||
          h['iterations'] != 2 ||
          h['id'] is! String ||
          (h['id'] as String).length != 32 ||
          base64Decode(h['salt'] as String).length != 16) {
        throw const FormatException();
      }
      final result = VaultEnvelope(
        h,
        root['wrappedKey'] as Map<String, dynamic>,
        root['payload'] as Map<String, dynamic>,
      );
      _box(result.wrappedKey, key: true);
      _box(result.payload);
      return result;
    } catch (_) {
      throw const VaultException(
        'Invalid, unsupported, or oversized Secrets backup.',
      );
    }
  }
}

SecretBox _box(Map<String, dynamic> value, {bool key = false}) {
  final nonce = base64Decode(value['nonce'] as String);
  final mac = base64Decode(value['mac'] as String);
  final data = base64Decode(value['data'] as String);
  if (nonce.length != 12 || mac.length != 16 || (key && data.length != 32)) {
    throw const FormatException('Invalid encrypted data.');
  }
  return SecretBox(data, nonce: nonce, mac: Mac(mac));
}

Map<String, dynamic> _jsonBox(SecretBox box) => {
  'nonce': base64Encode(box.nonce),
  'mac': base64Encode(box.mac.bytes),
  'data': base64Encode(box.cipherText),
};

class OpenVault {
  OpenVault(this.envelope, this.key, this.records);
  VaultEnvelope envelope;
  final Uint8List key;
  List<SecretRecord> records;
  void dispose() {
    key.fillRange(0, key.length, 0);
    records = [];
  }
}

class VaultCrypto {
  static final _aes = AesGcm.with256bits();
  static Future<SecretKey> _passphraseKey(
    String passphrase,
    VaultEnvelope envelope,
  ) => Argon2id(memory: 19456, iterations: 2, parallelism: 1, hashLength: 32)
      .deriveKeyFromPassword(
        password: passphrase,
        nonce: base64Decode(envelope.header['salt'] as String),
      );

  static Future<OpenVault> create(String passphrase) async {
    if (passphrase.length < 12)
      throw const VaultException(
        'Use a master passphrase of at least 12 characters.',
      );
    final key = randomBytes(32);
    final e = VaultEnvelope(
      {
        'format': 'Secrets',
        'version': 1,
        'id': _hex(randomBytes(16)),
        'kdf': 'argon2id',
        'memory': 19456,
        'iterations': 2,
        'parallelism': 1,
        'salt': base64Encode(randomBytes(16)),
      },
      {},
      {},
    );
    e.wrappedKey.addAll(
      _jsonBox(
        await _aes.encrypt(
          key,
          secretKey: await _passphraseKey(passphrase, e),
          aad: [...e.aad, ...utf8.encode('/key')],
        ),
      ),
    );
    final vault = OpenVault(e, key, []);
    await seal(vault, []);
    return vault;
  }

  static Future<OpenVault> unlock(
    VaultEnvelope envelope,
    String passphrase,
  ) async {
    try {
      final key = Uint8List.fromList(
        await _aes.decrypt(
          _box(envelope.wrappedKey, key: true),
          secretKey: await _passphraseKey(passphrase, envelope),
          aad: [...envelope.aad, ...utf8.encode('/key')],
        ),
      );
      try {
        return await unlockWithKey(envelope, key);
      } finally {
        key.fillRange(0, key.length, 0);
      }
    } catch (_) {
      throw const VaultException(
        'Could not unlock. Check the passphrase and backup file.',
      );
    }
  }

  static Future<OpenVault> unlockWithKey(
    VaultEnvelope envelope,
    List<int> key,
  ) async {
    try {
      final clear = await _aes.decrypt(
        _box(envelope.payload),
        secretKey: SecretKey(key),
        aad: [...envelope.aad, ...utf8.encode('/payload')],
      );
      final json = jsonDecode(utf8.decode(clear)) as Map<String, dynamic>;
      final records = (json['records'] as List)
          .map((r) => SecretRecord.fromJson(r as Map<String, dynamic>))
          .toList();
      if (records.map((r) => r.id).toSet().length != records.length)
        throw const FormatException();
      return OpenVault(envelope, Uint8List.fromList(key), records);
    } catch (_) {
      throw const VaultException(
        'Could not decrypt the vault. Use your master passphrase or a valid backup.',
      );
    }
  }

  /// Returns a new envelope; the caller commits it only after persistence succeeds.
  static Future<VaultEnvelope> seal(
    OpenVault vault,
    List<SecretRecord> records,
  ) async {
    final data = utf8.encode(
      jsonEncode({'records': records.map((r) => r.toJson()).toList()}),
    );
    if (data.length > maxVaultBytes ~/ 2)
      throw const VaultException('Vault exceeds the supported size.');
    final payload = _jsonBox(
      await _aes.encrypt(
        data,
        secretKey: SecretKey(vault.key),
        aad: [...vault.envelope.aad, ...utf8.encode('/payload')],
      ),
    );
    final result = VaultEnvelope(
      Map.of(vault.envelope.header),
      Map.of(vault.envelope.wrappedKey),
      payload,
    );
    // Creation starts with an empty payload; normal saves are committed by the repository.
    if (vault.envelope.payload.isEmpty) vault.envelope = result;
    return result;
  }
}

String _hex(List<int> bytes) =>
    bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

class SecretGenerator {
  static String password({
    int length = 24,
    bool upper = true,
    bool lower = true,
    bool digits = true,
    bool symbols = true,
  }) {
    if (length < 4 || length > 256)
      throw const VaultException('Password length must be 4–256.');
    final groups = [
      if (upper) 'ABCDEFGHIJKLMNOPQRSTUVWXYZ',
      if (lower) 'abcdefghijklmnopqrstuvwxyz',
      if (digits) '0123456789',
      if (symbols) '!@#\$%^&*()-_=+[]{}:,.?',
    ];
    if (groups.isEmpty)
      throw const VaultException('Select at least one character group.');
    final random = Random.secure();
    final alphabet = groups.join();
    // Uniform rejection sampling over valid passwords, with at least one character from each selected group.
    while (true) {
      final value = List.generate(
        length,
        (_) => alphabet[random.nextInt(alphabet.length)],
      ).join();
      if (groups.every((g) => value.split('').any(g.contains))) return value;
    }
  }

  static String token({int bytes = 32, bool hex = false}) {
    if (bytes < 16 || bytes > 256)
      throw const VaultException('Token size must be 16–256 random bytes.');
    final value = randomBytes(bytes);
    return hex ? _hex(value) : base64UrlEncode(value).replaceAll('=', '');
  }
}
