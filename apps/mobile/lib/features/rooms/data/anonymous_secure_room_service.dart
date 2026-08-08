// anonymous secure room service
// keeps guest room keys and member tokens local so anonymous rooms never create accounts

import 'dart:async';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/utils/logger.dart';
import 'secure_room_crypto.dart';
import 'secure_room_service.dart';

class AnonymousSecureRoomSummary {
  const AnonymousSecureRoomSummary({
    required this.id,
    required this.inviteCode,
    required this.status,
    required this.messageTtlSeconds,
    required this.maxMembers,
    required this.createdAt,
    required this.expiresAt,
    this.activeMemberCount = 1,
  });

  final String id;
  final String inviteCode;
  final String status;
  final int messageTtlSeconds;
  final int maxMembers;
  final int activeMemberCount;
  final DateTime createdAt;
  final DateTime expiresAt;

  bool get isActive =>
      status == 'active' && expiresAt.isAfter(DateTime.now().toUtc());

  String get memberProgressLabel =>
      '${activeMemberCount.clamp(1, maxMembers)}/$maxMembers joined';
}

class AnonymousRoomMember {
  const AnonymousRoomMember({
    required this.id,
    required this.role,
    required this.displayName,
    required this.avatarSeed,
    required this.joinedAt,
    this.lastSeenAt,
  });

  final String id;
  final String role;
  final String displayName;
  final String avatarSeed;
  final DateTime joinedAt;
  final DateTime? lastSeenAt;

  bool get isHost => role == 'host';
}

class AnonymousRoomMessage {
  const AnonymousRoomMessage({
    required this.id,
    required this.roomId,
    required this.senderMemberId,
    required this.kind,
    required this.clientMessageId,
    required this.createdAt,
    required this.expiresAt,
    required this.integrityOk,
    this.text,
  });

  final String id;
  final String roomId;
  final String senderMemberId;
  final String kind;
  final String clientMessageId;
  final DateTime createdAt;
  final DateTime expiresAt;
  final bool integrityOk;
  final String? text;

  bool get isExpired => expiresAt.isBefore(DateTime.now());
}

class AnonymousRoomState {
  const AnonymousRoomState({
    required this.room,
    required this.currentMember,
    required this.members,
    required this.messages,
    required this.serverNow,
  });

  final AnonymousSecureRoomSummary room;
  final AnonymousRoomMember currentMember;
  final List<AnonymousRoomMember> members;
  final List<AnonymousRoomMessage> messages;
  final DateTime serverNow;
}

class CreatedAnonymousSecureRoom {
  const CreatedAnonymousSecureRoom({
    required this.room,
    required this.member,
    required this.roomKey,
    required this.shareLink,
  });

  final AnonymousSecureRoomSummary room;
  final AnonymousRoomMember member;
  final String roomKey;
  final String shareLink;
}

class AnonymousSecureRoomService {
  AnonymousSecureRoomService._();
  static final instance = AnonymousSecureRoomService._();

  static const int maxAnonymousTextCharacters = 1000;
  static const int maxAnonymousTextLines = 20;
  static const _storage = FlutterSecureStorage();
  static final _anonCodeRegex = RegExp(r'^anon-[a-z2-9]{10}$');

  final _client = Supabase.instance.client;
  final _localSendTimes = <String, List<DateTime>>{};

  bool get accountIsSignedIn => _client.auth.currentUser != null;

  Future<CreatedAnonymousSecureRoom> createRoom({
    required String displayName,
    int ttlSeconds = 120,
    int maxMembers = 2,
  }) async {
    _assertSignedOut();
    final cleanName = sanitizeDisplayName(displayName);
    if (cleanName == null) {
      throw Exception('Use a name between 2 and 32 characters.');
    }

    final roomKey = SecureRoomCrypto.generateRoomKey();
    final data = await _invoke(
      'create-anonymous-secure-room',
      body: {
        'display_name': cleanName,
        'ttl_seconds': ttlSeconds.clamp(120, 300),
        'max_members': maxMembers.clamp(2, 3),
      },
    );
    final room = _mapRoom(data['room']);
    final member = _mapMember(data['member']);
    final token = data['member_token'] as String? ?? '';
    if (token.isEmpty) throw Exception('Anonymous member token was missing.');

    await _saveCredentials(
      roomId: room.id,
      roomKey: roomKey,
      memberToken: token,
      displayName: cleanName,
      memberId: member.id,
    );

    return CreatedAnonymousSecureRoom(
      room: room,
      member: member,
      roomKey: roomKey,
      shareLink: buildShareLink(room.inviteCode, roomKey),
    );
  }

