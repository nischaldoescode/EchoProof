import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../../../core/utils/logger.dart';
import '../../../core/utils/media_file_safety.dart';
import '../../../core/services/device_service.dart';
import 'secure_room_crypto.dart';

class SecureRoomSummary {
  const SecureRoomSummary({
    required this.id,
    required this.inviteCode,
    required this.status,
    required this.messageTtlSeconds,
    required this.createdAt,
    this.creatorId,
    this.maxMembers = 2,
    this.waitForMembers = false,
    this.startedAt,
    this.waitingExpiresAt,
    this.activeMemberCount = 1,
  });

  final String id;
  final String? creatorId;
  final String inviteCode;
  final String status;
  final int messageTtlSeconds;
  final int maxMembers;
  final bool waitForMembers;
  final DateTime createdAt;
  final DateTime? startedAt;
  final DateTime? waitingExpiresAt;
  final int activeMemberCount;

  bool get isActive => status == 'active';
  bool get isWaiting => isActive && waitForMembers && startedAt == null;
  bool get canSendMessages => isActive && !isWaiting;
  String get memberProgressLabel =>
      '${activeMemberCount.clamp(1, maxMembers)}/$maxMembers joined';
}

class SecureRoomMessage {
  const SecureRoomMessage({
    required this.id,
    required this.roomId,
    required this.senderId,
    required this.kind,
    required this.createdAt,
    required this.expiresAt,
    required this.clientMessageId,
    required this.integrityOk,
    required this.senderVerified,
    required this.senderDeviceId,
    this.deliveredCount = 0,
    this.readCount = 0,
    this.audioWaveformLevels = const [],
    this.audioDurationMs,
    this.text,
    this.mediaPath,
    this.mediaNonce,
    this.mediaMac,
  });

  final String id;
  final String roomId;
  final String senderId;
  final String kind;
  final DateTime createdAt;
  final DateTime expiresAt;
  final String clientMessageId;
  final bool integrityOk;
  final bool senderVerified;
  final String senderDeviceId;
  final int deliveredCount;
  final int readCount;
  final List<double> audioWaveformLevels;
  final int? audioDurationMs;
  final String? text;
  final String? mediaPath;
  final String? mediaNonce;
  final String? mediaMac;

  bool get isExpired => expiresAt.isBefore(DateTime.now());
  bool get cryptographicallyVerified => integrityOk && senderVerified;
}

class CreatedSecureRoom {
  const CreatedSecureRoom({
    required this.room,
    required this.roomKey,
    required this.shareLink,
  });

  final SecureRoomSummary room;
  final String roomKey;
  final String shareLink;
}

enum SecureRoomPresenceState { active, background, offline }

class SecureRoomPresence {
  const SecureRoomPresence({
    required this.userId,
    required this.state,
    required this.updatedAt,
    this.displayName,
    this.username,
  });

  final String userId;
  final SecureRoomPresenceState state;
  final DateTime updatedAt;
  final String? displayName;
  final String? username;

  bool get isActive => state == SecureRoomPresenceState.active;
  bool get isBackground => state == SecureRoomPresenceState.background;

  String get label {
    final name =
        (displayName?.trim().isNotEmpty == true ? displayName : username) ??
            'Someone';
    return switch (state) {
      SecureRoomPresenceState.active => '$name is here',
      SecureRoomPresenceState.background => '$name is away',
      SecureRoomPresenceState.offline => '$name is offline',
    };
  }
}

class SecureRoomMember {
  const SecureRoomMember({
    required this.userId,
    required this.joinedAt,
    this.displayName,
    this.username,
    this.avatarUrl,
  });

  final String userId;
  final DateTime joinedAt;
  final String? displayName;
  final String? username;
  final String? avatarUrl;

  String get label {
    final display = displayName?.trim();
    if (display != null && display.isNotEmpty) return display;
    final handle = username?.trim();
    if (handle != null && handle.isNotEmpty) return '@$handle';
    return 'Unknown member';
  }
}

class SecureRoomService extends ChangeNotifier {
  SecureRoomService._();
  static final instance = SecureRoomService._();

  static const int maxRoomTextCharacters = 1000;
  static const int maxRoomTextLines = 20;
  static const int maxRoomVideoBytes = 25 * 1024 * 1024;
  static const int maxRoomVideoSeconds = 60;
  static const _storage = FlutterSecureStorage();
  static const _localCreateTimesKey = 'secure_room_local_creates';
  static const _signingPrivateKey = 'secure_room_ed25519_private_key';
  static const _signingPublicKey = 'secure_room_ed25519_public_key';
  static const _urlRegex =
      r'((https?:\/\/|www\.)[^\s<>"{}|\\^`\[\]]+|[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}\/[^\s]*)';
  static final RegExp _unsafeControlRegex =
      RegExp(r'[\u0000-\u0008\u000B\u000C\u000E-\u001F\u007F]');
  static final RegExp _bidirectionalOverrideRegex =
      RegExp(r'[\u202A-\u202E\u2066-\u2069]');

  final _client = Supabase.instance.client;
  final _deviceService = DeviceService(_storage);
  final _localSendTimes = <String, List<DateTime>>{};
  final _mediaPlaintextCache = <String, Uint8List>{};
  int _mediaPlaintextCacheBytes = 0;
  final _registeredSigningRooms = <String>{};
  final _publicKeyCache = <String, _PublicKeyCacheEntry>{};
  Duration? _serverClockOffset;
  DateTime? _serverClockOffsetFetchedAt;
  DateTime? _lastMessagePurgeAt;

  List<SecureRoomSummary> _rooms = [];
  bool _isLoading = false;
  String? _error;

