import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:secrets/app.dart';
import 'package:secrets/core/vault.dart';
import 'package:secrets/platform/android_bridge.dart';

class _BiometricBridge extends AndroidBridge {
  _BiometricBridge(this.vault);
  final OpenVault vault;
  @override
  Future<String?> read() async => vault.envelope.encode();
  @override
  Future<Map<String, dynamic>> status() async => {'biometrics': true};
  @override
  Future<Uint8List?> biometricKey() async =>
      Uint8List.fromList(vault.key).asUnmodifiableView();
}

void main() {
  testWidgets(
    'biometric unlock succeeds with a read-only platform key buffer',
    (tester) async {
      late OpenVault vault;
      await tester.runAsync(() async {
        vault = await VaultCrypto.create('12345678');
      });
      await tester.pumpWidget(SecretsApp(bridge: _BiometricBridge(vault)));
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        await tester.tap(find.text('Use biometrics'));
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await tester.pumpAndSettle();
      expect(find.text('Add secret'), findsOneWidget);
      expect(find.byType(SnackBar), findsNothing);
      await tester.pumpWidget(const SizedBox());
      vault.dispose();
    },
  );
}
