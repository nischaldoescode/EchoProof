import 'package:echoproof/features/rooms/data/anonymous_secure_room_service.dart';
import 'package:echoproof/features/rooms/data/secure_room_crypto.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('anonymous secure room helpers', () {
    test('accepts only anonymous invite codes', () {
      expect(
        AnonymousSecureRoomService.normalizeInviteCode('ANON-abcde23456'),
        'anon-abcde23456',
      );
      expect(
        AnonymousSecureRoomService.normalizeInviteCode('abcde23456'),
        isNull,
      );
      expect(
        AnonymousSecureRoomService.normalizeInviteCode('anon-too-short'),
        isNull,
      );
    });

    test('extracts code and fragment key from shared invite text', () {
      final roomKey = SecureRoomCrypto.generateRoomKey();
      final link =
          'https://echoproof.online/room?code=anon-abcde23456#key=$roomKey';

      final invite = AnonymousSecureRoomService.parseInviteText(link);

      expect(invite.code, 'anon-abcde23456');
      expect(invite.key, roomKey);
    });

    test('sanitizes temporary display names', () {
      expect(
        AnonymousSecureRoomService.sanitizeDisplayName('  Quiet   Guest  '),
        'Quiet Guest',
      );
      expect(AnonymousSecureRoomService.sanitizeDisplayName('A'), isNull);
    });

    test('token hash is stable base64url without padding', () {
      final hash = SecureRoomCrypto.sha256Base64Url('member-token');

      expect(hash, SecureRoomCrypto.sha256Base64Url('member-token'));
      expect(hash, isNot(contains('=')));
      expect(hash.length, greaterThanOrEqualTo(43));
    });
  });
}