  Future<AnonymousSecureRoomSummary> joinRoom({
    required String inviteCode,
    required String roomKey,
    required String displayName,
  }) async {
    _assertSignedOut();
    final code = normalizeInviteCode(inviteCode);
    if (code == null) {
      throw Exception('Anonymous room codes must start with anon-.');
    }
    if (!SecureRoomCrypto.isValidRoomKey(roomKey)) {
      throw Exception('This invite key is invalid or incomplete.');
    }
    final cleanName = sanitizeDisplayName(displayName);
    if (cleanName == null) {
      throw Exception('Use a name between 2 and 32 characters.');
    }

    final data = await _invoke(
      'join-anonymous-secure-room',
      body: {'invite_code': code, 'display_name': cleanName},
    );
    final room = _mapRoom(data['room']);
    final member = _mapMember(data['member']);
    final token = data['member_token'] as String? ?? '';
    if (token.isEmpty) throw Exception('Anonymous member token was missing.');

    await _saveCredentials(
      roomId: room.id,
      roomKey: roomKey.trim(),
      memberToken: token,
      displayName: cleanName,
      memberId: member.id,
    );
    return room;
  }

  Future<AnonymousRoomState> loadState(String roomId) async {
    _assertSignedOut();
    final credentials = await _credentials(roomId);
    final data = await _invoke(
      'anonymous-secure-room-state',
      body: {'room_id': roomId, 'member_token': credentials.memberToken},
    );
    final room = _mapRoom(data['room']);
    final currentMember = _mapMember(data['member']);
    final members = List<Map<String, dynamic>>.from(
      (data['members'] as List?) ?? const [],
    ).map(_mapMember).toList();
    final messages = <AnonymousRoomMessage>[];
    for (final raw in (data['messages'] as List?) ?? const []) {
      messages.add(
        await _decryptMessage(
          Map<String, dynamic>.from(raw as Map),
          credentials.roomKey,
        ),
      );
    }

    return AnonymousRoomState(
      room: room,
      currentMember: currentMember,
      members: members,
      messages: messages.where((m) => !m.isExpired).toList(),
      serverNow:
          DateTime.tryParse(data['server_now'] as String? ?? '')?.toUtc() ??
          DateTime.now().toUtc(),
    );
  }

  Future<AnonymousRoomMessage> sendText({
    required String roomId,
    required String text,
    int ttlSeconds = 120,
  }) async {
    _assertSignedOut();
    final clean = SecureRoomService.redactLinks(
      SecureRoomService.sanitizeRoomText(text),
    );
    if (clean.isEmpty) throw Exception('Message is empty.');
    _assertLocalSendRate(roomId);

    final credentials = await _credentials(roomId);
    final encrypted = await SecureRoomCrypto.encryptString(
      clean,
      credentials.roomKey,
    );
    final clientMessageId = SecureRoomCrypto.generateClientMessageId();
    final createdAt = DateTime.now().toUtc().toIso8601String();
    final signature = SecureRoomCrypto.signMessage(
      roomKey: credentials.roomKey,
      roomId: roomId,
      clientMessageId: clientMessageId,
      nonce: encrypted.nonce,
      ciphertext: encrypted.ciphertext,
      createdAt: createdAt,
    );

    final data = await _invoke(
      'send-anonymous-secure-room-message',
      body: {
        'room_id': roomId,
        'member_token': credentials.memberToken,
        'kind': 'text',
        'ciphertext': encrypted.ciphertext,
        'nonce': encrypted.nonce,
        'mac': encrypted.mac,
        'signature': signature,
        'client_message_id': clientMessageId,
        'client_created_at': createdAt,
        'ttl_seconds': ttlSeconds.clamp(120, 300),
      },
    );

    return _decryptMessage(
      Map<String, dynamic>.from(data['message'] as Map),
      credentials.roomKey,
    );
  }

  Future<void> leaveRoom(String roomId) async {
    final credentials = await _credentials(roomId);
    await _invoke(
      'leave-anonymous-secure-room',
      body: {'room_id': roomId, 'member_token': credentials.memberToken},
    );
    await forgetRoom(roomId);
  }

  Future<void> forgetRoom(String roomId) {
    // anonymous rooms are intentionally device-local, so clearing these values
    // makes the old invite unusable on this install without touching accounts
    return Future.wait([
      _storage.delete(key: _keyName(roomId)),
      _storage.delete(key: _tokenName(roomId)),
      _storage.delete(key: _displayNameKey(roomId)),
      _storage.delete(key: _memberIdKey(roomId)),
      _clearLastRoomIfCurrent(roomId),
    ]);
  }

