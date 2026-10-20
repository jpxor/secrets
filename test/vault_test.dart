import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:secrets/core/vault.dart';

void main() {
  test(
    'portable backup restores without a device key; tampering and wrong passphrases fail',
    () async {
      final vault = await VaultCrypto.create('a memorable master passphrase');
      const records = [
        SecretRecord(
          id: 'one',
          service: 'mail\nwork',
          username: 'alice',
          secret: 'never store me in plaintext',
        ),
      ];
      final envelope = await VaultCrypto.seal(vault, records);
      final exported = envelope.encode();
      expect(exported.contains('alice'), isFalse);
      expect(exported.contains('mail'), isFalse);
      expect(exported.contains('never store'), isFalse);
      final restored = await VaultCrypto.unlock(
        VaultEnvelope.decode(exported),
        'a memorable master passphrase',
      );
      expect(restored.records.single.secret, records.single.secret);
      expect(restored.records.single.service, records.single.service);
      await expectLater(
        VaultCrypto.unlock(envelope, 'wrong master passphrase'),
        throwsA(isA<VaultException>()),
      );
      final tampered = jsonDecode(exported) as Map<String, dynamic>;
      final bytes = base64Decode(tampered['payload']['data'] as String);
      bytes[0] ^= 1;
      tampered['payload']['data'] = base64Encode(bytes);
      await expectLater(
        VaultCrypto.unlock(
          VaultEnvelope.decode(jsonEncode(tampered)),
          'a memorable master passphrase',
        ),
        throwsA(isA<VaultException>()),
      );
      tampered['header']['memory'] = 999999999;
      expect(
        () => VaultEnvelope.decode(jsonEncode(tampered)),
        throwsA(isA<VaultException>()),
      );
      vault.dispose();
      restored.dispose();
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );

  test('generation honors all selected groups and token byte counts', () {
    for (var i = 0; i < 50; i++) {
      final password = SecretGenerator.password(length: 20);
      expect(password.length, 20);
      for (final pattern in [r'[A-Z]', r'[a-z]', r'[0-9]', r'[^a-zA-Z0-9]']) {
        expect(RegExp(pattern).hasMatch(password), isTrue);
      }
    }
    final token = SecretGenerator.token(bytes: 32);
    expect(base64Url.decode(base64Url.normalize(token)).length, 32);
    expect(SecretGenerator.token(bytes: 32, hex: true).length, 64);
    expect(
      () => SecretGenerator.password(
        upper: false,
        lower: false,
        digits: false,
        symbols: false,
      ),
      throwsA(isA<VaultException>()),
    );
  });
}
