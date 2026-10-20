import 'package:flutter_test/flutter_test.dart';
import 'package:secrets/core/session.dart';
import 'package:secrets/core/vault.dart';

class MemoryStore implements VaultStore {
  String? content;
  bool failWrites = false;
  bool failReads = false;
  @override
  Future<String?> read() async {
    if (failReads) throw StateError('Corrupted local file');
    return content;
  }

  @override
  Future<void> write(String envelope, {bool replacement = false}) async {
    if (failWrites) throw StateError('Disk full');
    content = envelope;
  }
}

void main() {
  testWidgets(
    'regression: repeated background events keep the original lock deadline',
    (tester) async {
      final session = VaultSession(MemoryStore());
      addTearDown(session.dispose);
      await tester.runAsync(
        () => session.create('a memorable master passphrase'),
      );
      final start = DateTime(2026);
      session.background(now: start);
      await tester.pump(const Duration(seconds: 20));
      session.background(now: start.add(const Duration(seconds: 20)));
      await tester.pump(const Duration(seconds: 10));
      expect(session.unlocked, isFalse);
    },
  );
  test(
    'regression: unreadable local storage cannot be overwritten by Create',
    () async {
      final store = MemoryStore()..failReads = true;
      final session = VaultSession(store);
      await expectLater(session.initialize(), throwsStateError);
      expect(session.exists, isTrue);
      await expectLater(
        session.create('a memorable master passphrase'),
        throwsA(isA<VaultException>()),
      );
      expect(store.content, isNull);
      session.dispose();
    },
  );
  test(
    'failed save/import preserve the original vault and active foreground use does not lock',
    () async {
      final store = MemoryStore();
      final session = VaultSession(store);
      await session.create('a memorable master passphrase');
      const record = SecretRecord(
        id: '1',
        service: 'original',
        username: 'u',
        secret: 's',
      );
      await session.save([record]);
      final original = store.content;
      store.failWrites = true;
      await expectLater(session.save([]), throwsStateError);
      expect(session.records.single.service, 'original');
      expect(store.content, original);
      store.failWrites = false;
      await expectLater(
        session.restore(original!, 'incorrect password'),
        throwsA(isA<VaultException>()),
      );
      expect(store.content, original);
      expect(session.records.single.service, 'original');
      final start = DateTime(2026);
      session.foreground(now: start.add(const Duration(hours: 1)));
      expect(session.unlocked, isTrue);
      session.background(now: start);
      session.foreground(now: start.add(const Duration(seconds: 29)));
      expect(session.unlocked, isTrue);
      session.background(now: start);
      session.foreground(now: start.add(const Duration(seconds: 30)));
      expect(session.unlocked, isFalse);
      session.dispose();
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );
}
