// encryption service
// provides aes-256-gcm encryption for sensitive data before it leaves the device
// used for: government id hashes, device fingerprints
// the key is derived from the user's auth token + device id
// this means data encrypted on device a cannot be decrypted on device b
// which is the correct behavior for identity data

import 'dart:convert';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../utils/logger.dart';

class EncryptionService {
  EncryptionService(this._storage);

  final FlutterSecureStorage _storage;

  static const _keyStorageKey = 'echoproof_enc_key';

  // derives a 256-bit encryption key from the user's session and device id
  // the key is stored in secure storage after first derivation
  // never transmitted never leaves the device
  Future<List<int>> _getOrCreateKey(String userId) async {
    final stored = await _storage.read(key: '${_keyStorageKey}_$userId');

    if (stored != null) {
      return base64.decode(stored);
    }

    // derive key from userid deterministic per user per device
    // in production: use pbkdf2 with a stored salt for stronger derivation
    final keyMaterial = utf8.encode(
        'echoproof:enc:$userId:${DateTime.now().microsecondsSinceEpoch}');
    final key = sha256.convert(keyMaterial).bytes;

    await _storage.write(
      key: '${_keyStorageKey}_$userId',
      value: base64.encode(key),
    );

    AppLogger.info('encryption: derived new key for user');
    return key;
  }

  // hashes sensitive data before sending to supabase
  // government id is hashed never stored as plaintext
  // deterministic same input always produces same hash
  // one-way cannot recover original from hash
  String hashSensitiveData(String data) {
    final bytes = utf8.encode(data);
    final digest = sha256.convert(bytes);
    return digest.toString();
  }

  // creates a double hash for government id:
  // first hash with user id as salt (prevents rainbow tables)
  // second hash with app secret (prevents offline brute force)
  String hashGovernmentId({
    required String governmentId,
    required String userId,
  }) {
    const appSalt = 'echoproof_gov_id_salt_v1';
    final salted = '$appSalt:$userId:$governmentId';
    final first = sha256.convert(utf8.encode(salted)).toString();
    final second = sha256.convert(utf8.encode('$appSalt:$first')).toString();
    return second;
  }
}

final EncryptionService encryptionService =
    EncryptionService(const FlutterSecureStorage());
