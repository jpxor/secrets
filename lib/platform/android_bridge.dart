import 'package:flutter/services.dart';

import '../core/session.dart';

class AndroidBridge implements VaultStore {
  static const channel = MethodChannel('app.secretskeeper.secrets/platform');
  @override
  Future<String?> read() => channel.invokeMethod<String>('readVault');
  @override
  Future<void> write(String envelope, {bool replacement = false}) =>
      channel.invokeMethod('writeVault', {
        'envelope': envelope,
        'replacement': replacement,
      });
  Future<Map<String, dynamic>> status() async => Map<String, dynamic>.from(
    (await channel.invokeMapMethod<String, dynamic>('status'))!,
  );
  Future<void> copy(String value) =>
      channel.invokeMethod('copySecret', {'value': value});
  Future<void> exportVault() => channel.invokeMethod('exportVault');
  Future<String?> importVault() => channel.invokeMethod<String>('importVault');
  Future<void> enableBiometrics(Uint8List key, String id) =>
      channel.invokeMethod('enableBiometrics', {'key': key, 'id': id});
  Future<Uint8List?> biometricKey() =>
      channel.invokeMethod<Uint8List>('biometricKey');
  Future<void> disableBiometrics() => channel.invokeMethod('disableBiometrics');
  Future<void> backupNow() => channel.invokeMethod('backupNow');
  Future<void> disconnect() => channel.invokeMethod('disconnectBackup');
  Future<Map<String, dynamic>> connect(Map<String, String> config) async =>
      Map<String, dynamic>.from(
        (await channel.invokeMapMethod<String, dynamic>(
          'connectBackup',
          config,
        ))!,
      );
  Future<void> activate() => channel.invokeMethod('activateBackup');
  Future<String?> candidateBackup(String name) =>
      channel.invokeMethod<String>('candidateBackup', {'name': name});
  Future<String?> downloadBackup() =>
      channel.invokeMethod<String>('downloadBackup');
  Future<void> setLockDelay(int seconds) =>
      channel.invokeMethod('setLockDelay', {'seconds': seconds});
}
