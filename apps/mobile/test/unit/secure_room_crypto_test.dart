import 'package:echoproof/features/rooms/data/secure_room_crypto.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('secure room crypto', () {
    test('encrypts and decrypts room text with a 256-bit room key', () async {
      final roomKey = SecureRoomCrypto.generateRoomKey();
      final payload = await SecureRoomCrypto.encryptString(
        'proof-sensitive message',
        roomKey,
      );

      final decrypted = await SecureRoomCrypto.decryptString(payload, roomKey);

      expect(decrypted, 'proof-sensitive message');
      expect(SecureRoomCrypto.isValidRoomKey(roomKey), isTrue);
    });

    test('verifies sender signatures and rejects tampered ciphertext',
        () async {
      const roomId = 'room-1';
      const senderId = 'user-1';
      const senderDeviceId = 'device-1';
      const kind = 'text';
      const createdAt = '2026-05-17T12:00:00.000Z';

      final roomKey = SecureRoomCrypto.generateRoomKey();
      final signingKey = await SecureRoomCrypto.generateSigningKeyPair();
      final encrypted = await SecureRoomCrypto.encryptString('hello', roomKey);
      final clientMessageId = SecureRoomCrypto.generateClientMessageId();

      final roomSignature = SecureRoomCrypto.signMessage(
        roomKey: roomKey,
        roomId: roomId,
        clientMessageId: clientMessageId,
        nonce: encrypted.nonce,
        ciphertext: encrypted.ciphertext,
        createdAt: createdAt,
      );
      final senderSignature = await SecureRoomCrypto.signDeviceMessage(
        privateKey: signingKey.privateKey,
        publicKey: signingKey.publicKey,
        roomId: roomId,
        senderId: senderId,
        senderDeviceId: senderDeviceId,
        clientMessageId: clientMessageId,
        kind: kind,
        nonce: encrypted.nonce,
        ciphertext: encrypted.ciphertext,
        createdAt: createdAt,
      );

      expect(
        SecureRoomCrypto.verifyMessage(
          roomKey: roomKey,
          roomId: roomId,
          clientMessageId: clientMessageId,
          nonce: encrypted.nonce,
          ciphertext: encrypted.ciphertext,
          createdAt: createdAt,
          signature: roomSignature,
        ),
        isTrue,
      );
      expect(
        await SecureRoomCrypto.verifyDeviceMessage(
          publicKey: signingKey.publicKey,
          signature: senderSignature,
          roomId: roomId,
          senderId: senderId,
          senderDeviceId: senderDeviceId,
          clientMessageId: clientMessageId,
          kind: kind,
          nonce: encrypted.nonce,
          ciphertext: encrypted.ciphertext,
          createdAt: createdAt,
        ),
        isTrue,
      );
      expect(
        SecureRoomCrypto.verifyMessage(
          roomKey: roomKey,
          roomId: roomId,
          clientMessageId: clientMessageId,
          nonce: encrypted.nonce,
          ciphertext: '${encrypted.ciphertext}tampered',
          createdAt: createdAt,
          signature: roomSignature,
        ),
        isFalse,
      );
      expect(
        await SecureRoomCrypto.verifyDeviceMessage(
          publicKey: signingKey.publicKey,
          signature: senderSignature,
          roomId: roomId,
          senderId: senderId,
          senderDeviceId: senderDeviceId,
          clientMessageId: clientMessageId,
          kind: kind,
          nonce: encrypted.nonce,
          ciphertext: '${encrypted.ciphertext}tampered',
          createdAt: createdAt,
        ),
        isFalse,
      );
    });

    test('rejects malformed room keys before join', () {
      expect(SecureRoomCrypto.isValidRoomKey('not-a-real-room-key'), isFalse);
    });
  });
}
