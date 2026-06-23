import 'dart:async';

import 'package:hive_flutter/hive_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../utils/logger.dart';
import 'connectivity_service.dart';

enum _OutboxKind { createReply, setReplyLike, setBookmark }

class OfflineReplySubmission {
  const OfflineReplySubmission({
    required this.clientMutationId,
    required this.queued,
  });

  final String clientMutationId;
  final bool queued;
}

/// persists idempotent user actions and replays them after connectivity returns.
class OfflineMutationOutbox {
  OfflineMutationOutbox._();

  static final OfflineMutationOutbox instance = OfflineMutationOutbox._();

  StreamSubscription<bool>? _connectivitySubscription;
  bool _initialized = false;
  bool _flushing = false;

  Box get _box => Hive.box('offline_outbox');

  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;
    _connectivitySubscription = ConnectivityService
        .instance
        .onConnectivityChanged
        .listen((online) {
          if (online) unawaited(flush());
        });
    if (ConnectivityService.instance.isOnline) unawaited(flush());
  }

  Future<OfflineReplySubmission> submitReply({
    required String echoId,
    required String content,
    String? parentReplyId,
    String? quotedEchoId,
    String? evidenceUrl,
  }) async {
    final userId = _requireUserId();
    final mutationId = const Uuid().v4();
    final key = 'reply:$userId:$mutationId';
    final record = _OutboxRecord(
      key: key,
      userId: userId,
      kind: _OutboxKind.createReply,
      createdAt: DateTime.now().toUtc(),
      payload: {
        'echo_id': echoId,
        'content': content,
        'parent_reply_id': parentReplyId,
        'quoted_echo_id': quotedEchoId,
        'evidence_url': evidenceUrl,
        'client_mutation_id': mutationId,
      },
    );
    await _save(record);

    if (!ConnectivityService.instance.isOnline) {
      return OfflineReplySubmission(clientMutationId: mutationId, queued: true);
    }

    try {
      await _deliver(record);
      await _box.delete(key);
      return OfflineReplySubmission(
        clientMutationId: mutationId,
        queued: false,
      );
    } on _OutboxDeliveryException catch (error) {
      if (!error.isTransient) {
        await _box.delete(key);
        rethrow;
      }
      await _markRetry(record, error.message);
      return OfflineReplySubmission(clientMutationId: mutationId, queued: true);
    } catch (error) {
      await _markRetry(record, error.toString());
      return OfflineReplySubmission(clientMutationId: mutationId, queued: true);
    }
  }

  Future<void> setReplyLike({required String replyId, required bool liked}) {
    return _saveDesiredState(
      kind: _OutboxKind.setReplyLike,
      keySuffix: replyId,
      payload: {'reply_id': replyId, 'liked': liked},
    );
  }

  Future<void> setBookmark({required String echoId, required bool saved}) {
    return _saveDesiredState(
      kind: _OutboxKind.setBookmark,
      keySuffix: echoId,
      payload: {'echo_id': echoId, 'saved': saved},
    );
  }

  Future<void> _saveDesiredState({
    required _OutboxKind kind,
    required String keySuffix,
    required Map<String, dynamic> payload,
  }) async {
    final userId = _requireUserId();
    final key = '${kind.name}:$userId:$keySuffix';
    final record = _OutboxRecord(
      key: key,
      userId: userId,
      kind: kind,
      createdAt: DateTime.now().toUtc(),
      payload: payload,
    );
    await _save(record);
    if (ConnectivityService.instance.isOnline) unawaited(flush());
  }

  Future<void> flush() async {
    if (_flushing || !ConnectivityService.instance.isOnline) return;
    final currentUserId = Supabase.instance.client.auth.currentUser?.id;
    if (currentUserId == null) return;

    _flushing = true;
    try {
      final records = _records()
        ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
      for (final record in records) {
        if (record.userId != currentUserId) continue;
        try {
          await _deliver(record);
          await _box.delete(record.key);
        } on _OutboxDeliveryException catch (error) {
          if (error.isTransient) {
            await _markRetry(record, error.message);
            break;
          }
          await _box.delete(record.key);
          AppLogger.warn(
            'outbox: discarded ${record.kind.name} ${error.message}',
          );
        } catch (error) {
          await _markRetry(record, error.toString());
          break;
        }
      }
    } finally {
      _flushing = false;
    }
  }

  Future<void> _deliver(_OutboxRecord record) async {
    final client = Supabase.instance.client;
    switch (record.kind) {
      case _OutboxKind.createReply:
        final result = await client.functions.invoke(
          'create-echo-reply',
          body: record.payload,
        );
        if (result.status != 200) {
          final data = result.data;
          final message = data is Map<String, dynamic>
              ? data['error'] as String? ?? 'reply could not be posted'
              : 'reply could not be posted';
          throw _OutboxDeliveryException(result.status, message);
        }
      case _OutboxKind.setReplyLike:
        await client.rpc(
          'set_echo_reply_like',
          params: {
            'p_reply_id': record.payload['reply_id'],
            'p_liked': record.payload['liked'],
          },
        );
      case _OutboxKind.setBookmark:
        final echoId = record.payload['echo_id'];
        final saved = record.payload['saved'] == true;
        if (saved) {
          await client.from('echo_bookmarks').upsert({
            'user_id': record.userId,
            'echo_id': echoId,
          }, onConflict: 'user_id,echo_id');
        } else {
          await client
              .from('echo_bookmarks')
              .delete()
              .eq('user_id', record.userId)
              .eq('echo_id', echoId);
        }
    }
  }

  Future<void> _save(_OutboxRecord record) {
    return _box.put(record.key, record.toMap());
  }

  Future<void> _markRetry(_OutboxRecord record, String error) {
    return _save(
      record.copyWith(
        attempts: record.attempts + 1,
        lastError: error.length > 160 ? error.substring(0, 160) : error,
      ),
    );
  }

  List<_OutboxRecord> _records() {
    return _box.values
        .whereType<Map>()
        .map(
          (value) => _OutboxRecord.fromMap(Map<dynamic, dynamic>.from(value)),
        )
        .whereType<_OutboxRecord>()
        .toList();
  }

  String _requireUserId() {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) throw StateError('not authenticated');
    return userId;
  }

  Future<void> dispose() async {
    await _connectivitySubscription?.cancel();
    _connectivitySubscription = null;
    _initialized = false;
  }
}

