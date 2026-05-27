import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:crypto/crypto.dart' as crypto;

class EncryptedPayload {
  const EncryptedPayload({
    required this.ciphertext,
    required this.nonce,
    required this.mac,
  });

  final String ciphertext;
  final String nonce;
  final String mac;
}

abstract final class SecureRoomCrypto {
  static final _aes = AesGcm.with256bits();
  static final _ed25519 = Ed25519();
  static final _random = Random.secure();

  static String generateRoomKey() => base64UrlEncode(_randomBytes(32));

  static String generateClientMessageId() =>
      base64UrlEncode(_randomBytes(18)).replaceAll('=', '');

  static Future<EncryptedPayload> encryptString(
    String plainText,
    String roomKey,
  ) async {
    final nonce = _randomBytes(12);
    final box = await _aes.encrypt(
      utf8.encode(plainText),
      secretKey: SecretKey(_decodeKey(roomKey)),
      nonce: nonce,
    );
    return EncryptedPayload(
      ciphertext: base64Encode(box.cipherText),
      nonce: base64Encode(box.nonce),
      mac: base64Encode(box.mac.bytes),
    );
  }

  static Future<String> decryptString(
    EncryptedPayload payload,
    String roomKey,
  ) async {
    final bytes = await _aes.decrypt(
      SecretBox(
        base64Decode(payload.ciphertext),
        nonce: base64Decode(payload.nonce),
        mac: Mac(base64Decode(payload.mac)),
      ),
      secretKey: SecretKey(_decodeKey(roomKey)),
    );
    return utf8.decode(bytes);
  }

  static Future<EncryptedPayload> encryptBytes(
    Uint8List bytes,
    String roomKey,
  ) async {
    final nonce = _randomBytes(12);
    final box = await _aes.encrypt(
      bytes,
      secretKey: SecretKey(_decodeKey(roomKey)),
      nonce: nonce,
    );
    return EncryptedPayload(
      ciphertext: base64Encode(box.cipherText),
      nonce: base64Encode(box.nonce),
      mac: base64Encode(box.mac.bytes),
    );
  }

  static Future<Uint8List> decryptBytes(
    EncryptedPayload payload,
    String roomKey,
  ) async {
    final bytes = await _aes.decrypt(
      SecretBox(
        base64Decode(payload.ciphertext),
        nonce: base64Decode(payload.nonce),
        mac: Mac(base64Decode(payload.mac)),
      ),
      secretKey: SecretKey(_decodeKey(roomKey)),
    );
    return Uint8List.fromList(bytes);
  }

  static String signMessage({
    required String roomKey,
    required String roomId,
    required String clientMessageId,
    required String nonce,
    required String ciphertext,
    required String createdAt,
  }) {
    final key = _decodeKey(roomKey);
    final payload = utf8.encode(
      '$roomId:$clientMessageId:$nonce:$ciphertext:$createdAt',
    );
    return crypto.Hmac(crypto.sha256, key).convert(payload).toString();
  }

  static bool verifyMessage({
    required String roomKey,
    required String roomId,
    required String clientMessageId,
    required String nonce,
    required String ciphertext,
    required String createdAt,
    required String signature,
  }) {
    final expected = signMessage(
      roomKey: roomKey,
      roomId: roomId,
      clientMessageId: clientMessageId,
      nonce: nonce,
      ciphertext: ciphertext,
      createdAt: createdAt,
    );
    return _constantTimeEquals(expected, signature);
  }

  static Future<({String privateKey, String publicKey})>
      generateSigningKeyPair() async {
    final keyPair = await _ed25519.newKeyPair();
    final privateData = await keyPair.extract();
    return (
      privateKey: base64UrlEncode(privateData.bytes).replaceAll('=', ''),
      publicKey:
          base64UrlEncode(privateData.publicKey.bytes).replaceAll('=', ''),
    );
  }

