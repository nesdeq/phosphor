import 'package:flutter_test/flutter_test.dart';
import 'package:phosphor/core/services/crypto_service.dart';

void main() {
  group('CryptoService', () {
    late CryptoService alice;
    late CryptoService bob;

    setUp(() async {
      alice = CryptoService();
      bob = CryptoService();
      const sharedSecret = 'PHO-ABCDEF-GHJKLMNPQRST';
      await alice.deriveKey(sharedSecret);
      await bob.deriveKey(sharedSecret);
    });

    test('encrypt/decrypt round-trips identical strings', () async {
      const plaintext = 'hello phosphor';
      final box = await alice.encrypt(plaintext, 'output');
      final decrypted = await bob.decrypt(box.nonce, box.ciphertext, 'output');
      expect(decrypted, plaintext);
    });

    test('different keys cannot decrypt each other', () async {
      final eve = CryptoService();
      await eve.deriveKey('PHO-DIFFERENT-SECRETXXXXXX');
      final box = await alice.encrypt('secret', 'output');
      expect(
        () => eve.decrypt(box.nonce, box.ciphertext, 'output'),
        throwsA(anything),
      );
    });

    test('AAD mismatch (msgType) rejects decryption', () async {
      final box = await alice.encrypt('payload', 'output');
      expect(
        () => bob.decrypt(box.nonce, box.ciphertext, 'input'),
        throwsA(anything),
      );
    });

    test('decrypt before deriveKey throws StateError', () async {
      final fresh = CryptoService();
      expect(
        () => fresh.decrypt('n', 'c', 'output'),
        throwsA(isA<StateError>()),
      );
    });

    test('encrypt before deriveKey throws StateError', () async {
      final fresh = CryptoService();
      expect(
        () => fresh.encrypt('p', 'output'),
        throwsA(isA<StateError>()),
      );
    });

    test('replay of identical ciphertext throws', () async {
      final box = await alice.encrypt('once', 'output');
      final first = await bob.decrypt(box.nonce, box.ciphertext, 'output');
      expect(first, 'once');
      expect(
        () => bob.decrypt(box.nonce, box.ciphertext, 'output'),
        throwsA(isA<StateError>()),
      );
    });

    test('each encrypt produces a fresh nonce', () async {
      final a = await alice.encrypt('x', 'output');
      final b = await alice.encrypt('x', 'output');
      expect(a.nonce, isNot(equals(b.nonce)));
      // Identical plaintext + AAD must still produce different ciphertexts
      // because AES-GCM uses a fresh random nonce per call.
      expect(a.ciphertext, isNot(equals(b.ciphertext)));
    });

    test('large nonce window does not falsely reject distinct nonces',
        () async {
      // Send 2000 messages — well above the 1024 LRU window — and all should
      // decrypt successfully because each gets a fresh nonce.
      for (var i = 0; i < 2000; i++) {
        final box = await alice.encrypt('msg-$i', 'output');
        final got = await bob.decrypt(box.nonce, box.ciphertext, 'output');
        expect(got, 'msg-$i');
      }
    });
  });
}