  Future<String?> resumableRoomId() async {
    final roomId = await _storage.read(key: _lastRoomIdKey);
    if (roomId == null || roomId.isEmpty) return null;
    return await hasCredentials(roomId) ? roomId : null;
  }

  Future<bool> hasCredentials(String roomId) async {
    final key = await _storage.read(key: _keyName(roomId));
    final token = await _storage.read(key: _tokenName(roomId));
    return key != null &&
        key.isNotEmpty &&
        SecureRoomCrypto.isValidRoomKey(key) &&
        token != null &&
        token.isNotEmpty;
  }

  Future<String> requireRoomKey(String roomId) async {
    final credentials = await _credentials(roomId);
    return credentials.roomKey;
  }

  static String? normalizeInviteCode(String value) {
    final code = value.trim().toLowerCase();
    return _anonCodeRegex.hasMatch(code) ? code : null;
  }

  static String? sanitizeDisplayName(String value) {
    final clean = value
        .replaceAll(RegExp(r'[\u0000-\u001F\u007F]'), '')
        .replaceAll(RegExp(r'[\u202A-\u202E\u2066-\u2069]'), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (clean.length < 2 || clean.length > 32) return null;
    return clean;
  }

  static String buildShareLink(String inviteCode, String roomKey) {
    final baseUrl = const String.fromEnvironment(
      'ROOM_INVITE_URL',
      defaultValue: 'https://echoproof.online/room',
    );
    final separator = baseUrl.contains('?') ? '&' : '?';
    return '$baseUrl${separator}code=${Uri.encodeComponent(inviteCode)}'
        '#key=${Uri.encodeComponent(roomKey)}';
  }

  static ({String? code, String? key}) parseInviteText(String value) {
    final text = value.trim();
    String? code;
    String? key;
    final uri = Uri.tryParse(text);
    if (uri != null) {
      code = normalizeInviteCode(uri.queryParameters['code'] ?? '');
      if (uri.fragment.isNotEmpty) {
        try {
          key = Uri.splitQueryString(uri.fragment)['key'];
        } catch (_) {
          key = null;
        }
      }
    }
    code ??= RegExp(
      r'\banon-[a-z2-9]{10}\b',
      caseSensitive: false,
    ).firstMatch(text)?.group(0)?.toLowerCase();
    key ??= RegExp(r'key=([^&\s]+)').firstMatch(text)?.group(1);
    return (code: code == null ? null : normalizeInviteCode(code), key: key);
  }

  Future<Map<String, dynamic>> _invoke(
    String functionName, {
    required Map<String, dynamic> body,
  }) async {
    final response = await _client.functions.invoke(functionName, body: body);
    final raw = response.data;
    if (raw is! Map) throw Exception('Anonymous room server response failed.');
    final data = Map<String, dynamic>.from(raw);
    if (data['error'] != null) {
      AppLogger.warn(
        'anonymous rooms: $functionName failed ${data['error']} '
        'stage=${data['diagnostic_stage'] ?? 'unknown'} '
        'code=${data['diagnostic_code'] ?? 'none'} '
        'ref=${data['request_id'] ?? 'none'}',
      );
      throw Exception(_functionErrorMessage(data));
    }
    return data;
  }

  Future<AnonymousRoomMessage> _decryptMessage(
    Map<String, dynamic> row,
    String roomKey,
  ) async {
    final roomId = row['room_id'] as String? ?? '';
    final clientMessageId = row['client_message_id'] as String? ?? '';
    final nonce = row['nonce'] as String? ?? '';
    final ciphertext = row['ciphertext'] as String? ?? '';
    final clientCreatedAt = row['client_created_at'] as String? ?? '';
    final signature = row['signature'] as String? ?? '';
    final integrityOk = SecureRoomCrypto.verifyMessage(
      roomKey: roomKey,
      roomId: roomId,
      clientMessageId: clientMessageId,
      nonce: nonce,
      ciphertext: ciphertext,
      createdAt: clientCreatedAt,
      signature: signature,
    );

    String? text;
    if (integrityOk) {
      try {
        text = await SecureRoomCrypto.decryptString(
          EncryptedPayload(
            ciphertext: ciphertext,
            nonce: nonce,
            mac: row['mac'] as String? ?? '',
          ),
          roomKey,
        );
      } catch (e) {
        AppLogger.warn('anonymous rooms: decrypt failed $e');
      }
    }

    return AnonymousRoomMessage(
      id: row['id'] as String? ?? '',
      roomId: roomId,
      senderMemberId: row['sender_member_id'] as String? ?? '',
      kind: row['kind'] as String? ?? 'text',
      clientMessageId: clientMessageId,
      integrityOk: integrityOk && text != null,
      text: text,
      createdAt:
          DateTime.tryParse(row['created_at'] as String? ?? '') ??
          DateTime.now(),
      expiresAt:
          DateTime.tryParse(row['expires_at'] as String? ?? '') ??
          DateTime.now(),
    );
  }

  AnonymousSecureRoomSummary _mapRoom(dynamic raw) {
    final row = Map<String, dynamic>.from(raw as Map);
    return AnonymousSecureRoomSummary(
      id: row['id'] as String? ?? '',
      inviteCode: row['invite_code'] as String? ?? '',
      status: row['status'] as String? ?? 'active',
      messageTtlSeconds: (row['message_ttl_seconds'] as num?)?.toInt() ?? 120,
      maxMembers: ((row['max_members'] as num?)?.toInt().clamp(2, 3) ?? 2)
          .toInt(),
      activeMemberCount:
          (row['active_member_count'] as num?)?.toInt().clamp(1, 3).toInt() ??
          1,
      createdAt:
          DateTime.tryParse(row['created_at'] as String? ?? '') ??
          DateTime.now(),
      expiresAt:
          DateTime.tryParse(row['expires_at'] as String? ?? '') ??
          DateTime.now().toUtc().add(const Duration(hours: 24)),
    );
  }

  AnonymousRoomMember _mapMember(dynamic raw) {
    final row = Map<String, dynamic>.from(raw as Map);
    return AnonymousRoomMember(
      id: row['id'] as String? ?? '',
      role: row['role'] as String? ?? 'member',
      displayName: row['display_name'] as String? ?? 'Guest',
      avatarSeed: row['avatar_seed'] as String? ?? '',
      joinedAt:
          DateTime.tryParse(row['joined_at'] as String? ?? '') ??
          DateTime.now(),
      lastSeenAt: DateTime.tryParse(row['last_seen_at'] as String? ?? ''),
    );
  }

  Future<void> _saveCredentials({
    required String roomId,
    required String roomKey,
    required String memberToken,
    required String displayName,
    required String memberId,
  }) {
    return Future.wait([
      _storage.write(key: _keyName(roomId), value: roomKey),
      _storage.write(key: _tokenName(roomId), value: memberToken),
      _storage.write(key: _displayNameKey(roomId), value: displayName),
      _storage.write(key: _memberIdKey(roomId), value: memberId),
      _storage.write(key: _lastRoomIdKey, value: roomId),
    ]);
  }

  Future<void> _clearLastRoomIfCurrent(String roomId) async {
    final current = await _storage.read(key: _lastRoomIdKey);
    if (current == roomId) {
      await _storage.delete(key: _lastRoomIdKey);
    }
  }

  Future<_AnonymousRoomCredentials> _credentials(String roomId) async {
    final key = await _storage.read(key: _keyName(roomId));
    final token = await _storage.read(key: _tokenName(roomId));
    if (key == null ||
        key.isEmpty ||
        !SecureRoomCrypto.isValidRoomKey(key) ||
        token == null ||
        token.isEmpty) {
      throw Exception('Anonymous room credentials are missing on this device.');
    }
    return _AnonymousRoomCredentials(roomKey: key, memberToken: token);
  }

  void _assertSignedOut() {
    if (accountIsSignedIn) {
      throw Exception('Anonymous rooms are only available before sign in.');
    }
  }

  void _assertLocalSendRate(String roomId) {
    final now = DateTime.now();
    final recent = _localSendTimes.putIfAbsent(roomId, () => <DateTime>[]);
    recent.removeWhere((sentAt) => now.difference(sentAt).inSeconds >= 10);
    if (recent.length >= 8) {
      throw Exception('Slow down a little before sending more messages.');
    }
    recent.add(now);
  }

  String _functionErrorMessage(Map<String, dynamic> data) {
    final message = (data['message'] ?? data['error']).toString();
    final requestId = data['request_id'] as String?;
    if (requestId == null || requestId.isEmpty) return message;
    final shortId = requestId.length <= 8
        ? requestId
        : requestId.substring(0, 8);
    return '$message Ref $shortId.';
  }

  static String _keyName(String roomId) => 'anonymous_room_key_$roomId';
  static String _tokenName(String roomId) => 'anonymous_room_token_$roomId';
  static String _displayNameKey(String roomId) => 'anonymous_room_name_$roomId';
  static String _memberIdKey(String roomId) => 'anonymous_room_member_$roomId';
  static const String _lastRoomIdKey = 'anonymous_room_last_id';
}

class _AnonymousRoomCredentials {
  const _AnonymousRoomCredentials({
    required this.roomKey,
    required this.memberToken,
  });

  final String roomKey;
  final String memberToken;
}