class _OutboxRecord {
  const _OutboxRecord({
    required this.key,
    required this.userId,
    required this.kind,
    required this.createdAt,
    required this.payload,
    this.attempts = 0,
    this.lastError,
  });

  final String key;
  final String userId;
  final _OutboxKind kind;
  final DateTime createdAt;
  final Map<String, dynamic> payload;
  final int attempts;
  final String? lastError;

  _OutboxRecord copyWith({int? attempts, String? lastError}) {
    return _OutboxRecord(
      key: key,
      userId: userId,
      kind: kind,
      createdAt: createdAt,
      payload: payload,
      attempts: attempts ?? this.attempts,
      lastError: lastError ?? this.lastError,
    );
  }

  Map<String, dynamic> toMap() => {
    'key': key,
    'user_id': userId,
    'kind': kind.name,
    'created_at': createdAt.toIso8601String(),
    'payload': payload,
    'attempts': attempts,
    'last_error': lastError,
  };

  static _OutboxRecord? fromMap(Map<dynamic, dynamic> map) {
    final key = map['key'] as String?;
    final userId = map['user_id'] as String?;
    final kindName = map['kind'] as String?;
    final createdAt = DateTime.tryParse(map['created_at'] as String? ?? '');
    final payload = map['payload'];
    if (key == null ||
        userId == null ||
        kindName == null ||
        createdAt == null ||
        payload is! Map) {
      return null;
    }
    final kind = _OutboxKind.values.where((value) => value.name == kindName);
    if (kind.isEmpty) return null;
    return _OutboxRecord(
      key: key,
      userId: userId,
      kind: kind.first,
      createdAt: createdAt,
      payload: Map<String, dynamic>.from(payload),
      attempts: (map['attempts'] as num?)?.toInt() ?? 0,
      lastError: map['last_error'] as String?,
    );
  }
}

class _OutboxDeliveryException implements Exception {
  const _OutboxDeliveryException(this.statusCode, this.message);

  final int statusCode;
  final String message;

  bool get isTransient =>
      statusCode >= 500 || statusCode == 408 || statusCode == 429;

  @override
  String toString() => message;
}
