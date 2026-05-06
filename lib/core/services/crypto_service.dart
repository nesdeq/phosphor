import 'dart:collection';
import 'dart:convert';

import 'package:cryptography/cryptography.dart';

/// End-to-end encryption for multiplayer sessions.
///
/// Uses HKDF-SHA256 to derive a 256-bit key from the encryption secret
/// (the second half of the session code), then AES-256-GCM for authenticated
/// encryption. The relay server only sees the routing code, never the secret.
///
/// Replay protection: incoming nonces are checked against an LRU set of
/// recently-seen nonces; duplicates throw. AES-GCM mandates fresh nonces
/// per encryption, so any duplicate is by definition a replay.
class CryptoService {
  static const _salt = 'PHOSPHOR-SESSION-v1';
  static const _info = 'aes-256-gcm-key';

  /// Recent-nonce window for replay rejection. 1024 entries covers any
  /// reasonable burst; older nonces silently drop out of the set.
  static const _seenNonceWindow = 1024;

  final _aesGcm = AesGcm.with256bits();
  SecretKey? _key;

  final Set<String> _seenNonces = HashSet<String>();
  final Queue<String> _nonceOrder = Queue<String>();

  /// Derive an AES-256 key from the session code via HKDF.
  Future<void> deriveKey(String sessionCode) async {
    final hkdf = Hkdf(hmac: Hmac(Sha256()), outputLength: 32);
    _key = await hkdf.deriveKey(
      secretKey: SecretKeyData(utf8.encode(sessionCode)),
      nonce: utf8.encode(_salt),
      info: utf8.encode(_info),
    );
  }

  /// Encrypt plaintext. [msgType] is bound as AAD to prevent type confusion.
  /// Returns base64-encoded nonce and ciphertext (with appended GCM tag).
  Future<({String nonce, String ciphertext})> encrypt(
    String plaintext,
    String msgType,
  ) async {
    final key = _key;
    if (key == null) throw StateError('Call deriveKey() first');

    final secretBox = await _aesGcm.encrypt(
      utf8.encode(plaintext),
      secretKey: key,
      aad: utf8.encode(msgType),
    );

    final combined = [...secretBox.cipherText, ...secretBox.mac.bytes];
    return (
      nonce: base64Encode(secretBox.nonce),
      ciphertext: base64Encode(combined),
    );
  }

  /// Decrypt ciphertext. [msgType] must match the AAD used during encryption.
  /// Throws on duplicate nonce (replay).
  Future<String> decrypt(
    String nonceB64,
    String ciphertextB64,
    String msgType,
  ) async {
    final key = _key;
    if (key == null) throw StateError('Call deriveKey() first');

    if (!_seenNonces.add(nonceB64)) {
      throw StateError('Replay detected: duplicate nonce');
    }
    _nonceOrder.add(nonceB64);
    while (_nonceOrder.length > _seenNonceWindow) {
      _seenNonces.remove(_nonceOrder.removeFirst());
    }

    final nonce = base64Decode(nonceB64);
    final combined = base64Decode(ciphertextB64);

    // Last 16 bytes are the GCM authentication tag
    final ct = combined.sublist(0, combined.length - 16);
    final mac = Mac(combined.sublist(combined.length - 16));

    final clearText = await _aesGcm.decrypt(
      SecretBox(ct, nonce: nonce, mac: mac),
      secretKey: key,
      aad: utf8.encode(msgType),
    );

    return utf8.decode(clearText);
  }
}