  List<SecureRoomSummary> get rooms => List.unmodifiable(_rooms);
  bool get isLoading => _isLoading;
  String? get error => _error;
  int get localCreatesRemainingToday {
    final used = _localCreatesToday();
    return (2 - used).clamp(0, 2).toInt();
  }

  Duration get localCreateRetryAfter =>
      Duration(seconds: _localCreateRetrySeconds());

  Future<void> loadRooms() async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return;

    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final rows = await _client
          .from('secure_room_members')
          .select('secure_rooms!inner(id, creator_id, invite_code, status, '
              'message_ttl_seconds, max_members, wait_for_members, '
              'started_at, waiting_expires_at, created_at)')
          .eq('user_id', userId)
          .isFilter('left_at', null)
          .eq('secure_rooms.status', 'active')
          .order('joined_at', ascending: false);

      _rooms = (rows as List)
          .map((row) => _mapRoom((row as Map<String, dynamic>)['secure_rooms']))
          .toList();
    } catch (e) {
      _error = 'Could not load rooms.';
      AppLogger.error('rooms: load failed', e);
    }

    _isLoading = false;
    notifyListeners();
  }

  Future<CreatedSecureRoom> createRoom({
    int ttlSeconds = 120,
    int maxMembers = 2,
    bool waitForMembers = false,
    int waitingTimeoutSeconds = 180,
  }) async {
    final localRetry = _localCreateRetrySeconds();
    if (localRetry > 0) {
      throw Exception(
        'You used today\'s 2 room creates. Try again after local midnight.',
      );
    }

    final roomKey = SecureRoomCrypto.generateRoomKey();
    final response = await _client.functions.invoke(
      'create-secure-room',
      body: {
        'ttl_seconds': ttlSeconds.clamp(120, 300),
        'max_members': maxMembers.clamp(2, 3),
        'wait_for_members': waitForMembers,
        'waiting_timeout_seconds': waitingTimeoutSeconds.clamp(120, 300),
        'timezone_offset_minutes': DateTime.now().timeZoneOffset.inMinutes,
      },
    );

    final data = Map<String, dynamic>.from(response.data as Map);
    if (data['error'] != null) {
      AppLogger.warn(
        'rooms: create failed ${data['error']} '
        'stage=${data['diagnostic_stage'] ?? 'unknown'} '
        'code=${data['diagnostic_code'] ?? 'none'} '
        'ref=${data['request_id'] ?? 'none'}',
      );
      throw Exception(_functionErrorMessage(data));
    }

    final room = _mapRoom(data['room']);
    await _saveRoomKey(room.id, roomKey);
    await _registerSigningKey(room.id);
    await _recordLocalCreate();
    await loadRooms();

    return CreatedSecureRoom(
      room: room,
      roomKey: roomKey,
      shareLink: buildShareLink(room.inviteCode, roomKey),
    );
  }

  Future<SecureRoomSummary> joinRoom({
    required String inviteCode,
    required String roomKey,
  }) async {
    final code = inviteCode.trim().toUpperCase();
    if (!RegExp(r'^[A-Z2-9]{8}$').hasMatch(code)) {
      throw Exception('Enter the 8-character room code.');
    }
    if (!SecureRoomCrypto.isValidRoomKey(roomKey)) {
      throw Exception('This invite key is invalid or incomplete.');
    }

    final response = await _client.functions.invoke(
      'join-secure-room',
      body: {'invite_code': code},
    );
    final data = Map<String, dynamic>.from(response.data as Map);
    if (data['error'] != null) {
      AppLogger.warn(
        'rooms: join failed ${data['error']} '
        'stage=${data['diagnostic_stage'] ?? 'unknown'} '
        'code=${data['diagnostic_code'] ?? 'none'} '
        'ref=${data['request_id'] ?? 'none'}',
      );
      throw Exception(_functionErrorMessage(data));
    }

    final room = _mapRoom(data['room']);
    await _saveRoomKey(room.id, roomKey.trim());
    await _registerSigningKey(room.id);
    await loadRooms();
    return room;
  }

  Future<void> leaveRoom(String roomId) async {
    await _client.functions.invoke(
      'leave-secure-room',
      body: {'room_id': roomId},
    );
    await _storage.delete(key: _keyName(roomId));
    await loadRooms();
  }

  Future<void> forgetRoomKey(String roomId) {
    return _storage.delete(key: _keyName(roomId));
  }

  Future<SecureRoomSummary> updateRoomTimer({
    required String roomId,
    required int ttlSeconds,
  }) async {
    await _client.rpc(
      'update_secure_room_timer',
      params: {
        'p_room_id': roomId,
        'p_ttl_seconds': ttlSeconds.clamp(120, 300),
      },
    );
    final room = await loadRoom(roomId);
    await loadRooms();
    return room;
  }

  Future<SecureRoomSummary> loadRoom(String roomId) async {
    await _client.rpc('refresh_secure_room_state',
        params: {'p_room_id': roomId}).catchError((_) {});
    final row = await _client
        .from('secure_rooms')
        .select('id, creator_id, invite_code, status, message_ttl_seconds, '
            'max_members, wait_for_members, started_at, waiting_expires_at, '
            'created_at')
        .eq('id', roomId)
        .maybeSingle();
    if (row == null) {
      throw Exception('Room is no longer available.');
    }
    final activeMemberCount = await _activeMemberCount(roomId);
    return _mapRoom(row, activeMemberCount: activeMemberCount);
  }

  Future<List<SecureRoomMessage>> loadMessages(String roomId) async {
    final now = DateTime.now();
    if (_lastMessagePurgeAt == null ||
        now.difference(_lastMessagePurgeAt!) > const Duration(seconds: 30)) {
      _lastMessagePurgeAt = now;
      await _client
          .rpc('purge_expired_secure_room_messages')
          .catchError((_) {});
    }
    final roomKey = await requireRoomKey(roomId);
    final rows = await _client
        .from('secure_room_messages')
        .select()
        .eq('room_id', roomId)
        .gt('expires_at', DateTime.now().toUtc().toIso8601String())
        .order('created_at', ascending: true)
        .limit(80);
    final messageRows = List<Map<String, dynamic>>.from(rows as List);
    var publicKeys = await _loadPublicKeys(roomId);
    final missingSigningKey = messageRows.any((row) {
      final senderId = row['sender_id'] as String? ?? '';
      final deviceId = row['sender_device_id'] as String? ?? '';
      return senderId.isNotEmpty &&
          deviceId.isNotEmpty &&
          !publicKeys.containsKey('$senderId:$deviceId');
    });
    if (missingSigningKey) {
      publicKeys = await _loadPublicKeys(roomId, forceRefresh: true);
    }
    final receiptCounts = await _loadReceiptCounts(
      messageRows,
    );
    final messages = <SecureRoomMessage>[];
    for (final row in messageRows) {
      messages.add(
        await _decryptMessage(
          row,
          roomKey,
          publicKeys,
          receiptCounts[row['id'] as String? ?? ''] ?? const _ReceiptCounts(),
        ),
      );
    }
    return messages.where((m) => !m.isExpired).toList();
  }

  Future<SecureRoomMessage?> decryptRealtimeMessage(
    String roomId,
    Map<String, dynamic> row,
  ) async {
    if (row['room_id'] != roomId) return null;
    final expiresAt = DateTime.tryParse(row['expires_at'] as String? ?? '');
    if (expiresAt != null && expiresAt.isBefore(DateTime.now())) return null;

    final roomKey = await requireRoomKey(roomId);
    var publicKeys = await _loadPublicKeys(roomId);
    final senderId = row['sender_id'] as String? ?? '';
    final deviceId = row['sender_device_id'] as String? ?? '';
    if (senderId.isNotEmpty &&
        deviceId.isNotEmpty &&
        !publicKeys.containsKey('$senderId:$deviceId')) {
      publicKeys = await _loadPublicKeys(roomId, forceRefresh: true);
    }

    return _decryptMessage(
      row,
      roomKey,
      publicKeys,
      const _ReceiptCounts(),
    );
  }

  RealtimeChannel subscribeToMessages({
    required String roomId,
    required void Function(
      Map<String, dynamic> row,
      PostgresChangeEvent eventType,
    ) onMessageChanged,
    void Function()? onRoomChanged,
    void Function(Map<String, dynamic> row)? onReceiptChanged,
    void Function()? onPresenceChanged,
  }) {
    return _client
        .channel('secure_room_messages_$roomId')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'secure_room_messages',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'room_id',
            value: roomId,
          ),
          callback: (payload) {
            final eventType = payload.eventType;
            final row = eventType == PostgresChangeEvent.delete
                ? payload.oldRecord
                : payload.newRecord;
            onMessageChanged(Map<String, dynamic>.from(row), eventType);
          },
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'secure_rooms',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'id',
            value: roomId,
          ),
          callback: (_) => onRoomChanged?.call(),
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'secure_room_members',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'room_id',
            value: roomId,
          ),
          callback: (_) => onRoomChanged?.call(),
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'secure_room_message_receipts',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'room_id',
            value: roomId,
          ),
          callback: (payload) => onReceiptChanged?.call(
            Map<String, dynamic>.from(payload.newRecord),
          ),
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'secure_room_presence',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'room_id',
            value: roomId,
          ),
          callback: (_) => onPresenceChanged?.call(),
        )
        .subscribe();
  }

  Future<void> prepareRoomForFastSend(String roomId) async {
    await Future.wait([
      _registerSigningKey(roomId),
      _serverNowUtc(),
      requireRoomKey(roomId),
    ]);
  }

  Future<SecureRoomMessage> sendText({
    required String roomId,
    required String text,
    required int ttlSeconds,
    String? clientMessageId,
  }) async {
    final sanitized = sanitizeRoomText(text);
    final clean = redactLinks(sanitized);
    if (clean.isEmpty) {
      throw Exception('Message is empty.');
    }
    return _sendEncryptedMessage(
      roomId: roomId,
      kind: 'text',
      plainText: clean,
      ttlSeconds: ttlSeconds,
      clientMessageId: clientMessageId,
    );
  }

  Future<SecureRoomMessage> sendMedia({
    required String roomId,
    required String localPath,
    required MediaFileKind kind,
    required int ttlSeconds,
    String? clientMessageId,
  }) async {
    final validation = await MediaFileSafety.validateLocalFile(
      localPath,
      expectedKind: kind,
    );
    if (!validation.isValid) {
      throw Exception(validation.error ?? 'Unsupported media.');
    }

    final messageKind = _messageKindFor(validation);
    if (messageKind == 'video' && validation.sizeBytes > maxRoomVideoBytes) {
      throw Exception('Videos in secure rooms must be under 25 MB.');
    }
    await _assertMediaQuota(roomId: roomId, kind: messageKind);
    _assertLocalSendRate(roomId);

    final roomKey = await requireRoomKey(roomId);
    final bytes = await File(localPath).readAsBytes();
    final encrypted = await SecureRoomCrypto.encryptBytes(
      Uint8List.fromList(bytes),
      roomKey,
    );
    final encryptedBytes = base64Decode(encrypted.ciphertext);
    final userId = _client.auth.currentUser?.id;
    if (userId == null) throw Exception('Sign in again.');

    final ext = switch (messageKind) {
      'gif' => 'gif',
      'image' => 'img',
      'video' => 'vid',
      _ => 'media',
    };
    final path = '$roomId/$userId/${const Uuid().v4()}.$ext.bin';
    await _client.storage.from('room-media').uploadBinary(
          path,
          encryptedBytes,
          fileOptions: const FileOptions(
            contentType: 'application/octet-stream',
            upsert: false,
          ),
        );

    _cachePlaintextMedia(path, bytes);
    return _sendEncryptedMessage(
      roomId: roomId,
      kind: messageKind,
      plainText: switch (messageKind) {
        'gif' => 'Encrypted GIF',
        'image' => 'Encrypted image',
        'video' => 'Encrypted video',
        _ => 'Encrypted media',
      },
      ttlSeconds: ttlSeconds,
      mediaPath: path,
      mediaNonce: encrypted.nonce,
      mediaMac: encrypted.mac,
      countLocalRate: false,
      clientMessageId: clientMessageId,
    );
  }

  Future<SecureRoomMessage> sendAudio({
    required String roomId,
    required String localPath,
    required int durationMs,
    required int ttlSeconds,
    List<double> waveformLevels = const [],
    String? clientMessageId,
  }) async {
    final file = File(localPath);
    if (!await file.exists()) {
      throw Exception('Voice note was not saved.');
    }
    final bytes = await file.readAsBytes();
    if (bytes.isEmpty) {
      throw Exception('Voice note is empty.');
    }
    if (durationMs <= 0 || durationMs > 60000) {
      throw Exception('Voice notes must be 1 minute or shorter.');
    }
    if (bytes.length > 3 * 1024 * 1024) {
      throw Exception('Voice note is too large. Keep it under 60 seconds.');
    }
    _assertLocalSendRate(roomId);

    final roomKey = await requireRoomKey(roomId);
    final encrypted = await SecureRoomCrypto.encryptBytes(
      Uint8List.fromList(bytes),
      roomKey,
    );
    final encryptedBytes = base64Decode(encrypted.ciphertext);
    final userId = _client.auth.currentUser?.id;
    if (userId == null) throw Exception('Sign in again.');

    final path = '$roomId/$userId/${const Uuid().v4()}.aud.bin';
    await _client.storage.from('room-media').uploadBinary(
          path,
          encryptedBytes,
          fileOptions: const FileOptions(
            contentType: 'application/octet-stream',
            upsert: false,
          ),
        );

    final normalizedLevels = waveformLevels
        .where((level) => level.isFinite)
        .take(42)
        .map((level) => level.clamp(0.03, 1.0).toStringAsFixed(2))
        .join(',');

    _cachePlaintextMedia(path, bytes);
    return _sendEncryptedMessage(
      roomId: roomId,
      kind: 'audio',
      plainText: normalizedLevels.isEmpty
          ? 'voice:$durationMs'
          : 'voice:$durationMs:$normalizedLevels',
      ttlSeconds: ttlSeconds,
      mediaPath: path,
      mediaNonce: encrypted.nonce,
      mediaMac: encrypted.mac,
      countLocalRate: false,
      clientMessageId: clientMessageId,
    );
  }

  Future<Uint8List> decryptMedia(SecureRoomMessage message) async {
    if (message.mediaPath == null ||
        message.mediaNonce == null ||
        message.mediaMac == null) {
      throw Exception('Missing media payload.');
    }
    final cached = _mediaPlaintextCache[message.mediaPath!];
    if (cached != null) {
      return Uint8List.fromList(cached);
    }
    final roomKey = await requireRoomKey(message.roomId);
    final encryptedBytes =
        await _client.storage.from('room-media').download(message.mediaPath!);
    final bytes = await SecureRoomCrypto.decryptBytes(
      EncryptedPayload(
        ciphertext: base64Encode(encryptedBytes),
        nonce: message.mediaNonce!,
        mac: message.mediaMac!,
      ),
      roomKey,
    );
    _cachePlaintextMedia(message.mediaPath!, bytes);
    return bytes;
  }

  void _cachePlaintextMedia(String path, List<int> bytes) {
    // Keep just-sent small media in memory so the sender sees it immediately
    // instead of waiting for a storage round trip that may lag behind realtime.
    if (bytes.length > maxRoomVideoBytes) return;
    final existing = _mediaPlaintextCache.remove(path);
    if (existing != null) {
      _mediaPlaintextCacheBytes = (_mediaPlaintextCacheBytes - existing.length)
          .clamp(0, 1 << 31)
          .toInt();
    }
    _mediaPlaintextCache[path] = Uint8List.fromList(bytes);
    _mediaPlaintextCacheBytes += bytes.length;
    const maxCacheBytes = 48 * 1024 * 1024;
    while (_mediaPlaintextCache.length > 12 ||
        _mediaPlaintextCacheBytes > maxCacheBytes) {
      final firstKey = _mediaPlaintextCache.keys.first;
      final removed = _mediaPlaintextCache.remove(firstKey);
      if (removed == null) break;
      _mediaPlaintextCacheBytes = (_mediaPlaintextCacheBytes - removed.length)
          .clamp(0, 1 << 31)
          .toInt();
    }
  }

  Future<List<SecureRoomMember>> loadMembers(String roomId) async {
    try {
      final rows = await _client
          .from('secure_room_members')
          .select(
              'user_id, joined_at, users_public(username, display_name, avatar_url)')
          .eq('room_id', roomId)
          .isFilter('left_at', null)
          .order('joined_at', ascending: true);
      return List<Map<String, dynamic>>.from(rows as List).map((row) {
        final profile = row['users_public'] as Map<String, dynamic>?;
        return SecureRoomMember(
          userId: row['user_id'] as String? ?? '',
          joinedAt: DateTime.tryParse(row['joined_at'] as String? ?? '') ??
              DateTime.now(),
          username: profile?['username'] as String?,
          displayName: profile?['display_name'] as String?,
          avatarUrl: profile?['avatar_url'] as String?,
        );
      }).toList();
    } catch (e) {
      AppLogger.warn('rooms: member load failed $e');
      return const [];
    }
  }

  Future<int> _activeMemberCount(String roomId) async {
    try {
      final rows = await _client
          .from('secure_room_members')
          .select('user_id')
          .eq('room_id', roomId)
          .isFilter('left_at', null)
          .limit(4);
      final count = (rows as List).length;
      return count <= 0 ? 1 : count;
    } catch (e) {
      AppLogger.warn('rooms: active member count failed $e');
      return 1;
    }
  }

  Future<void> deleteMessage(SecureRoomMessage message) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) throw Exception('Sign in again.');
    await _client.rpc(
      'delete_secure_room_message',
      params: {'p_message_id': message.id},
    );
    if (message.mediaPath != null && message.senderId == userId) {
      unawaited(_deleteOwnMediaObject(message.mediaPath!));
      final removed = _mediaPlaintextCache.remove(message.mediaPath);
      if (removed != null) {
        _mediaPlaintextCacheBytes = (_mediaPlaintextCacheBytes - removed.length)
            .clamp(0, 1 << 31)
            .toInt();
      }
    }
  }

  Future<void> _deleteOwnMediaObject(String mediaPath) async {
    try {
      await _client.storage.from('room-media').remove([mediaPath]);
    } catch (_) {
      // The guarded RPC removes the live database row immediately; storage
      // cleanup can be retried by a server-side janitor without blocking UI.
    }
  }

  Future<void> setTyping(String roomId, bool typing) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return;
    if (!typing) {
      await _client
          .from('secure_room_typing')
          .delete()
          .eq('room_id', roomId)
          .eq('user_id', userId);
      return;
    }
    final now = DateTime.now().toUtc();
    await _client.from('secure_room_typing').upsert({
      'room_id': roomId,
      'user_id': userId,
      'updated_at': now.toIso8601String(),
      'expires_at': now.add(const Duration(seconds: 8)).toIso8601String(),
    }, onConflict: 'room_id,user_id');
  }

  Stream<List<Map<String, dynamic>>> typingStream(String roomId) async* {
    while (true) {
      try {
        final userId = _client.auth.currentUser?.id;
        final rows = await _client
            .from('secure_room_typing')
            .select('user_id, users_public(username, display_name)')
            .eq('room_id', roomId)
            .gt('expires_at', DateTime.now().toUtc().toIso8601String());
        final list = List<Map<String, dynamic>>.from(rows as List)
            .where((row) => row['user_id'] != userId)
            .toList();
        yield list;
      } catch (_) {
        yield const [];
      }
      await Future<void>.delayed(const Duration(seconds: 3));
    }
  }

  Future<void> setPresence(
    String roomId,
    SecureRoomPresenceState state,
  ) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return;
    final now = DateTime.now().toUtc();
    await _client.from('secure_room_presence').upsert({
      'room_id': roomId,
      'user_id': userId,
      'state': state.name,
      'updated_at': now.toIso8601String(),
      'expires_at': now
          .add(Duration(
              seconds: state == SecureRoomPresenceState.active ? 20 : 90))
          .toIso8601String(),
    }, onConflict: 'room_id,user_id');
  }

  Stream<List<SecureRoomPresence>> presenceStream(String roomId) async* {
    while (true) {
      yield await loadPresence(roomId);
      await Future<void>.delayed(const Duration(seconds: 5));
    }
  }

  Future<List<SecureRoomPresence>> loadPresence(String roomId) async {
    try {
      final userId = _client.auth.currentUser?.id;
      final rows = await _client
          .from('secure_room_presence')
          .select(
              'user_id, state, updated_at, users_public(username, display_name)')
          .eq('room_id', roomId)
          .gt('expires_at', DateTime.now().toUtc().toIso8601String());
      return List<Map<String, dynamic>>.from(rows as List)
          .where((row) => row['user_id'] != userId)
          .map((row) {
        final profile = row['users_public'] as Map<String, dynamic>?;
        return SecureRoomPresence(
          userId: row['user_id'] as String? ?? '',
          state: _presenceState(row['state'] as String?),
          updatedAt: DateTime.tryParse(row['updated_at'] as String? ?? '') ??
              DateTime.now(),
          username: profile?['username'] as String?,
          displayName: profile?['display_name'] as String?,
        );
      }).toList();
    } catch (e) {
      AppLogger.warn('rooms: presence load failed $e');
      return const [];
    }
  }

  Future<void> markMessagesRead({
    required String roomId,
    required List<SecureRoomMessage> messages,
  }) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return;
    final now = DateTime.now().toUtc().toIso8601String();
    final rows = messages
        .where((m) => m.senderId != userId && !m.isExpired)
        .map((m) => {
              'room_id': roomId,
              'message_id': m.id,
              'user_id': userId,
              'delivered_at': now,
              'read_at': now,
              'updated_at': now,
            })
        .toList();
    if (rows.isEmpty) return;
    await _client.from('secure_room_message_receipts').upsert(
          rows,
          onConflict: 'message_id,user_id',
        );
  }

  Future<String> requireRoomKey(String roomId) async {
    final key = await _storage.read(key: _keyName(roomId));
    if (key == null || key.isEmpty) {
      throw Exception(
          'Secret key missing. This device cannot decrypt the room.');
    }
    return key;
  }

  String _messageKindFor(MediaFileValidationResult validation) {
    if (validation.kind == MediaFileKind.video) return 'video';
    if (validation.extension.toLowerCase() == 'gif') return 'gif';
    return 'image';
  }

  Future<void> _assertMediaQuota({
    required String roomId,
    required String kind,
  }) async {
    if (kind != 'image' && kind != 'video' && kind != 'gif') return;
    final userId = _client.auth.currentUser?.id;
    if (userId == null) throw Exception('Sign in again.');

    final rows = await _client
        .from('secure_room_messages')
        .select('id')
        .eq('room_id', roomId)
        .eq('sender_id', userId)
        .eq('kind', kind)
        .gt('expires_at', DateTime.now().toUtc().toIso8601String())
        .limit(2);
    if ((rows as List).length >= 2) {
      final label = switch (kind) {
        'gif' => 'GIFs',
        'image' => 'photos',
        'video' => 'videos',
        _ => 'media files',
      };
      throw Exception(
        'You can send only 2 $label in one active secure room window.',
      );
    }
  }

  Future<SecureRoomMessage> _sendEncryptedMessage({
    required String roomId,
    required String kind,
    required String plainText,
    required int ttlSeconds,
    String? mediaPath,
    String? mediaNonce,
    String? mediaMac,
    bool countLocalRate = true,
    String? clientMessageId,
  }) async {
    if (countLocalRate) {
      _assertLocalSendRate(roomId);
    }
    final userId = _client.auth.currentUser?.id;
    if (userId == null) throw Exception('Sign in again.');
    await _registerSigningKey(roomId);
    final deviceId = await _deviceService.getDeviceId();
    final signingKey = await _ensureSigningKeyPair();
    final roomKey = await requireRoomKey(roomId);
    final now = await _serverNowUtc();
    final clientCreatedAt = now.toIso8601String();
    final ttl = ttlSeconds.clamp(120, 300).toInt();
    final encrypted = await SecureRoomCrypto.encryptString(plainText, roomKey);
    final effectiveClientMessageId =
        clientMessageId ?? SecureRoomCrypto.generateClientMessageId();
    final signature = SecureRoomCrypto.signMessage(
      roomKey: roomKey,
      roomId: roomId,
      clientMessageId: effectiveClientMessageId,
      nonce: encrypted.nonce,
      ciphertext: encrypted.ciphertext,
      createdAt: clientCreatedAt,
    );
    final senderSignature = await SecureRoomCrypto.signDeviceMessage(
      privateKey: signingKey.privateKey,
      publicKey: signingKey.publicKey,
      roomId: roomId,
      senderId: userId,
      senderDeviceId: deviceId,
      clientMessageId: effectiveClientMessageId,
      kind: kind,
      nonce: encrypted.nonce,
      ciphertext: encrypted.ciphertext,
      createdAt: clientCreatedAt,
    );

    final inserted = await _client
        .from('secure_room_messages')
        .insert({
          'room_id': roomId,
          'sender_id': userId,
          'sender_device_id': deviceId,
          'kind': kind,
          'ciphertext': encrypted.ciphertext,
          'nonce': encrypted.nonce,
          'mac': encrypted.mac,
          'signature': signature,
          'sender_signature': senderSignature,
          'media_path': mediaPath,
          'media_nonce': mediaNonce,
          'media_mac': mediaMac,
          'client_message_id': effectiveClientMessageId,
          'client_created_at': clientCreatedAt,
          'created_at': clientCreatedAt,
          'expires_at': now.add(Duration(seconds: ttl)).toIso8601String(),
        })
        .select()
        .single();

    final ownPublicKeys = <String, String>{
      '$userId:$deviceId': signingKey.publicKey,
    };
    final cached = _publicKeyCache[roomId];
    if (cached != null) {
      ownPublicKeys.addAll(cached.keys);
    }
    return _decryptMessage(
      Map<String, dynamic>.from(inserted as Map),
      roomKey,
      ownPublicKeys,
      const _ReceiptCounts(),
    );
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

  Future<Map<String, String>> _loadPublicKeys(
    String roomId, {
    bool forceRefresh = false,
  }) async {
    final cached = _publicKeyCache[roomId];
    if (!forceRefresh &&
        cached != null &&
        DateTime.now().difference(cached.fetchedAt) <
            const Duration(minutes: 2)) {
      return cached.keys;
    }
    try {
      final rows = await _client
          .from('secure_room_member_keys')
          .select('user_id, device_id, public_key')
          .eq('room_id', roomId);
      final keys = <String, String>{};
      for (final raw in rows as List) {
        final row = Map<String, dynamic>.from(raw as Map);
        final userId = row['user_id'] as String? ?? '';
        final deviceId = row['device_id'] as String? ?? '';
        final publicKey = row['public_key'] as String? ?? '';
        if (userId.isNotEmpty && deviceId.isNotEmpty && publicKey.isNotEmpty) {
          keys['$userId:$deviceId'] = publicKey;
        }
      }
      _publicKeyCache[roomId] = _PublicKeyCacheEntry(
        keys: keys,
        fetchedAt: DateTime.now(),
      );
      return keys;
    } catch (e) {
      AppLogger.warn('rooms: public key load failed $e');
      return const {};
    }
  }

  Future<Map<String, _ReceiptCounts>> _loadReceiptCounts(
    List<Map<String, dynamic>> messageRows,
  ) async {
    if (messageRows.isEmpty) return const {};
    final ids = messageRows
        .map((row) => row['id'] as String?)
        .whereType<String>()
        .toList();
    if (ids.isEmpty) return const {};

    try {
      final senderByMessage = {
        for (final row in messageRows)
          if (row['id'] is String)
            row['id'] as String: row['sender_id'] as String?
      };
      final rows = await _client
          .from('secure_room_message_receipts')
          .select('message_id, user_id, delivered_at, read_at')
          .filter('message_id', 'in', '(${ids.join(',')})');
      final counts = <String, _ReceiptCounts>{};
      for (final raw in rows as List) {
        final row = Map<String, dynamic>.from(raw as Map);
        final messageId = row['message_id'] as String? ?? '';
        final userId = row['user_id'] as String? ?? '';
        if (messageId.isEmpty || userId.isEmpty) continue;
        if (senderByMessage[messageId] == userId) continue;

        final current = counts[messageId] ?? const _ReceiptCounts();
        counts[messageId] = _ReceiptCounts(
          deliveredCount:
              current.deliveredCount + (row['delivered_at'] == null ? 0 : 1),
          readCount: current.readCount + (row['read_at'] == null ? 0 : 1),
        );
      }
      return counts;
    } catch (e) {
      AppLogger.warn('rooms: receipt load failed $e');
      return const {};
    }
  }

  Future<void> _registerSigningKey(String roomId) async {
    if (_registeredSigningRooms.contains(roomId)) return;
    final userId = _client.auth.currentUser?.id;
    if (userId == null) throw Exception('Sign in again.');
    final deviceId = await _deviceService.getDeviceId();
    final key = await _ensureSigningKeyPair();
    await _client.from('secure_room_member_keys').upsert({
      'room_id': roomId,
      'user_id': userId,
      'device_id': deviceId,
      'public_key': key.publicKey,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }, onConflict: 'room_id,user_id,device_id');
    _registeredSigningRooms.add(roomId);
    final cached = _publicKeyCache[roomId]?.keys ?? const <String, String>{};
    _publicKeyCache[roomId] = _PublicKeyCacheEntry(
      keys: {...cached, '$userId:$deviceId': key.publicKey},
      fetchedAt: DateTime.now(),
    );
  }

  Future<({String privateKey, String publicKey})>
      _ensureSigningKeyPair() async {
    final privateKey = await _storage.read(key: _signingPrivateKey);
    final publicKey = await _storage.read(key: _signingPublicKey);
    if (privateKey != null &&
        privateKey.isNotEmpty &&
        publicKey != null &&
        publicKey.isNotEmpty) {
      return (privateKey: privateKey, publicKey: publicKey);
    }

    final generated = await SecureRoomCrypto.generateSigningKeyPair();
    await _storage.write(key: _signingPrivateKey, value: generated.privateKey);
    await _storage.write(key: _signingPublicKey, value: generated.publicKey);
    return generated;
  }

  Future<DateTime> _serverNowUtc() async {
    final now = DateTime.now().toUtc();
    final cachedAt = _serverClockOffsetFetchedAt;
    final offset = _serverClockOffset;
    if (cachedAt != null &&
        offset != null &&
        now.difference(cachedAt) < const Duration(minutes: 5)) {
      return now.add(offset);
    }
    try {
      final response = await _client.rpc('secure_room_server_now');
      if (response is String) {
        final serverNow = DateTime.parse(response).toUtc();
        _serverClockOffset = serverNow.difference(now);
        _serverClockOffsetFetchedAt = now;
        return serverNow;
      }
      if (response is Map && response['now'] is String) {
        final serverNow = DateTime.parse(response['now'] as String).toUtc();
        _serverClockOffset = serverNow.difference(now);
        _serverClockOffsetFetchedAt = now;
        return serverNow;
      }
    } catch (e) {
      AppLogger.warn('rooms: server time unavailable, using local clock $e');
    }
    return now;
  }

  Future<String> roomFingerprint(String roomId) async {
    final key = await requireRoomKey(roomId);
    return SecureRoomCrypto.fingerprint(key);
  }

  Future<String> deviceSigningFingerprint() async {
    final key = await _ensureSigningKeyPair();
    return SecureRoomCrypto.fingerprint(key.publicKey);
  }

  Future<SecureRoomMessage> _decryptMessage(
    Map<String, dynamic> row,
    String roomKey,
    Map<String, String> publicKeys,
    _ReceiptCounts receiptCounts,
  ) async {
    final createdAt =
        DateTime.tryParse(row['created_at'] as String? ?? '') ?? DateTime.now();
    final clientMessageId = row['client_message_id'] as String? ?? '';
    final clientCreatedAt = row['client_created_at'] as String? ??
        createdAt.toUtc().toIso8601String();
    final ciphertext = row['ciphertext'] as String? ?? '';
    final nonce = row['nonce'] as String? ?? '';
    final signature = row['signature'] as String? ?? '';
    final senderDeviceId = row['sender_device_id'] as String? ?? '';
    final senderSignature = row['sender_signature'] as String? ?? '';
    final roomId = row['room_id'] as String? ?? '';
    final senderId = row['sender_id'] as String? ?? '';
    final kind = row['kind'] as String? ?? 'text';
    final integrityOk = SecureRoomCrypto.verifyMessage(
      roomKey: roomKey,
      roomId: roomId,
      clientMessageId: clientMessageId,
      nonce: nonce,
      ciphertext: ciphertext,
      createdAt: clientCreatedAt,
      signature: signature,
    );
    final publicKey = publicKeys['$senderId:$senderDeviceId'];
    final senderVerified = publicKey == null || senderSignature.isEmpty
        ? false
        : await SecureRoomCrypto.verifyDeviceMessage(
            publicKey: publicKey,
            signature: senderSignature,
            roomId: roomId,
            senderId: senderId,
            senderDeviceId: senderDeviceId,
            clientMessageId: clientMessageId,
            kind: kind,
            nonce: nonce,
            ciphertext: ciphertext,
            createdAt: clientCreatedAt,
          );

    String text;
    try {
      text = await SecureRoomCrypto.decryptString(
        EncryptedPayload(
          ciphertext: ciphertext,
          nonce: nonce,
          mac: row['mac'] as String? ?? '',
        ),
        roomKey,
      );
    } catch (_) {
      text = 'Message integrity compromised';
    }
    int? audioDurationMs;
    var audioWaveformLevels = const <double>[];
    if (kind == 'audio' && text.startsWith('voice:')) {
      final parts = text.split(':');
      if (parts.length >= 2) {
        audioDurationMs = int.tryParse(parts[1]);
      }
      if (parts.length >= 3) {
        audioWaveformLevels = parts[2]
            .split(',')
            .map(double.tryParse)
            .whereType<double>()
            .where((level) => level.isFinite)
            .map((level) => level.clamp(0.03, 1.0).toDouble())
            .toList(growable: false);
      }
    }

    return SecureRoomMessage(
      id: row['id'] as String,
      roomId: roomId,
      senderId: senderId,
      senderDeviceId: senderDeviceId,
      senderVerified: senderVerified,
      deliveredCount: receiptCounts.deliveredCount,
      readCount: receiptCounts.readCount,
      audioDurationMs: audioDurationMs,
      audioWaveformLevels: audioWaveformLevels,
      kind: kind,
      createdAt: createdAt,
      expiresAt: DateTime.tryParse(row['expires_at'] as String? ?? '') ??
          DateTime.now(),
      clientMessageId: clientMessageId,
      integrityOk: integrityOk,
      text: text,
      mediaPath: row['media_path'] as String?,
      mediaNonce: row['media_nonce'] as String?,
      mediaMac: row['media_mac'] as String?,
    );
  }

  SecureRoomPresenceState _presenceState(String? value) {
    return switch (value) {
      'active' => SecureRoomPresenceState.active,
      'background' => SecureRoomPresenceState.background,
      _ => SecureRoomPresenceState.offline,
    };
  }

  static String redactLinks(String text) {
    return text.replaceAll(
        RegExp(_urlRegex, caseSensitive: false), '[redacted]');
  }

  static String sanitizeRoomText(String text) {
    final normalizedNewlines = text
        .replaceAll('\r\n', '\n')
        .replaceAll('\r', '\n')
        .replaceAll(_unsafeControlRegex, '')
        .replaceAll(_bidirectionalOverrideRegex, '');
    final cappedLines =
        normalizedNewlines.split('\n').take(maxRoomTextLines).join('\n').trim();
    if (cappedLines.isEmpty) return '';
    final runes = cappedLines.runes.toList(growable: false);
    if (runes.length <= maxRoomTextCharacters) return cappedLines;
    return String.fromCharCodes(runes.take(maxRoomTextCharacters)).trim();
  }

  String _functionErrorMessage(Map<String, dynamic> data) {
    final message = (data['message'] ?? data['error']).toString();
    final requestId = data['request_id'] as String?;
    if (requestId == null || requestId.isEmpty) return message;
    final shortId =
        requestId.length <= 8 ? requestId : requestId.substring(0, 8);
    return '$message Ref $shortId.';
  }

  static String buildShareLink(String inviteCode, String roomKey) {
    final code = Uri.encodeComponent(inviteCode);
    final key = Uri.encodeComponent(roomKey);
    return 'https://join.echoproof.online/room?code=$code#key=$key';
  }

  SecureRoomSummary _mapRoom(dynamic raw, {int? activeMemberCount}) {
    final row = Map<String, dynamic>.from(raw as Map);
    final relationCount = row['secure_room_members'];
    int resolvedActiveMemberCount =
        activeMemberCount ?? (row['active_member_count'] as num?)?.toInt() ?? 1;
    if (relationCount is List && relationCount.isNotEmpty) {
      final count = (relationCount.first as Map?)?['count'];
      if (count is num) resolvedActiveMemberCount = count.toInt();
    }
    return SecureRoomSummary(
      id: row['id'] as String,
      creatorId: row['creator_id'] as String?,
      inviteCode: row['invite_code'] as String? ?? '',
      status: row['status'] as String? ?? 'active',
      messageTtlSeconds: (row['message_ttl_seconds'] as num?)?.toInt() ?? 120,
      maxMembers:
          ((row['max_members'] as num?)?.toInt().clamp(2, 3) ?? 2).toInt(),
      waitForMembers: row['wait_for_members'] as bool? ?? false,
      startedAt: DateTime.tryParse(row['started_at'] as String? ?? ''),
      waitingExpiresAt:
          DateTime.tryParse(row['waiting_expires_at'] as String? ?? ''),
      activeMemberCount: resolvedActiveMemberCount,
      createdAt: DateTime.tryParse(row['created_at'] as String? ?? '') ??
          DateTime.now(),
    );
  }

  Future<void> _saveRoomKey(String roomId, String key) {
    return _storage.write(key: _keyName(roomId), value: key);
  }

  String _keyName(String roomId) => 'secure_room_key_$roomId';

  Future<void> _recordLocalCreate() async {
    final box = Hive.box('app_settings');
    final times = List<String>.from(
      (box.get(_localCreateTimesKey) as List?) ?? const [],
    )..add(DateTime.now().toIso8601String());
    await box.put(_localCreateTimesKey, times);
  }

  int _localCreateRetrySeconds() {
    final today = _localCreatesToday();
    if (today < 2) return 0;
    final now = DateTime.now();
    final tomorrow = DateTime(now.year, now.month, now.day + 1);
    return tomorrow.difference(now).inSeconds.clamp(1, 86400).toInt();
  }

  int _localCreatesToday() {
    final box = Hive.box('app_settings');
    final times = List<String>.from(
      (box.get(_localCreateTimesKey) as List?) ?? const [],
    );
    final now = DateTime.now();
    return times
        .map(DateTime.tryParse)
        .whereType<DateTime>()
        .where((t) =>
            t.year == now.year && t.month == now.month && t.day == now.day)
        .length;
  }
}

class _ReceiptCounts {
  const _ReceiptCounts({
    this.deliveredCount = 0,
    this.readCount = 0,
  });

  final int deliveredCount;
  final int readCount;
}

class _PublicKeyCacheEntry {
  const _PublicKeyCacheEntry({
    required this.keys,
    required this.fetchedAt,
  });

  final Map<String, String> keys;
  final DateTime fetchedAt;
}
