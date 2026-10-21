import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:secrets/platform/android_bridge.dart';
import 'package:secrets/ui/provider_page.dart';

const firstKey = 'SHA256:AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA';
const secondKey = 'SHA256:BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB';

class _Bridge extends AndroidBridge {
  final calls = <Map<String, String>>[];
  bool changed = false;
  @override
  Future<Map<String, dynamic>> connect(Map<String, String> config) async {
    calls.add(Map.of(config));
    final expected = changed && calls.length > 1 ? secondKey : firstKey;
    if (config['fingerprint'] != expected) {
      throw PlatformException(
        code: 'ssh_host_key',
        details: {
          'fingerprint': expected,
          'previousFingerprint': config['fingerprint'] ?? '',
        },
      );
    }
    return {'exists': false};
  }
}

Future<void> _openSftp(
  WidgetTester tester,
  _Bridge bridge,
  VoidCallback connected,
) async {
  await tester.pumpWidget(
    MaterialApp(
      home: ProviderPage(
        bridge: bridge,
        restoring: false,
        onConnected: (_) async {
          connected();
          return false;
        },
      ),
    ),
  );
  await tester.tap(find.byType(DropdownButtonFormField<String>));
  await tester.pumpAndSettle();
  await tester.tap(find.text('SFTP').last);
  await tester.pumpAndSettle();
  Future<void> fill(String label, String value) async {
    final field = find.byWidgetPredicate(
      (w) => w is TextField && w.decoration?.labelText == label,
    );
    await tester.ensureVisible(field);
    await tester.enterText(field, value);
  }

  await fill('Server host', 'server.local');
  await fill('Port', '2222');
  await fill('Username', 'tester');
  await fill('Password (optional)', 'synthetic-test-password');
  expect(
    find.byWidgetPredicate(
      (w) =>
          w is TextField &&
          (w.decoration?.labelText?.contains('fingerprint') ?? false),
    ),
    findsNothing,
  );
  final button = find.text('Connect and enable backup');
  FocusManager.instance.primaryFocus?.unfocus();
  await tester.pumpAndSettle();
  final scroll = tester.state<ScrollableState>(find.byType(Scrollable).first);
  scroll.position.jumpTo(scroll.position.maxScrollExtent);
  await tester.pumpAndSettle();
  await tester.tap(button);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

void main() {
  testWidgets(
    'SFTP password can be shown and hidden without changing its value',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: ProviderPage(
            bridge: _Bridge(),
            restoring: false,
            onConnected: (_) async => false,
          ),
        ),
      );
      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('SFTP').last);
      await tester.pumpAndSettle();
      final password = find.byWidgetPredicate(
        (w) =>
            w is TextField && w.decoration?.labelText == 'Password (optional)',
      );
      await tester.ensureVisible(password);
      await tester.enterText(password, 'synthetic-test-password');
      expect(tester.widget<TextField>(password).obscureText, isTrue);
      final show = find.byTooltip('Show password');
      await tester.ensureVisible(show);
      await tester.pumpAndSettle();
      await tester.tap(show);
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(password).obscureText, isFalse);
      expect(
        tester.widget<TextField>(password).controller!.text,
        'synthetic-test-password',
      );
      await tester.tap(find.byTooltip('Hide password'));
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(password).obscureText, isTrue);
      expect(
        tester.widget<TextField>(password).controller!.text,
        'synthetic-test-password',
      );
    },
  );

  testWidgets('SFTP cancellation never approves or activates the destination', (
    tester,
  ) async {
    final bridge = _Bridge();
    var connected = 0;
    await _openSftp(tester, bridge, () => connected++);
    expect(find.text('Trust this SSH host?'), findsOneWidget);
    expect(find.text('server.local:2222'), findsOneWidget);
    expect(find.text(firstKey), findsOneWidget);
    expect(bridge.calls, hasLength(1));
    expect(connected, 0);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(bridge.calls, hasLength(1));
    expect(connected, 0);
    expect(bridge.calls.single.containsKey('fingerprint'), isFalse);
  });

  testWidgets(
    'SFTP approval retries with the displayed key and preserves credentials',
    (tester) async {
      final bridge = _Bridge();
      var connected = 0;
      await _openSftp(tester, bridge, () => connected++);
      await tester.tap(find.text('Trust and connect'));
      await tester.pumpAndSettle();
      expect(bridge.calls, hasLength(2));
      expect(bridge.calls.last['fingerprint'], firstKey);
      expect(bridge.calls.last['host'], 'server.local');
      expect(bridge.calls.last['port'], '2222');
      expect(bridge.calls.last['password'], 'synthetic-test-password');
      expect(connected, 1);
    },
  );

  testWidgets(
    'SFTP key changes during retry require a separate explicit decision',
    (tester) async {
      final bridge = _Bridge()..changed = true;
      var connected = 0;
      await _openSftp(tester, bridge, () => connected++);
      await tester.tap(find.text('Trust and connect'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('SSH host key changed'), findsOneWidget);
      expect(find.text(firstKey), findsOneWidget);
      expect(find.text(secondKey), findsOneWidget);
      expect(connected, 0);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(bridge.calls, hasLength(2));
      expect(connected, 0);
    },
  );
}