  static Future<String> signDeviceMessage({
    required String privateKey,
    required String publicKey,
    required String roomId,
    required String senderId,
    required String senderDeviceId,
    required String clientMessageId,
    required String kind,
    required String nonce,
    required String ciphertext,
    required String createdAt,
  }) async {
    final privateBytes = _decodeBase64Url(privateKey);
    final publicBytes = _decodeBase64Url(publicKey);
    final keyPair = SimpleKeyPairData(
      privateBytes,
      publicKey: SimplePublicKey(publicBytes, type: KeyPairType.ed25519),
      type: KeyPairType.ed25519,
    );
    final signature = await _ed25519.sign(
      _messageBytes(
        roomId: roomId,
        senderId: senderId,
        senderDeviceId: senderDeviceId,
        clientMessageId: clientMessageId,
        kind: kind,
        nonce: nonce,
        ciphertext: ciphertext,
        createdAt: createdAt,
      ),
      keyPair: keyPair,
    );
    return base64UrlEncode(signature.bytes).replaceAll('=', '');
  }

  static Future<bool> verifyDeviceMessage({
    required String publicKey,
    required String signature,
    required String roomId,
    required String senderId,
    required String senderDeviceId,
    required String clientMessageId,
    required String kind,
    required String nonce,
    required String ciphertext,
    required String createdAt,
  }) async {
    try {
      final publicBytes = _decodeBase64Url(publicKey);
      final signatureBytes = _decodeBase64Url(signature);
      return _ed25519.verify(
        _messageBytes(
          roomId: roomId,
          senderId: senderId,
          senderDeviceId: senderDeviceId,
          clientMessageId: clientMessageId,
          kind: kind,
          nonce: nonce,
          ciphertext: ciphertext,
          createdAt: createdAt,
        ),
        signature: Signature(
          signatureBytes,
          publicKey: SimplePublicKey(publicBytes, type: KeyPairType.ed25519),
        ),
      );
    } catch (_) {
      return false;
    }
  }

  static bool isValidRoomKey(String roomKey) {
    try {
      _decodeKey(roomKey);
      return true;
    } catch (_) {
      return false;
    }
  }

  static String fingerprint(String value, {int groups = 4}) {
    final digest = crypto.sha256.convert(utf8.encode(value)).bytes;
    return digest
        .take(groups * 2)
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join()
        .toUpperCase()
        .replaceAllMapped(RegExp('.{4}'), (m) => '${m.group(0)} ')
        .trim();
  }

  static List<int> _decodeKey(String roomKey) {
    var normalized = roomKey.trim();
    final remainder = normalized.length % 4;
    if (remainder != 0) {
      normalized = normalized.padRight(normalized.length + 4 - remainder, '=');
    }
    final bytes = base64Url.decode(normalized);
    if (bytes.length != 32) {
      throw const FormatException('Room key must be 32 bytes.');
    }
    return bytes;
  }

  static List<int> _decodeBase64Url(String value) {
    var normalized = value.trim();
    final remainder = normalized.length % 4;
    if (remainder != 0) {
      normalized = normalized.padRight(normalized.length + 4 - remainder, '=');
    }
    return base64Url.decode(normalized);
  }

  static List<int> _messageBytes({
    required String roomId,
    required String senderId,
    required String senderDeviceId,
    required String clientMessageId,
    required String kind,
    required String nonce,
    required String ciphertext,
    required String createdAt,
  }) {
    return utf8.encode(
      [
        'echoproof-room-message-v1',
        roomId,
        senderId,
        senderDeviceId,
        clientMessageId,
        kind,
        nonce,
        ciphertext,
        createdAt,
      ].join('\n'),
    );
  }

  static Uint8List _randomBytes(int length) {
    return Uint8List.fromList(
      List<int>.generate(length, (_) => _random.nextInt(256)),
    );
  }

  static bool _constantTimeEquals(String a, String b) {
    if (a.length != b.length) return false;
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
    }
    return diff == 0;
  }
}
