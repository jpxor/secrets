import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:secrets/core/session.dart';
import 'package:secrets/core/vault.dart';
import 'package:secrets/platform/android_bridge.dart';
import 'package:secrets/ui/auth.dart';
import 'package:secrets/ui/vault_page.dart';
import 'package:secrets/ui/provider_page.dart';

class _Store implements VaultStore {
  String? text;
  @override
  Future<String?> read() async => text;
  @override
  Future<void> write(String envelope, {bool replacement = false}) async {
    text = envelope;
  }
}

void main() {
  testWidgets(
    'regression: switching providers never reuses another server password',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: ProviderPage(
            bridge: AndroidBridge(),
            restoring: false,
            onConnected: (_) async => true,
          ),
        ),
      );
      Future<void> choose(String name) async {
        tester
            .state<ScrollableState>(find.byType(Scrollable).first)
            .position
            .jumpTo(0);
        await tester.pumpAndSettle();
        final selector = find.byType(DropdownButtonFormField<String>);
        await tester.ensureVisible(selector);
        await tester.tap(selector);
        await tester.pumpAndSettle();
        await tester.tap(find.text(name).last);
        await tester.pumpAndSettle();
      }

      await choose('SFTP');
      final password = find.byWidgetPredicate(
        (w) =>
            w is TextField && w.decoration?.labelText == 'Password (optional)',
      );
      await tester.ensureVisible(password);
      await tester.enterText(password, 'test-server-password');
      await choose('Git');
      final token = tester.widget<TextField>(
        find.byWidgetPredicate(
          (w) =>
              w is TextField &&
              w.decoration?.labelText == 'Password / access token (optional)',
        ),
      );
      expect(token.controller!.text, isEmpty);
    },
  );
  testWidgets('service search does not expose username matches', (
    tester,
  ) async {
    final session = VaultSession(_Store());
    await tester.runAsync(() async {
      await session.create('a memorable master passphrase');
      await session.save([
        const SecretRecord(
          id: 'one',
          service: 'Mail service',
          username: 'Alice private name',
          secret: 'sensitive',
        ),
      ]);
    });
    await tester.pumpWidget(
      MaterialApp(
        home: VaultPage(
          session: session,
          bridge: AndroidBridge(),
          status: const {},
          settings: () async {},
        ),
      ),
    );
    expect(find.text('Mail service'), findsOneWidget);
    expect(find.text('sensitive'), findsNothing);
    await tester.enterText(find.byType(TextField), 'Alice');
    await tester.pump();
    expect(find.text('No matching services.'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'MAIL');
    await tester.pump();
    expect(find.text('Mail service'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    session.dispose();
  });

  testWidgets('fresh installation offers recovery before creating a vault', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: UnlockPage(
          exists: false,
          busy: false,
          biometricEnabled: false,
          error: null,
          unlock: (_) async {},
          create: () async {},
          biometric: () async {},
          importFile: () async {},
          remoteRestore: () async {},
        ),
      ),
    );
    expect(find.text('Create vault'), findsOneWidget);
    expect(find.text('Restore from encrypted file'), findsOneWidget);
    expect(find.text('Restore from backup provider'), findsOneWidget);
  });
}
