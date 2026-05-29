import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:audio_waveforms/audio_waveforms.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:video_player/video_player.dart';

import '../../../../app/theme/colors.dart';
import '../../../../app/theme/spacing.dart';
import '../../../../app/theme/typography.dart';
import '../../../../core/utils/media_file_safety.dart';
import '../../../../core/utils/snack.dart';
import '../../../../shared/widgets/safe_circle_avatar.dart';
import '../../data/secure_room_service.dart';

double _mediaPreviewWidth(BuildContext context) {
  final screenWidth = MediaQuery.sizeOf(context).width;
  final ratio = screenWidth < 380 ? 0.52 : 0.58;
  return math.min(300.0, math.max(176.0, screenWidth * ratio));
}

String _formatShortDuration(Duration duration) {
  final seconds = duration.inSeconds.clamp(0, 599).toInt();
  return '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}';
}

const _chatCanvas = Color(0xFFF8F4EE);
const _chatSurface = Color(0xFFFFFEFB);
const _mineBubble = Color(0xFFEAF6EC);
const _otherBubble = Color(0xFFFFFEFC);
const _softInk = Color(0xFF24312C);
const _maxVoiceDuration = Duration(seconds: 60);
const _voiceRecorderSettings = RecorderSettings(
  bitRate: 64000,
  sampleRate: 44100,
);
const _voiceWaveStyle = WaveStyle(
  waveColor: AppColors.fernGreenDark,
  showMiddleLine: false,
  waveThickness: 3,
  spacing: 5,
  scaleFactor: 72,
  showTop: true,
  showBottom: true,
  extendWaveform: true,
  backgroundColor: Colors.transparent,
);
const _voicePlayerWaveStyle = PlayerWaveStyle(
  fixedWaveColor: Color(0xFFCFE5D5),
  liveWaveColor: AppColors.fernGreenDark,
  showSeekLine: false,
  waveThickness: 3,
  spacing: 5,
  scaleFactor: 72,
  backgroundColor: Colors.transparent,
);

class SecureRoomChatScreen extends StatefulWidget {
  const SecureRoomChatScreen({super.key, required this.roomId});

  final String roomId;

  @override
  State<SecureRoomChatScreen> createState() => _SecureRoomChatScreenState();
}

class _SecureRoomChatScreenState extends State<SecureRoomChatScreen>
    with WidgetsBindingObserver {
  final _service = SecureRoomService.instance;
  final _client = Supabase.instance.client;
  final _textCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  final _picker = ImagePicker();
  final _recorderController = RecorderController();
  final _profiles = <String, Map<String, dynamic>>{};

  SecureRoomSummary? _room;
  List<SecureRoomMessage> _messages = const [];
  List<SecureRoomPresence> _presence = const [];
  List<SecureRoomMember> _members = const [];
  RealtimeChannel? _channel;
  StreamSubscription<List<Map<String, dynamic>>>? _typingSub;
  StreamSubscription<List<SecureRoomPresence>>? _presenceSub;
  StreamSubscription<Duration>? _recordingDurationSub;
  Timer? _typingTimer;
  Timer? _expiryTimer;
  Timer? _roomStateTimer;
  Timer? _recordingTimer;
  Timer? _messagePollTimer;
  Timer? _messageRefreshDebounce;
  Timer? _securityBannerTimer;
  bool _loading = true;
  bool _loadingMessages = false;
  bool _queuedMessageRefresh = false;
  bool _recording = false;
  bool _showSecurityBanner = true;
  bool _closingRoom = false;
  String? _error;
  String _closingRoomReason = 'This secure room was destroyed.';
  String? _typingLabel;
  String? _recordingPath;
  String? _voicePreviewPath;
  Duration _voicePreviewDuration = Duration.zero;
  List<double> _voicePreviewLevels = const [];
  int _recordingSeconds = 0;
  int _ttlSeconds = 120;
  bool _voiceLimitStopTriggered = false;
  bool _sendingVoiceNote = false;
  final List<_DeletedMessageGhost> _deletedGhosts = [];
  final List<_PendingRoomMessage> _pendingMessages = [];

  String? get _currentUserId => _client.auth.currentUser?.id;
  bool get _roomAvailable => _room?.isActive ?? false;
  bool get _canSend => _room?.canSendMessages ?? false;
  bool get _canShareInvite {
    final room = _room;
    if (room == null || !room.isActive) return false;
    return room.activeMemberCount < room.maxMembers;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
    _textCtrl.addListener(_onComposerChanged);
    _expiryTimer = Timer.periodic(
      const Duration(seconds: 1),
      (_) => _animateExpiredMessages(),
    );
    _roomStateTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (mounted && !_closingRoom && (_room?.isActive ?? false)) {
        unawaited(_handleRoomChanged());
      }
    });
    _messagePollTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      if (mounted && (_room?.canSendMessages ?? false)) {
        _loadMessagesOnly(scrollToBottom: false, updatePresence: false);
      }
    });
    _securityBannerTimer = Timer(const Duration(seconds: 5), () {
      if (mounted) setState(() => _showSecurityBanner = false);
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _textCtrl.removeListener(_onComposerChanged);
    _textCtrl.dispose();
    _scrollCtrl.dispose();
    _typingTimer?.cancel();
    _expiryTimer?.cancel();
    _roomStateTimer?.cancel();
    _recordingTimer?.cancel();
    _messagePollTimer?.cancel();
    _messageRefreshDebounce?.cancel();
    _securityBannerTimer?.cancel();
    _recordingDurationSub?.cancel();
    _typingSub?.cancel();
    _presenceSub?.cancel();
    if (_channel != null) {
      _client.removeChannel(_channel!);
    }
    _service.setTyping(widget.roomId, false);
    _service.setPresence(widget.roomId, SecureRoomPresenceState.offline);
    final recordingPath = _recordingPath;
    _recorderController.dispose();
    if (recordingPath != null) {
      unawaited(_deleteRecordingFile(recordingPath));
    }
    final previewPath = _voicePreviewPath;
    if (previewPath != null) {
      unawaited(_deleteRecordingFile(previewPath));
    }
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _service.setPresence(widget.roomId, SecureRoomPresenceState.active);
      _loadMessagesOnly(refreshRoom: true, refreshMembers: true);
    } else {
      _service.setTyping(widget.roomId, false);
      _service.setPresence(widget.roomId, SecureRoomPresenceState.background);
      if (_recording) {
        unawaited(_cancelRecording(showSnack: false));
      }
    }
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final room = await _service.loadRoom(widget.roomId);
      final messages = await _service.loadMessages(widget.roomId);
      final members = await _service.loadMembers(widget.roomId);
      await _loadProfiles(messages);
      if (!mounted) return;
      setState(() {
        _room = room;
        _ttlSeconds = room.messageTtlSeconds;
        _messages = messages.where((m) => !m.isExpired).toList();
        _members = members;
        _loading = false;
      });
      _subscribe();
      _startTypingStream();
      _startPresenceStream();
      await _service.setPresence(widget.roomId, SecureRoomPresenceState.active);
      unawaited(_service.prepareRoomForFastSend(widget.roomId));
      unawaited(_markVisibleMessagesRead(messages));
      _scrollToEnd();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = _friendlyError(e);
      });
    }
  }

  Future<void> _loadMessagesOnly({
    bool refreshRoom = false,
    bool refreshMembers = false,
    bool updatePresence = true,
    bool scrollToBottom = true,
  }) async {
    if (!mounted) return;
    if (_loadingMessages) {
      _queuedMessageRefresh = true;
      return;
    }
    _loadingMessages = true;
    try {
      final room = refreshRoom ? await _service.loadRoom(widget.roomId) : _room;
      final messages = await _service.loadMessages(widget.roomId);
      final members =
          refreshMembers ? await _service.loadMembers(widget.roomId) : null;
      await _loadProfiles(messages);
      if (!mounted) return;
      if (room != null && !room.isActive) {
        unawaited(
            _handleRoomDestroyed('A member left. The room was destroyed.'));
        return;
      }
      if (members != null) {
        setState(() => _members = members);
      }
      _replaceMessages(messages, room: room);
      _prefetchRecentMedia(messages);
      if (updatePresence) {
        await _service.setPresence(
          widget.roomId,
          SecureRoomPresenceState.active,
        );
      }
      unawaited(_markVisibleMessagesRead(messages));
      if (scrollToBottom) _scrollToEnd();
    } catch (e) {
      if (mounted) {
        setState(() => _error = _friendlyError(e));
      }
    } finally {
      _loadingMessages = false;
      if (_queuedMessageRefresh && mounted) {
        _queuedMessageRefresh = false;
        unawaited(_loadMessagesOnly(
          refreshRoom: refreshRoom,
          refreshMembers: refreshMembers,
          updatePresence: updatePresence,
          scrollToBottom: scrollToBottom,
        ));
      }
    }
  }

  void _replaceMessages(
    List<SecureRoomMessage> messages, {
    SecureRoomSummary? room,
  }) {
    final visible = messages.where((m) => !m.isExpired).toList();
    final incomingIds = visible.map((m) => m.id).toSet();
    final incomingClientIds = visible.map((m) => m.clientMessageId).toSet();
    final removed = _messages
        .where((m) => !incomingIds.contains(m.id))
        .where((m) => !_deletedGhosts.any((ghost) => ghost.message.id == m.id))
        .toList();

    setState(() {
      if (room != null) _room = room;
      _messages = visible;
      _pendingMessages.removeWhere(
        (pending) =>
            incomingClientIds.contains(pending.message.clientMessageId),
      );
    });

    if (removed.isNotEmpty) {
      _addDeletedGhosts(removed);
    }
  }

  Future<void> _handleRealtimeMessage(
    Map<String, dynamic> row,
    PostgresChangeEvent eventType,
  ) async {
    if (eventType == PostgresChangeEvent.delete) {
      _removeRealtimeMessage(row['id'] as String?);
      return;
    }
    if (row.isEmpty) {
      _scheduleMessageRefresh();
      return;
    }
    try {
      final message = await _service.decryptRealtimeMessage(widget.roomId, row);
      if (!mounted || message == null || message.isExpired) return;
      _mergeRealtimeMessage(message);
      unawaited(_loadProfiles([message]).then((_) {
        if (mounted) setState(() {});
      }).catchError((_) {}));
      _prefetchRecentMedia([message]);
      if (message.senderId != _currentUserId) {
        unawaited(
          _service.markMessagesRead(
            roomId: widget.roomId,
            messages: [message],
          ),
        );
      }
      _scrollToEnd();
    } catch (_) {
      _scheduleMessageRefresh();
    }
  }

  void _mergeRealtimeMessage(SecureRoomMessage message) {
    setState(() {
      _pendingMessages.removeWhere(
        (pending) => pending.message.clientMessageId == message.clientMessageId,
      );
      final index = _messages.indexWhere(
        (current) =>
            current.id == message.id ||
            current.clientMessageId == message.clientMessageId,
      );
      if (index >= 0) {
        _messages = [
          ..._messages.take(index),
          message,
          ..._messages.skip(index + 1),
        ];
      } else {
        _messages = [..._messages, message]
          ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
      }
    });
  }

  void _removeRealtimeMessage(String? messageId) {
    if (messageId == null || messageId.isEmpty || !mounted) return;
    final removed =
        _messages.where((message) => message.id == messageId).toList();
    if (removed.isEmpty) return;
    setState(() {
      _messages =
          _messages.where((message) => message.id != messageId).toList();
    });
    _addDeletedGhosts(removed);
  }

  void _scheduleMessageRefresh() {
    _messageRefreshDebounce?.cancel();
    _messageRefreshDebounce = Timer(const Duration(milliseconds: 350), () {
      if (!mounted) return;
      unawaited(_loadMessagesOnly(scrollToBottom: false));
    });
  }

  Future<void> _handleRoomChanged() async {
    if (!mounted || _closingRoom) return;
    try {
      final room = await _service.loadRoom(widget.roomId);
      final members = await _service.loadMembers(widget.roomId);
      if (!mounted) return;
      if (!room.isActive) {
        await _handleRoomDestroyed('A member left. The room was destroyed.');
        return;
      }
      setState(() {
        _room = room;
        _ttlSeconds = room.messageTtlSeconds;
        _members = members;
      });
    } catch (_) {
      if (mounted) {
        await _handleRoomDestroyed('This secure room is no longer available.');
      }
    }
  }

  Future<void> _handleRoomDestroyed(String reason) async {
    if (!mounted || _closingRoom) return;
    _typingTimer?.cancel();
    unawaited(_service.setTyping(widget.roomId, false));
    unawaited(
        _service.setPresence(widget.roomId, SecureRoomPresenceState.offline));
    unawaited(_service.forgetRoomKey(widget.roomId));
    setState(() {
      _closingRoom = true;
      _closingRoomReason = reason;
      _room = _room == null
          ? null
          : SecureRoomSummary(
              id: _room!.id,
              inviteCode: _room!.inviteCode,
              status: 'destroyed',
              messageTtlSeconds: _room!.messageTtlSeconds,
              createdAt: _room!.createdAt,
              creatorId: _room!.creatorId,
              maxMembers: _room!.maxMembers,
              waitForMembers: _room!.waitForMembers,
              startedAt: _room!.startedAt,
              waitingExpiresAt: _room!.waitingExpiresAt,
              activeMemberCount: _room!.activeMemberCount,
            );
      _messages = const [];
      _pendingMessages.clear();
      _typingLabel = null;
    });
    await Future<void>.delayed(const Duration(milliseconds: 950));
    if (!mounted) return;
    context.go('/rooms');
    showInfoSnack(context, reason);
  }

  void _prefetchRecentMedia(List<SecureRoomMessage> messages) {
    final lightweightMedia = messages
        .where((message) =>
            message.mediaPath != null &&
            (message.kind == 'image' ||
                message.kind == 'gif' ||
                message.kind == 'audio'))
        .toList()
        .reversed
        .take(6);
    for (final message in lightweightMedia) {
      unawaited(_service.decryptMedia(message).then((_) {}).catchError((_) {}));
    }
  }

  void _animateExpiredMessages() {
    if (!mounted || (_messages.isEmpty && _pendingMessages.isEmpty)) return;
    final expired = _messages.where((m) => m.isExpired).toList();
    final expiredPending = _pendingMessages
        .where((pending) => pending.message.isExpired)
        .map((pending) => pending.message)
        .toList();
    if (expired.isEmpty && expiredPending.isEmpty) return;
    setState(() {
      _messages = _messages.where((m) => !m.isExpired).toList();
      _pendingMessages.removeWhere((pending) => pending.message.isExpired);
    });
    _addDeletedGhosts([...expired, ...expiredPending]);
  }

  void _addDeletedGhosts(List<SecureRoomMessage> messages) {
    if (!mounted || messages.isEmpty) return;
    final existingIds = _deletedGhosts.map((ghost) => ghost.message.id).toSet();
    final ghosts = messages
        .where((message) => !existingIds.contains(message.id))
        .map(
          (message) => _DeletedMessageGhost(
            id: '${message.id}-${DateTime.now().microsecondsSinceEpoch}',
            message: message,
          ),
        )
        .toList();
    if (ghosts.isEmpty) return;
    setState(() => _deletedGhosts.addAll(ghosts));
  }

  void _removeDeletedGhost(String ghostId) {
    if (!mounted) return;
    setState(() => _deletedGhosts.removeWhere((ghost) => ghost.id == ghostId));
  }

  List<Object> _timelineItems() {
    final items = <Object>[
      ..._messages,
      ..._pendingMessages,
      ..._deletedGhosts,
    ];
    items.sort((a, b) {
      final aTime = switch (a) {
        SecureRoomMessage message => message.createdAt,
        _PendingRoomMessage pending => pending.message.createdAt,
        _DeletedMessageGhost ghost => ghost.message.createdAt,
        _ => DateTime.now(),
      };
      final bTime = switch (b) {
        SecureRoomMessage message => message.createdAt,
        _PendingRoomMessage pending => pending.message.createdAt,
        _DeletedMessageGhost ghost => ghost.message.createdAt,
        _ => DateTime.now(),
      };
      return aTime.compareTo(bTime);
    });
    return items;
  }

  void _subscribe() {
    if (_channel != null) return;
    _channel = _service.subscribeToMessages(
      roomId: widget.roomId,
      onMessageChanged: (row, eventType) =>
          unawaited(_handleRealtimeMessage(row, eventType)),
      onRoomChanged: () => unawaited(_handleRoomChanged()),
      onReceiptChanged: (_) => _scheduleMessageRefresh(),
      onPresenceChanged: () {},
    );
  }

  void _startTypingStream() {
    _typingSub ??= _service.typingStream(widget.roomId).listen((rows) {
      if (!mounted) return;
      final names = rows
          .map((row) {
            final profile = row['users_public'] as Map<String, dynamic>?;
            return (profile?['display_name'] as String?)?.trim().isNotEmpty ==
                    true
                ? profile!['display_name'] as String
                : profile?['username'] as String?;
          })
          .whereType<String>()
          .toList();
      setState(() {
        _typingLabel = names.isEmpty
            ? null
            : names.length == 1
                ? '${names.first} is typing'
                : '${names.length} people are typing';
      });
    });
  }

  void _startPresenceStream() {
    _presenceSub ??= _service.presenceStream(widget.roomId).listen((presence) {
      if (!mounted) return;
      setState(() => _presence = presence);
    });
  }

  Future<void> _markVisibleMessagesRead(
    List<SecureRoomMessage> messages,
  ) async {
    final room = _room;
    if (room == null || !room.canSendMessages) return;
    await _service.markMessagesRead(roomId: widget.roomId, messages: messages);
  }

  Future<void> _loadProfiles(List<SecureRoomMessage> messages) async {
    final ids = messages.map((m) => m.senderId).where((id) => id.isNotEmpty);
    final missing = ids.toSet().difference(_profiles.keys.toSet());
    if (missing.isEmpty) return;
    final rows = await _client
        .from('users_public')
        .select('id, username, display_name, avatar_url, trust_tier, is_public')
        .filter('id', 'in', '(${missing.join(',')})');
    for (final row in rows as List) {
      final map = Map<String, dynamic>.from(row as Map);
      _profiles[map['id'] as String] = map;
    }
  }

  String _newPendingClientMessageId() {
    return 'local-${DateTime.now().microsecondsSinceEpoch}-${math.Random().nextInt(1 << 32)}';
  }

  SecureRoomMessage _buildPendingMessage({
    required String clientMessageId,
    required String kind,
    required String? text,
    required int ttlSeconds,
    int? audioDurationMs,
    List<double> audioWaveformLevels = const [],
  }) {
    final now = DateTime.now();
    return SecureRoomMessage(
      id: clientMessageId,
      roomId: widget.roomId,
      senderId: _currentUserId ?? '',
      kind: kind,
      createdAt: now,
      expiresAt: now.add(Duration(seconds: ttlSeconds.clamp(120, 300))),
      clientMessageId: clientMessageId,
      integrityOk: true,
      senderVerified: false,
      senderDeviceId: 'local',
      text: text,
      audioDurationMs: audioDurationMs,
      audioWaveformLevels: audioWaveformLevels,
    );
  }

  void _addPendingMessage(_PendingRoomMessage pending) {
    if (!mounted) return;
    setState(() => _pendingMessages.add(pending));
    _scrollToEnd();
  }

  void _removePendingMessage(String clientMessageId) {
    if (!mounted) return;
    setState(() {
      _pendingMessages.removeWhere(
        (pending) => pending.message.clientMessageId == clientMessageId,
      );
    });
  }

  void _completePendingMessage(
    String clientMessageId,
    SecureRoomMessage message,
  ) {
    if (!mounted) return;
    setState(() {
      _pendingMessages.removeWhere(
        (pending) => pending.message.clientMessageId == clientMessageId,
      );
      final existingIndex = _messages.indexWhere(
        (current) =>
            current.id == message.id ||
            current.clientMessageId == message.clientMessageId,
      );
      if (existingIndex >= 0) {
        _messages = [
          ..._messages.take(existingIndex),
          message,
          ..._messages.skip(existingIndex + 1),
        ];
      } else {
        _messages = [..._messages, message]
          ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
      }
    });
    _scrollToEnd();
  }

  void _onComposerChanged() {
    if (!_canSend) return;
    if (_textCtrl.text.trim().isEmpty) {
      _typingTimer?.cancel();
      _service.setTyping(widget.roomId, false);
      return;
    }
    _service.setTyping(widget.roomId, true);
    _typingTimer?.cancel();
    _typingTimer = Timer(const Duration(seconds: 2), () {
      _service.setTyping(widget.roomId, false);
    });
  }

  Future<void> _sendText() async {
    final original = _textCtrl.text;
    final sanitized = SecureRoomService.sanitizeRoomText(original);
    if (sanitized.isEmpty || !_canSend) return;
    final redacted = SecureRoomService.redactLinks(sanitized);
    final clientMessageId = _newPendingClientMessageId();
    final pending = _PendingRoomMessage(
      message: _buildPendingMessage(
        clientMessageId: clientMessageId,
        kind: 'text',
        text: redacted,
        ttlSeconds: _ttlSeconds,
      ),
    );
    _addPendingMessage(pending);
    try {
      _textCtrl.clear();
      _typingTimer?.cancel();
      unawaited(_service.setTyping(widget.roomId, false));
      final sent = await _service.sendText(
        roomId: widget.roomId,
        text: sanitized,
        ttlSeconds: _ttlSeconds,
        clientMessageId: clientMessageId,
      );
      _completePendingMessage(clientMessageId, sent);
      if (redacted != sanitized && mounted) {
        showInfoSnack(context, 'Links are not allowed in secure rooms.');
      }
    } catch (e) {
      if (mounted) {
        _removePendingMessage(clientMessageId);
        _textCtrl.text = sanitized;
        showErrorSnack(context, _friendlyError(e));
      }
    }
  }

  Future<void> _pickMedia(
    MediaFileKind kind, {
    ImageSource source = ImageSource.gallery,
  }) async {
    if (!_canSend) return;
    String? pendingClientMessageId;
    try {
      final picked = kind == MediaFileKind.image
          ? await _picker.pickImage(
              source: source,
              maxWidth: 1600,
              maxHeight: 1600,
              imageQuality: 85,
            )
          : await _picker.pickVideo(
              source: source,
              maxDuration: const Duration(seconds: 60),
            );
      if (picked == null) return;
      final validation = await MediaFileSafety.validateLocalFile(
        picked.path,
        expectedKind: kind,
      );
      if (!validation.isValid) {
        if (mounted) {
          showErrorSnack(
            context,
            validation.error ?? 'Unsupported media.',
          );
        }
        return;
      }
      int? durationMs;
      if (kind == MediaFileKind.video) {
        if (validation.sizeBytes > SecureRoomService.maxRoomVideoBytes) {
          if (mounted) {
            showErrorSnack(
              context,
              'Videos in secure rooms must be under 25 MB. This one is ${_formatBytes(validation.sizeBytes)}.',
            );
          }
          return;
        }
        durationMs = await _probeVideoDurationMs(picked.path);
        if (durationMs == null || durationMs <= 0) {
          if (mounted) {
            showErrorSnack(
                context, 'Could not read that video. Try another one.');
          }
          return;
        }
        if (durationMs >
            SecureRoomService.maxRoomVideoSeconds *
                Duration.millisecondsPerSecond) {
          if (mounted) {
            showErrorSnack(
              context,
              'Videos in secure rooms must be ${SecureRoomService.maxRoomVideoSeconds} seconds or shorter.',
            );
          }
          return;
        }
      }
      final messageKind = kind == MediaFileKind.video
          ? 'video'
          : picked.path.toLowerCase().endsWith('.gif')
              ? 'gif'
              : 'image';
      final clientMessageId = _newPendingClientMessageId();
      pendingClientMessageId = clientMessageId;
      _addPendingMessage(
        _PendingRoomMessage(
          localMediaPath: picked.path,
          label: messageKind == 'video' ? 'uploading video...' : 'uploading...',
          message: _buildPendingMessage(
            clientMessageId: clientMessageId,
            kind: messageKind,
            text: messageKind == 'video'
                ? 'Encrypted video'
                : messageKind == 'gif'
                    ? 'Encrypted GIF'
                    : 'Encrypted image',
            ttlSeconds: _ttlSeconds,
            audioDurationMs: durationMs,
          ),
        ),
      );
      final sent = await _service.sendMedia(
        roomId: widget.roomId,
        localPath: picked.path,
        kind: kind,
        ttlSeconds: _ttlSeconds,
        clientMessageId: clientMessageId,
      );
      _completePendingMessage(clientMessageId, sent);
    } catch (e) {
      if (mounted) {
        if (pendingClientMessageId != null) {
          _removePendingMessage(pendingClientMessageId);
        }
        showErrorSnack(context, _friendlyError(e));
      }
    }
  }

  Future<int?> _probeVideoDurationMs(String path) async {
    VideoPlayerController? controller;
    try {
      controller = VideoPlayerController.file(File(path));
      await controller.initialize();
      final value = controller.value;
      if (value.hasError || value.size.width <= 0 || value.size.height <= 0) {
        return null;
      }
      return value.duration.inMilliseconds;
    } catch (_) {
      return null;
    } finally {
      await controller?.dispose();
    }
  }

  String _formatBytes(int bytes) {
    if (bytes >= 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    if (bytes >= 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    }
    return '$bytes B';
  }

  Future<void> _showMediaMenu() async {
    if (!_canSend) return;
    await showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      backgroundColor: _chatSurface,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) {
        final bottom = MediaQuery.paddingOf(sheetContext).bottom;
        return Padding(
          padding: EdgeInsets.fromLTRB(
            AppSpacing.lg,
            0,
            AppSpacing.lg,
            AppSpacing.lg + bottom,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Attach encrypted media',
                style: AppTypography.textTheme.titleMedium?.copyWith(
                  color: _softInk,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                'Photos, videos, and GIFs are encrypted before upload and expire with the room timer.',
                style: AppTypography.textTheme.bodySmall?.copyWith(
                  color: AppColors.textSecondary,
                  height: 1.35,
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              GridView.count(
                crossAxisCount:
                    MediaQuery.sizeOf(sheetContext).width < 420 ? 2 : 4,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: AppSpacing.sm,
                crossAxisSpacing: AppSpacing.sm,
                childAspectRatio:
                    MediaQuery.sizeOf(sheetContext).width < 420 ? 2.35 : 1.0,
                children: [
                  _MediaMenuAction(
                    icon: Icons.photo_library_outlined,
                    label: 'Photo',
                    onTap: () {
                      Navigator.pop(sheetContext);
                      _pickMedia(MediaFileKind.image);
                    },
                  ),
                  _MediaMenuAction(
                    icon: Icons.movie_outlined,
                    label: 'Video',
                    onTap: () {
                      Navigator.pop(sheetContext);
                      _pickMedia(MediaFileKind.video);
                    },
                  ),
                  _MediaMenuAction(
                    icon: Icons.photo_camera_outlined,
                    label: 'Camera',
                    onTap: () {
                      Navigator.pop(sheetContext);
                      _pickMedia(
                        MediaFileKind.image,
                        source: ImageSource.camera,
                      );
                    },
                  ),
                  _MediaMenuAction(
                    icon: Icons.videocam_outlined,
                    label: 'Record',
                    onTap: () {
                      Navigator.pop(sheetContext);
                      _pickMedia(
                        MediaFileKind.video,
                        source: ImageSource.camera,
                      );
                    },
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _startRecording() async {
    if (!_canSend || _recording || _voicePreviewPath != null) return;
    try {
      final allowed = await _recorderController.checkPermission();
      if (!allowed) {
        if (mounted) {
          showErrorSnack(context, 'Microphone permission is needed.');
        }
        return;
      }
      final dir = await getTemporaryDirectory();
      final path =
          '${dir.path}/secure_room_voice_${DateTime.now().microsecondsSinceEpoch}.m4a';
      _recorderController.reset();
      await _recorderController.record(
        path: path,
        recorderSettings: _voiceRecorderSettings,
      );
      if (!mounted) return;
      setState(() {
        _recording = true;
        _recordingPath = path;
        _recordingSeconds = 0;
        _voiceLimitStopTriggered = false;
      });
      await _recordingDurationSub?.cancel();
      _recordingDurationSub =
          _recorderController.onCurrentDuration.listen((duration) {
        if (!mounted || !_recording) return;
        final seconds = duration.inSeconds.clamp(0, 60).toInt();
        if (seconds != _recordingSeconds) {
          setState(() => _recordingSeconds = seconds);
        }
        if (duration >= _maxVoiceDuration && !_voiceLimitStopTriggered) {
          _voiceLimitStopTriggered = true;
          unawaited(_finishRecording(autoStopped: true));
        }
      });
      _recordingTimer?.cancel();
      _recordingTimer = Timer(_maxVoiceDuration, () {
        if (mounted && _recording && !_voiceLimitStopTriggered) {
          _voiceLimitStopTriggered = true;
          unawaited(_finishRecording(autoStopped: true));
        }
      });
    } catch (e) {
      if (mounted) showErrorSnack(context, _friendlyError(e));
    }
  }

  Future<void> _finishRecording({bool autoStopped = false}) async {
    if (!_recording) return;
    _recordingTimer?.cancel();
    await _recordingDurationSub?.cancel();
    _recordingDurationSub = null;
    final elapsedBeforeStop = _recorderController.elapsedDuration;
    final levels = List<double>.from(_recorderController.waveData);
    String? path;
    try {
      path = await _recorderController.stop(false);
    } catch (_) {
      path = _recordingPath;
    }
    if (!mounted) return;
    final recordedDuration =
        _recorderController.recordedDuration > Duration.zero
            ? _recorderController.recordedDuration
            : elapsedBeforeStop > Duration.zero
                ? elapsedBeforeStop
                : Duration(seconds: _recordingSeconds);
    final duration = recordedDuration > _maxVoiceDuration
        ? _maxVoiceDuration
        : recordedDuration;
    setState(() {
      _recording = false;
      _recordingPath = null;
      _recordingSeconds = 0;
      _voiceLimitStopTriggered = false;
    });
    _recorderController.reset();

    if (path == null || duration.inMilliseconds < 700) {
      if (path != null) {
        unawaited(_deleteRecordingFile(path));
      }
      showInfoSnack(context, 'Voice note was too short.');
      return;
    }

    setState(() {
      _voicePreviewPath = path;
      _voicePreviewDuration = duration;
      _voicePreviewLevels = levels
          .where((level) => level.isFinite)
          .take(42)
          .map((level) => level.clamp(0.03, 1.0).toDouble())
          .toList(growable: false);
    });
    if (autoStopped) {
      showInfoSnack(context, 'Voice note reached 1:00. Send or delete it.');
    }
  }

  Future<void> _sendVoicePreview() async {
    final path = _voicePreviewPath;
    if (path == null || _sendingVoiceNote || !_canSend) return;
    final duration = _voicePreviewDuration > _maxVoiceDuration
        ? _maxVoiceDuration
        : _voicePreviewDuration;
    final durationMs = duration.inMilliseconds.clamp(1, 60000).toInt();
    final levels = List<double>.from(_voicePreviewLevels);
    final clientMessageId = _newPendingClientMessageId();
    setState(() {
      _voicePreviewPath = null;
      _voicePreviewDuration = Duration.zero;
      _voicePreviewLevels = const [];
      _sendingVoiceNote = true;
    });
    _addPendingMessage(
      _PendingRoomMessage(
        localMediaPath: path,
        label: 'sending voice...',
        message: _buildPendingMessage(
          clientMessageId: clientMessageId,
          kind: 'audio',
          text: 'voice:$durationMs',
          ttlSeconds: _ttlSeconds,
          audioDurationMs: durationMs,
          audioWaveformLevels: levels,
        ),
      ),
    );
    try {
      final sent = await _service.sendAudio(
        roomId: widget.roomId,
        localPath: path,
        durationMs: durationMs,
        ttlSeconds: _ttlSeconds,
        waveformLevels: levels,
        clientMessageId: clientMessageId,
      );
      _completePendingMessage(clientMessageId, sent);
      unawaited(_deleteRecordingFile(path));
    } catch (e) {
      if (mounted) {
        _removePendingMessage(clientMessageId);
        setState(() {
          _voicePreviewPath = path;
          _voicePreviewDuration = duration;
          _voicePreviewLevels = levels;
        });
        showErrorSnack(context, _friendlyError(e));
      }
    } finally {
      if (mounted) setState(() => _sendingVoiceNote = false);
    }
  }

  Future<void> _cancelRecording({bool showSnack = true}) async {
    if (!_recording) return;
    _recordingTimer?.cancel();
    await _recordingDurationSub?.cancel();
    _recordingDurationSub = null;
    final path = _recordingPath;
    String? stoppedPath;
    try {
      stoppedPath = await _recorderController.stop();
    } catch (_) {}
    if (path != null) {
      unawaited(_deleteRecordingFile(path));
    }
    if (stoppedPath != null && stoppedPath != path) {
      unawaited(_deleteRecordingFile(stoppedPath));
    }
    if (!mounted) return;
    setState(() {
      _recording = false;
      _recordingPath = null;
      _recordingSeconds = 0;
      _voiceLimitStopTriggered = false;
    });
    _recorderController.reset();
    if (showSnack) showInfoSnack(context, 'Voice note discarded.');
  }

  Future<void> _discardVoicePreview({bool showSnack = true}) async {
    final path = _voicePreviewPath;
    if (path == null) return;
    setState(() {
      _voicePreviewPath = null;
      _voicePreviewDuration = Duration.zero;
      _voicePreviewLevels = const [];
    });
    unawaited(_deleteRecordingFile(path));
    if (showSnack) showInfoSnack(context, 'Voice note discarded.');
  }

  Future<void> _deleteRecordingFile(String path) async {
    try {
      await File(path).delete();
    } catch (_) {
      // Best effort cleanup for temporary encrypted-room recordings.
    }
  }

  Future<void> _leaveRoom() async {
    final leave = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Destroy this room?'),
        content: const Text(
          'When one person leaves, the room is destroyed for everyone and live messages are removed.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Leave'),
          ),
        ],
      ),
    );
    if (leave != true) return;
    try {
      await _service.leaveRoom(widget.roomId);
      if (!mounted) return;
      await _handleRoomDestroyed('You left. The room was destroyed.');
    } catch (e) {
      if (mounted) showErrorSnack(context, _friendlyError(e));
    }
  }

  Future<void> _shareInvite() async {
    try {
      final room = _room ?? await _service.loadRoom(widget.roomId);
      if (room.activeMemberCount >= room.maxMembers) {
        if (mounted) showInfoSnack(context, 'This room is already full.');
        return;
      }
      final key = await _service.requireRoomKey(widget.roomId);
      await SharePlus.instance.share(
        ShareParams(
            text: SecureRoomService.buildShareLink(room.inviteCode, key)),
      );
    } catch (e) {
      if (mounted) showErrorSnack(context, _friendlyError(e));
    }
  }

  Future<void> _showKeyInfo() async {
    try {
      final roomFingerprint = await _service.roomFingerprint(widget.roomId);
      final deviceFingerprint = await _service.deviceSigningFingerprint();
      if (!mounted) return;
      showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Verify room keys'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Room fingerprint',
                style: AppTypography.textTheme.labelMedium,
              ),
              const SizedBox(height: AppSpacing.xs),
              SelectableText(
                roomFingerprint,
                style: AppTypography.josefin(
                  size: 18,
                  weight: FontWeight.w700,
                  color: AppColors.charcoal,
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              Text(
                'This device signing key',
                style: AppTypography.textTheme.labelMedium,
              ),
              const SizedBox(height: AppSpacing.xs),
              SelectableText(
                deviceFingerprint,
                style: AppTypography.textTheme.bodyMedium,
              ),
              const SizedBox(height: AppSpacing.md),
              Text(
                'Compare fingerprints out of band when the conversation is sensitive.',
                style: AppTypography.textTheme.bodySmall?.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Close'),
            ),
          ],
        ),
      );
    } catch (e) {
      if (mounted) showErrorSnack(context, _friendlyError(e));
    }
  }

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollCtrl.hasClients) return;
      _scrollCtrl.animateTo(
        _scrollCtrl.position.maxScrollExtent,
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOutCubic,
      );
    });
  }

  void _showSender(Map<String, dynamic> profile) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) {
        final username = profile['username'] as String? ?? '';
        final displayName =
            (profile['display_name'] as String?)?.trim().isNotEmpty == true
                ? profile['display_name'] as String
                : username;
        final avatarUrl = profile['avatar_url'] as String?;
        return AlertDialog(
          contentPadding: const EdgeInsets.all(AppSpacing.xl),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SafeCircleAvatar(
                radius: 34,
                backgroundColor: AppColors.softSand,
                avatarUrl: avatarUrl,
              ),
              const SizedBox(height: AppSpacing.md),
              Text(displayName, style: AppTypography.textTheme.titleMedium),
              if (username.isNotEmpty)
                Text(
                  '@$username',
                  style: AppTypography.textTheme.bodySmall?.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
              const SizedBox(height: AppSpacing.lg),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: username.isEmpty
                      ? null
                      : () {
                          Navigator.pop(dialogContext);
                          context.push(
                              '/profile/${Uri.encodeComponent(username)}');
                        },
                  icon: const Icon(Icons.person_add_alt_1_rounded),
                  label: const Text('View profile and follow'),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _deleteMessage(SecureRoomMessage message) async {
    final canDelete = message.senderId == _currentUserId ||
        _room?.creatorId == _currentUserId;
    if (!canDelete) {
      showInfoSnack(context, 'Only the sender or room host can delete this.');
      return;
    }
    setState(() {
      _messages = _messages.where((m) => m.id != message.id).toList();
    });
    _addDeletedGhosts([message]);
    try {
      await _service.deleteMessage(message);
      await _loadMessagesOnly();
    } catch (e) {
      if (mounted) {
        showErrorSnack(context, _friendlyError(e));
        await _loadMessagesOnly();
      }
    }
  }

  Future<void> _showMessageActions(
    SecureRoomMessage message,
    bool mine,
  ) async {
    final canDelete = mine ||
        (_room?.creatorId != null && _room?.creatorId == _currentUserId);
    final sender = _profiles[message.senderId];
    final senderName = sender == null
        ? (mine ? 'You' : 'Unknown')
        : ((sender['display_name'] as String?)?.trim().isNotEmpty == true
            ? sender['display_name'] as String
            : sender['username'] as String? ?? 'Unknown');
    await showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      backgroundColor: _chatSurface,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) {
        final bottom = MediaQuery.paddingOf(sheetContext).bottom;
        return Padding(
          padding: EdgeInsets.fromLTRB(
            AppSpacing.lg,
            0,
            AppSpacing.lg,
            AppSpacing.lg + bottom,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Message details',
                  style: AppTypography.textTheme.titleLarge),
              const SizedBox(height: AppSpacing.md),
              _RoomSettingsTile(
                icon:
                    mine ? Icons.north_east_rounded : Icons.south_west_rounded,
                title: mine ? 'Sent by you' : 'Sent by $senderName',
                subtitle:
                    '${message.kind.toUpperCase()} • ${_formatDateTime(message.createdAt)}',
              ),
              const SizedBox(height: AppSpacing.sm),
              _RoomSettingsTile(
                icon: message.cryptographicallyVerified
                    ? Icons.verified_user_rounded
                    : Icons.warning_amber_rounded,
                title: message.cryptographicallyVerified
                    ? 'Signature verified'
                    : 'Integrity needs attention',
                subtitle: mine
                    ? '${message.deliveredCount} delivered • ${message.readCount} read'
                    : 'Device key ${message.senderDeviceId.isEmpty ? 'unknown' : 'registered'}',
              ),
              const SizedBox(height: AppSpacing.sm),
              _RoomSettingsTile(
                icon: Icons.timer_outlined,
                title: 'Auto-delete',
                subtitle:
                    'Expires in ${message.expiresAt.difference(DateTime.now()).inSeconds.clamp(0, 999)} seconds',
              ),
              const SizedBox(height: AppSpacing.lg),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => Navigator.pop(sheetContext),
                      icon: const Icon(Icons.close_rounded),
                      label: const Text('Close'),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: canDelete
                          ? () {
                              Navigator.pop(sheetContext);
                              _deleteMessage(message);
                            }
                          : null,
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.sunsetCoral,
                      ),
                      icon: const Icon(Icons.delete_outline_rounded),
                      label: const Text('Delete'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _showMembersSheet() async {
    final room = _room;
    if (room == null) return;
    var members = _members;
    if (members.isEmpty) {
      members = await _service.loadMembers(widget.roomId);
      if (mounted) setState(() => _members = members);
    }
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      backgroundColor: _chatSurface,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) {
        final bottom = MediaQuery.paddingOf(sheetContext).bottom;
        return Padding(
          padding: EdgeInsets.fromLTRB(
            AppSpacing.lg,
            0,
            AppSpacing.lg,
            AppSpacing.lg + bottom,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Room members', style: AppTypography.textTheme.titleLarge),
              const SizedBox(height: AppSpacing.xs),
              Text(
                '${room.memberProgressLabel}. Presence changes when someone leaves the app or comes back.',
                style: AppTypography.textTheme.bodySmall?.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              for (final member in members)
                _RoomMemberRow(
                  member: member,
                  isHost: member.userId == room.creatorId,
                  presence: _presenceFor(member.userId),
                  isCurrentUser: member.userId == _currentUserId,
                  joinedAtLabel: _formatDateTime(member.joinedAt),
                ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _updateRoomTimer(
    int seconds,
    StateSetter sheetSetState,
  ) async {
    final room = _room;
    if (room == null || room.creatorId != _currentUserId) {
      showInfoSnack(context, 'Only the room host can change the timer.');
      return;
    }
    setState(() => _ttlSeconds = seconds);
    sheetSetState(() {});
    try {
      final updated = await _service.updateRoomTimer(
        roomId: widget.roomId,
        ttlSeconds: seconds,
      );
      if (!mounted) return;
      setState(() {
        _room = updated;
        _ttlSeconds = updated.messageTtlSeconds;
      });
      sheetSetState(() {});
    } catch (e) {
      if (mounted) showErrorSnack(context, _friendlyError(e));
    }
  }

  SecureRoomPresence? _presenceFor(String userId) {
    for (final presence in _presence) {
      if (presence.userId == userId) return presence;
    }
    return null;
  }

  String _formatDateTime(DateTime value) {
    final local = value.toLocal();
    final hour = local.hour % 12 == 0 ? 12 : local.hour % 12;
    final minute = local.minute.toString().padLeft(2, '0');
    final suffix = local.hour >= 12 ? 'PM' : 'AM';
    return '${local.day}/${local.month}/${local.year} $hour:$minute $suffix';
  }

  Future<void> _showRoomSettingsSheet() {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: AppColors.white,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, sheetSetState) {
            final bottom = MediaQuery.paddingOf(sheetContext).bottom;
            final room = _room;
            final canChangeTimer =
                room != null && room.creatorId == _currentUserId;
            return Padding(
              padding: EdgeInsets.fromLTRB(
                AppSpacing.lg,
                AppSpacing.md,
                AppSpacing.lg,
                AppSpacing.xl + bottom,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 42,
                      height: 4,
                      decoration: BoxDecoration(
                        color: AppColors.borderMedium,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  Text(
                    'Room settings',
                    style: AppTypography.textTheme.headlineSmall,
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    canChangeTimer
                        ? 'Timer changes apply to new messages only.'
                        : 'Only the room host can change the message timer.',
                    style: AppTypography.textTheme.bodySmall?.copyWith(
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  Text('Message timer',
                      style: AppTypography.textTheme.titleSmall),
                  const SizedBox(height: AppSpacing.sm),
                  Wrap(
                    spacing: AppSpacing.sm,
                    runSpacing: AppSpacing.sm,
                    children: [
                      for (final option in const [120, 180, 300])
                        _ChatTimerChip(
                          label: '${option ~/ 60} min',
                          selected: _ttlSeconds == option,
                          onTap: canChangeTimer
                              ? () => unawaited(
                                    _updateRoomTimer(option, sheetSetState),
                                  )
                              : null,
                        ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  _RoomSettingsTile(
                    icon: Icons.group_outlined,
                    title: room?.isWaiting == true
                        ? 'Waiting for members'
                        : 'Soft mode room',
                    subtitle: room == null
                        ? 'Loading room configuration.'
                        : '${room.memberProgressLabel} • max ${room.maxMembers}',
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  _RoomSettingsTile(
                    icon: Icons.verified_user_rounded,
                    title: 'Signed encrypted messages',
                    subtitle: 'Each message keeps integrity metadata.',
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  Row(
                    children: [
                      if (_canShareInvite) ...[
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: _roomAvailable
                                ? () {
                                    Navigator.pop(sheetContext);
                                    _shareInvite();
                                  }
                                : null,
                            icon: const Icon(Icons.ios_share_rounded),
                            label: const Text('Share'),
                          ),
                        ),
                        const SizedBox(width: AppSpacing.md),
                      ],
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: _roomAvailable
                              ? () {
                                  Navigator.pop(sheetContext);
                                  _showKeyInfo();
                                }
                              : null,
                          icon: const Icon(Icons.fingerprint_rounded),
                          label: const Text('Verify'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  String _friendlyError(Object error) {
    final text = error.toString().replaceFirst('Exception: ', '').trim();
    if (text.isEmpty) return 'Room action failed.';
    return text;
  }

  @override
  Widget build(BuildContext context) {
    final room = _room;
    final timelineItems = _timelineItems();
    return Scaffold(
      backgroundColor: AppColors.surfaceSecondary,
      appBar: AppBar(
        titleSpacing: AppSpacing.sm,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              room?.inviteCode ?? 'Secure room',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTypography.textTheme.titleMedium?.copyWith(
                color: AppColors.charcoal,
                fontWeight: FontWeight.w800,
              ),
            ),
            Text(
              room == null
                  ? '${_ttlSeconds ~/ 60} min expiry'
                  : room.isWaiting
                      ? 'Waiting • ${room.memberProgressLabel}'
                      : _presenceSubtitle(),
              style: AppTypography.textTheme.labelMedium,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Room members',
            onPressed: _roomAvailable ? _showMembersSheet : null,
            icon: const Icon(Icons.groups_2_outlined),
          ),
          PopupMenuButton<String>(
            enabled: _roomAvailable,
            tooltip: 'Room menu',
            icon: const Icon(Icons.more_vert_rounded),
            onSelected: (value) {
              switch (value) {
                case 'share':
                  if (_canShareInvite) _shareInvite();
                  break;
                case 'verify':
                  _showKeyInfo();
                  break;
                case 'settings':
                  _showRoomSettingsSheet();
                  break;
                case 'leave':
                  _leaveRoom();
                  break;
              }
            },
            itemBuilder: (context) => [
              if (_canShareInvite)
                const PopupMenuItem(
                  value: 'share',
                  child: ListTile(
                    leading: Icon(Icons.ios_share_rounded),
                    title: Text('Share invite'),
                  ),
                ),
              const PopupMenuItem(
                value: 'verify',
                child: ListTile(
                  leading: Icon(Icons.fingerprint_rounded),
                  title: Text('Verify keys'),
                ),
              ),
              PopupMenuItem(
                value: 'settings',
                child: ListTile(
                  leading: Icon(Icons.tune_rounded),
                  title: Text('Room settings'),
                ),
              ),
              PopupMenuItem(
                value: 'leave',
                child: ListTile(
                  leading: Icon(Icons.logout_rounded),
                  title: Text('Leave room'),
                ),
              ),
            ],
          ),
        ],
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: AppColors.fernGreen,
              ),
            )
          : _closingRoom
              ? _RoomClosingView(reason: _closingRoomReason)
              : _error != null
                  ? _RoomUnavailable(
                      error: _error!, onBack: () => context.go('/rooms'))
                  : room?.isActive == false
                      ? _RoomUnavailable(
                          error: 'This room has been destroyed.',
                          onBack: () => context.go('/rooms'),
                        )
                      : DecoratedBox(
                          decoration: const BoxDecoration(color: _chatCanvas),
                          child: Column(
                            children: [
                              AnimatedSwitcher(
                                duration: const Duration(milliseconds: 260),
                                switchInCurve: Curves.easeOutCubic,
                                switchOutCurve: Curves.easeInCubic,
                                child: (_showSecurityBanner ||
                                        room?.isWaiting == true ||
                                        room?.isActive == false)
                                    ? _SecurityBanner(
                                        key: const ValueKey('security-banner'),
                                        room: room,
                                      )
                                    : const SizedBox.shrink(
                                        key: ValueKey('security-banner-hidden'),
                                      ),
                              ),
                              Expanded(
                                child: room?.isWaiting == true
                                    ? _WaitingRoomPanel(
                                        room: room!,
                                        onRefresh: _loadMessagesOnly,
                                        onShare: _canShareInvite
                                            ? _shareInvite
                                            : null,
                                      )
                                    : ListView.builder(
                                        controller: _scrollCtrl,
                                        keyboardDismissBehavior:
                                            ScrollViewKeyboardDismissBehavior
                                                .onDrag,
                                        padding: const EdgeInsets.fromLTRB(
                                          AppSpacing.md,
                                          AppSpacing.lg,
                                          AppSpacing.md,
                                          AppSpacing.xl,
                                        ),
                                        itemCount: timelineItems.length +
                                            (_typingLabel == null ? 0 : 1),
                                        itemBuilder: (context, index) {
                                          if (index >= timelineItems.length) {
                                            return _TypingIndicator(
                                                label: _typingLabel!);
                                          }
                                          final item = timelineItems[index];
                                          final pending =
                                              item is _PendingRoomMessage
                                                  ? item
                                                  : null;
                                          final message = switch (item) {
                                            SecureRoomMessage message =>
                                              message,
                                            _PendingRoomMessage pending =>
                                              pending.message,
                                            _DeletedMessageGhost ghost =>
                                              ghost.message,
                                            _ => throw StateError(
                                                'Unknown timeline item'),
                                          };
                                          final mine = message.senderId ==
                                              _currentUserId;
                                          final bubble = _MessageBubble(
                                            key: ValueKey(
                                                'bubble-${message.id}'),
                                            message: message,
                                            mine: mine,
                                            isHost: message.senderId ==
                                                room?.creatorId,
                                            profile:
                                                _profiles[message.senderId],
                                            service: _service,
                                            roomMemberCount:
                                                room?.activeMemberCount ?? 2,
                                            onProfileTap: (profile) =>
                                                _showSender(profile),
                                            onLongPress: pending == null
                                                ? () => _showMessageActions(
                                                      message,
                                                      mine,
                                                    )
                                                : () {},
                                            pending: pending != null,
                                            pendingLabel: pending?.label,
                                            localMediaPath:
                                                pending?.localMediaPath,
                                          );
                                          if (item is _DeletedMessageGhost) {
                                            return _DustVanishBubble(
                                              key: ValueKey(item.id),
                                              mine: mine,
                                              onDone: () =>
                                                  _removeDeletedGhost(item.id),
                                              child: bubble,
                                            );
                                          }
                                          return bubble;
                                        },
                                      ),
                              ),
                              if (!room!.isWaiting)
                                _Composer(
                                  controller: _textCtrl,
                                  sending: false,
                                  enabled: _canSend,
                                  ttlSeconds: _ttlSeconds,
                                  onSend: _sendText,
                                  onOpenMediaMenu: _showMediaMenu,
                                  onStartRecording: _startRecording,
                                  onStopRecording: () => _finishRecording(),
                                  onCancelRecording: _cancelRecording,
                                  onSendVoicePreview: _sendVoicePreview,
                                  onDiscardVoicePreview: _discardVoicePreview,
                                  recording: _recording,
                                  recordingSeconds: _recordingSeconds,
                                  recorderController: _recorderController,
                                  voicePreviewPath: _voicePreviewPath,
                                  voicePreviewDuration: _voicePreviewDuration,
                                  sendingVoiceNote: _sendingVoiceNote,
                                ),
                            ],
                          ),
                        ),
    );
  }

  String _presenceSubtitle() {
    if (_presence.isEmpty) {
      return '1 here • ${_ttlSeconds ~/ 60} min expiry';
    }
    final active = _presence.where((p) => p.isActive).length + 1;
    final away = _presence.where((p) => p.isBackground).length;
    if (active > 0 && away > 0) {
      return '$active here • $away away • ${_ttlSeconds ~/ 60} min expiry';
    }
    if (active > 0) return '$active here • ${_ttlSeconds ~/ 60} min expiry';
    if (away > 0) return '$away away • ${_ttlSeconds ~/ 60} min expiry';
    return 'Encrypted • ${_ttlSeconds ~/ 60} min expiry';
  }
}

class _RoomSettingsTile extends StatelessWidget {
  const _RoomSettingsTile({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surfaceSecondary,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.borderSubtle),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: AppColors.charcoal.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, size: 19, color: AppColors.charcoal),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: AppTypography.textTheme.titleSmall),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: AppTypography.textTheme.bodySmall?.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _RoomMemberRow extends StatelessWidget {
  const _RoomMemberRow({
    required this.member,
    required this.isHost,
    required this.presence,
    required this.isCurrentUser,
    required this.joinedAtLabel,
  });

  final SecureRoomMember member;
  final bool isHost;
  final SecureRoomPresence? presence;
  final bool isCurrentUser;
  final String joinedAtLabel;

  @override
  Widget build(BuildContext context) {
    final state = isCurrentUser
        ? SecureRoomPresenceState.active
        : presence?.state ?? SecureRoomPresenceState.offline;
    final stateLabel = isCurrentUser
        ? 'You are here'
        : presence?.label ?? '${member.label} is offline';
    final stateColor = switch (state) {
      SecureRoomPresenceState.active => AppColors.fernGreen,
      SecureRoomPresenceState.background => AppColors.sunsetCoral,
      SecureRoomPresenceState.offline => AppColors.textTertiary,
    };
    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.borderSubtle),
      ),
      child: Row(
        children: [
          Stack(
            clipBehavior: Clip.none,
            children: [
              SafeCircleAvatar(
                radius: 22,
                backgroundColor: AppColors.softSand,
                avatarUrl: member.avatarUrl,
              ),
              Positioned(
                right: -1,
                bottom: -1,
                child: Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    color: stateColor,
                    shape: BoxShape.circle,
                    border: Border.all(color: AppColors.white, width: 2),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        isCurrentUser ? '${member.label} (you)' : member.label,
                        overflow: TextOverflow.ellipsis,
                        style: AppTypography.textTheme.titleSmall?.copyWith(
                          color: _softInk,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    if (isHost) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 7,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.fernGreenLight,
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          'Host',
                          style: AppTypography.textTheme.labelSmall?.copyWith(
                            color: AppColors.fernGreenDark,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  '$stateLabel • joined $joinedAtLabel',
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.textTheme.bodySmall?.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ChatTimerChip extends StatelessWidget {
  const _ChatTimerChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final background = selected ? AppColors.charcoal : AppColors.white;
    final foreground = selected ? AppColors.white : AppColors.charcoal;
    return Material(
      color: background,
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.sm,
          ),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: selected ? AppColors.fernGreen : AppColors.borderMedium,
              width: selected ? 1.6 : 1,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                selected ? Icons.check_rounded : Icons.timer_rounded,
                size: 16,
                color: onTap == null ? AppColors.textTertiary : foreground,
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: AppTypography.textTheme.labelLarge?.copyWith(
                  color: onTap == null ? AppColors.textTertiary : foreground,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SecurityBanner extends StatelessWidget {
  const _SecurityBanner({super.key, required this.room});
  final SecureRoomSummary? room;

  @override
  Widget build(BuildContext context) {
    final roomAvailable = room?.isActive ?? false;
    final waiting = room?.isWaiting ?? false;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.sm,
      ),
      color:
          roomAvailable ? AppColors.fernGreenLight : AppColors.sunsetCoralLight,
      child: Row(
        children: [
          Icon(
            roomAvailable
                ? Icons.enhanced_encryption_rounded
                : Icons.lock_clock_outlined,
            size: 16,
            color: roomAvailable
                ? AppColors.fernGreenDark
                : AppColors.sunsetCoralDark,
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              waiting
                  ? 'Waiting room. Messages unlock when members join or the timer resolves.'
                  : roomAvailable
                      ? 'Encrypted locally. Ed25519-signed messages. Auto-deletion active.'
                      : 'This room has been destroyed. Sending is disabled.',
              style: AppTypography.textTheme.bodySmall?.copyWith(
                color: roomAvailable
                    ? AppColors.fernGreenDark
                    : AppColors.sunsetCoralDark,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _WaitingRoomPanel extends StatelessWidget {
  const _WaitingRoomPanel({
    required this.room,
    required this.onRefresh,
    required this.onShare,
  });

  final SecureRoomSummary room;
  final Future<void> Function() onRefresh;
  final VoidCallback? onShare;

  @override
  Widget build(BuildContext context) {
    final expiresAt = room.waitingExpiresAt;
    final remaining =
        expiresAt?.difference(DateTime.now()).inSeconds.clamp(0, 999).toInt();
    final wide = MediaQuery.sizeOf(context).width >= 700;

    return RefreshIndicator(
      color: AppColors.fernGreen,
      onRefresh: onRefresh,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.fromLTRB(
          wide ? 48 : AppSpacing.xl,
          AppSpacing.xxl,
          wide ? 48 : AppSpacing.xl,
          AppSpacing.xxl,
        ),
        children: [
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: AppColors.white,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: AppColors.borderSubtle),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.05),
                      blurRadius: 26,
                      offset: const Offset(0, 16),
                    ),
                  ],
                ),
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.xl),
                  child: Column(
                    children: [
                      const _WaitingPulse(),
                      const SizedBox(height: AppSpacing.lg),
                      Text(
                        'Waiting for members',
                        style: AppTypography.textTheme.headlineSmall,
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      Text(
                        '${room.memberProgressLabel}. The chat starts when everyone joins. If only the host is here when the timer ends, the room is destroyed.',
                        style: AppTypography.textTheme.bodyMedium?.copyWith(
                          color: AppColors.textSecondary,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      if (remaining != null) ...[
                        const SizedBox(height: AppSpacing.lg),
                        Text(
                          '${remaining ~/ 60}:${(remaining % 60).toString().padLeft(2, '0')}',
                          style: AppTypography.josefin(
                            size: 34,
                            weight: FontWeight.w700,
                            color: AppColors.charcoal,
                          ),
                        ),
                      ],
                      const SizedBox(height: AppSpacing.lg),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: onRefresh,
                              icon: const Icon(Icons.refresh_rounded),
                              label: const Text('Refresh'),
                            ),
                          ),
                          if (onShare != null) ...[
                            const SizedBox(width: AppSpacing.md),
                            Expanded(
                              child: FilledButton.icon(
                                onPressed: onShare,
                                icon: const Icon(Icons.ios_share_rounded),
                                label: const Text('Share'),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _WaitingPulse extends StatefulWidget {
  const _WaitingPulse();

  @override
  State<_WaitingPulse> createState() => _WaitingPulseState();
}

class _WaitingPulseState extends State<_WaitingPulse>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1300),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        return Container(
          width: 78 + _controller.value * 8,
          height: 78 + _controller.value * 8,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: AppColors.fernGreenLight,
            border: Border.all(
              color: AppColors.fernGreen.withValues(
                alpha: 0.24 + _controller.value * 0.22,
              ),
              width: 2,
            ),
          ),
          child: const Icon(
            Icons.lock_clock_rounded,
            color: AppColors.fernGreen,
            size: 34,
          ),
        );
      },
    );
  }
}

class _DeletedMessageGhost {
  const _DeletedMessageGhost({
    required this.id,
    required this.message,
  });

  final String id;
  final SecureRoomMessage message;
}

class _PendingRoomMessage {
  const _PendingRoomMessage({
    required this.message,
    this.localMediaPath,
    this.label = 'sending...',
  });

  final SecureRoomMessage message;
  final String? localMediaPath;
  final String label;
}

class _DustVanishBubble extends StatefulWidget {
  const _DustVanishBubble({
    super.key,
    required this.child,
    required this.mine,
    required this.onDone,
  });

  final Widget child;
  final bool mine;
  final VoidCallback onDone;

  @override
  State<_DustVanishBubble> createState() => _DustVanishBubbleState();
}

class _DustVanishBubbleState extends State<_DustVanishBubble>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1450),
    )
      ..addStatusListener((status) {
        if (status == AnimationStatus.completed) widget.onDone();
      })
      ..forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final t = Curves.easeInOutCubic.transform(_controller.value);
        return ClipRect(
          child: CustomPaint(
            foregroundPainter: _DustVanishPainter(
              progress: t,
              mine: widget.mine,
            ),
            child: Opacity(
              opacity: (1 - t * 0.92).clamp(0.0, 1.0).toDouble(),
              child: Transform.translate(
                offset: Offset(widget.mine ? t * 24 : -t * 24, -t * 12),
                child: Transform.scale(
                  scale: 1 - t * 0.11,
                  alignment: widget.mine
                      ? Alignment.centerRight
                      : Alignment.centerLeft,
                  child: child,
                ),
              ),
            ),
          ),
        );
      },
      child: widget.child,
    );
  }
}

class _DustVanishPainter extends CustomPainter {
  const _DustVanishPainter({
    required this.progress,
    required this.mine,
  });

  final double progress;
  final bool mine;

  @override
  void paint(Canvas canvas, Size size) {
    if (progress <= 0.02 || size.isEmpty) return;
    final random = math.Random(42);
    final originX = mine ? size.width * 0.82 : size.width * 0.18;
    final originY = size.height * 0.54;
    final baseColor = mine ? AppColors.fernGreenDark : AppColors.charcoal;
    final paint = Paint()..style = PaintingStyle.fill;

    for (var i = 0; i < 86; i++) {
      final direction = mine ? -1.0 : 1.0;
      final angle = direction * (0.08 + random.nextDouble() * 1.1);
      final distance = (10 + random.nextDouble() * 118) * progress;
      final drift = (random.nextDouble() - 0.5) * 46 * progress;
      final radius = (0.7 + random.nextDouble() * 3.1) *
          math.pow(1 - progress, 1.4).toDouble();
      if (radius <= 0) continue;
      paint.color = baseColor.withValues(
        alpha: ((0.38 + random.nextDouble() * 0.22) * (1 - progress))
            .clamp(0.0, 0.48)
            .toDouble(),
      );
      canvas.drawCircle(
        Offset(
          originX + math.cos(angle) * distance * direction,
          originY + math.sin(angle) * distance + drift - progress * 18,
        ),
        radius,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _DustVanishPainter oldDelegate) {
    return oldDelegate.progress != progress || oldDelegate.mine != mine;
  }
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({
    super.key,
    required this.message,
    required this.mine,
    required this.isHost,
    required this.profile,
    required this.service,
    required this.roomMemberCount,
    required this.onProfileTap,
    required this.onLongPress,
    this.pending = false,
    this.pendingLabel,
    this.localMediaPath,
  });

  final SecureRoomMessage message;
  final bool mine;
  final bool isHost;
  final Map<String, dynamic>? profile;
  final SecureRoomService service;
  final int roomMemberCount;
  final ValueChanged<Map<String, dynamic>> onProfileTap;
  final VoidCallback onLongPress;
  final bool pending;
  final String? pendingLabel;
  final String? localMediaPath;

  @override
  Widget build(BuildContext context) {
    final avatarUrl = profile?['avatar_url'] as String?;
    final name = profile == null
        ? 'Unknown'
        : ((profile!['display_name'] as String?)?.trim().isNotEmpty == true
            ? profile!['display_name'] as String
            : profile!['username'] as String? ?? 'Unknown');
    final username = profile?['username'] as String?;
    final expiresIn = message.expiresAt.difference(DateTime.now()).inSeconds;
    final width = MediaQuery.sizeOf(context).width;
    final maxBubbleWidth = math.min(
      540.0,
      math.max(238.0, width * (width < 600 ? 0.80 : 0.66)),
    );
    final bubbleColor = mine ? _mineBubble : _otherBubble;
    final borderColor = mine
        ? AppColors.fernGreen.withValues(alpha: 0.22)
        : AppColors.borderSubtle.withValues(alpha: 0.8);

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Row(
        mainAxisAlignment:
            mine ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!mine)
            GestureDetector(
              onTap: profile == null ? null : () => onProfileTap(profile!),
              child: SafeCircleAvatar(
                radius: 16,
                backgroundColor: AppColors.softSand,
                avatarUrl: avatarUrl,
              ),
            ),
          if (!mine) const SizedBox(width: AppSpacing.sm),
          Flexible(
            child: GestureDetector(
              onLongPress: onLongPress,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                constraints: BoxConstraints(maxWidth: maxBubbleWidth),
                padding: EdgeInsets.all(
                  message.kind == 'text' || message.kind == 'system'
                      ? AppSpacing.md
                      : AppSpacing.sm,
                ),
                decoration: BoxDecoration(
                  color: bubbleColor,
                  borderRadius: BorderRadius.only(
                    topLeft: const Radius.circular(22),
                    topRight: const Radius.circular(22),
                    bottomLeft: Radius.circular(mine ? 22 : 8),
                    bottomRight: Radius.circular(mine ? 8 : 22),
                  ),
                  border: Border.all(color: borderColor),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.035),
                      blurRadius: 18,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment:
                      mine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                  children: [
                    if (!mine)
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Flexible(
                            child: Text(
                              name,
                              overflow: TextOverflow.ellipsis,
                              style:
                                  AppTypography.textTheme.labelMedium?.copyWith(
                                color: AppColors.fernGreenDark,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          if (username?.isNotEmpty == true) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 7,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color:
                                    AppColors.charcoal.withValues(alpha: 0.06),
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: Text(
                                '@$username',
                                style: AppTypography.textTheme.labelSmall
                                    ?.copyWith(
                                  color: AppColors.textSecondary,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ],
                          if (isHost) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: AppColors.fernGreenLight,
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: Text(
                                'Host',
                                style: AppTypography.textTheme.labelSmall
                                    ?.copyWith(color: AppColors.fernGreenDark),
                              ),
                            ),
                          ],
                        ],
                      ),
                    if (pending && localMediaPath != null)
                      _PendingLocalMediaPreview(
                        kind: message.kind,
                        localPath: localMediaPath!,
                        durationMs: message.audioDurationMs,
                      )
                    else if (pending)
                      _PendingInlinePreview(
                        kind: message.kind,
                        text: message.text ?? pendingLabel ?? 'sending...',
                      )
                    else if (message.kind == 'image' || message.kind == 'gif')
                      _EncryptedImage(message: message, service: service)
                    else if (message.kind == 'video')
                      _EncryptedVideo(message: message, service: service)
                    else if (message.kind == 'audio')
                      _EncryptedAudio(message: message, service: service)
                    else
                      Text(
                        message.text ?? '',
                        style: AppTypography.textTheme.bodyMedium?.copyWith(
                          color: _softInk,
                          height: 1.35,
                        ),
                      ),
                    const SizedBox(height: AppSpacing.sm),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          pending
                              ? Icons.schedule_rounded
                              : message.cryptographicallyVerified
                                  ? Icons.verified_user_rounded
                                  : Icons.warning_amber_rounded,
                          size: 13,
                          color: pending
                              ? AppColors.textTertiary
                              : message.cryptographicallyVerified
                                  ? AppColors.fernGreenDark
                                  : AppColors.sunsetCoral,
                        ),
                        const SizedBox(width: 4),
                        if (!pending &&
                            message.cryptographicallyVerified &&
                            mine) ...[
                          Icon(
                            _deliveryIcon(message),
                            size: 13,
                            color: _deliveryColor(message),
                          ),
                          const SizedBox(width: 4),
                        ],
                        Text(
                          pending
                              ? pendingLabel ?? 'sending...'
                              : message.cryptographicallyVerified
                                  ? mine
                                      ? '${_deliveryLabel(message)} • ${expiresIn.clamp(0, 999)}s'
                                      : '${expiresIn.clamp(0, 999)}s'
                                  : message.integrityOk
                                      ? 'sender key unknown'
                                      : 'integrity warning',
                          style: AppTypography.textTheme.labelSmall?.copyWith(
                            color: AppColors.textTertiary,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _deliveryLabel(SecureRoomMessage message) {
    final expectedReaders = (roomMemberCount - 1).clamp(1, 2).toInt();
    if (message.readCount >= expectedReaders) return 'read';
    if (message.readCount > 0) return 'seen ${message.readCount}';
    if (message.deliveredCount >= expectedReaders) return 'delivered';
    if (message.deliveredCount > 0) {
      return 'delivered ${message.deliveredCount}';
    }
    return 'sent';
  }

  IconData _deliveryIcon(SecureRoomMessage message) {
    return message.deliveredCount > 0 || message.readCount > 0
        ? Icons.done_all_rounded
        : Icons.done_rounded;
  }

  Color _deliveryColor(SecureRoomMessage message) {
    if (message.readCount > 0) return AppColors.fernGreenDark;
    return AppColors.textTertiary;
  }
}

Future<void> _showEncryptedImageViewer(
  BuildContext context,
  Uint8List bytes,
) {
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Close image',
    barrierColor: Colors.black.withValues(alpha: 0.92),
    transitionDuration: const Duration(milliseconds: 180),
    pageBuilder: (context, animation, secondaryAnimation) {
      return Scaffold(
        backgroundColor: Colors.transparent,
        body: SafeArea(
          child: Stack(
            children: [
              Center(
                child: InteractiveViewer(
                  minScale: 0.8,
                  maxScale: 4,
                  child: Image.memory(bytes, fit: BoxFit.contain),
                ),
              ),
              Positioned(
                top: AppSpacing.md,
                right: AppSpacing.md,
                child: IconButton.filled(
                  style: IconButton.styleFrom(
                    backgroundColor: Colors.black.withValues(alpha: 0.42),
                    foregroundColor: AppColors.white,
                  ),
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close_rounded),
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}

Future<void> _showEncryptedVideoViewer(BuildContext context, File file) {
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Close video',
    barrierColor: Colors.black.withValues(alpha: 0.94),
    transitionDuration: const Duration(milliseconds: 180),
    pageBuilder: (context, animation, secondaryAnimation) {
      return _EncryptedVideoViewer(file: file);
    },
  );
}

class _PendingInlinePreview extends StatelessWidget {
  const _PendingInlinePreview({
    required this.kind,
    required this.text,
  });

  final String kind;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          switch (kind) {
            'image' || 'gif' => Icons.image_outlined,
            'video' => Icons.movie_outlined,
            'audio' => Icons.mic_none_rounded,
            _ => Icons.lock_outline_rounded,
          },
          size: 18,
          color: AppColors.fernGreenDark,
        ),
        const SizedBox(width: AppSpacing.sm),
        Flexible(
          child: Text(
            text,
            style: AppTypography.textTheme.bodyMedium?.copyWith(
              color: _softInk,
              height: 1.35,
            ),
          ),
        ),
      ],
    );
  }
}

class _PendingLocalMediaPreview extends StatelessWidget {
  const _PendingLocalMediaPreview({
    required this.kind,
    required this.localPath,
    required this.durationMs,
  });

  final String kind;
  final String localPath;
  final int? durationMs;

  @override
  Widget build(BuildContext context) {
    final width = _mediaPreviewWidth(context);
    if (kind == 'audio') {
      return _VoiceMessagePlayer(
        localPath: localPath,
        durationMs: durationMs,
        compact: true,
        busy: true,
      );
    }

    if (kind == 'image' || kind == 'gif') {
      return ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: Stack(
          children: [
            Image.file(
              File(localPath),
              width: width,
              height: width * 0.72,
              fit: BoxFit.cover,
              gaplessPlayback: true,
            ),
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.12),
                ),
                child: const Center(
                  child: SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: AppColors.white,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    }

    return _PendingLocalVideoPreview(
      localPath: localPath,
      width: width,
      durationMs: durationMs,
    );
  }
}

class _PendingLocalVideoPreview extends StatefulWidget {
  const _PendingLocalVideoPreview({
    required this.localPath,
    required this.width,
    required this.durationMs,
  });

  final String localPath;
  final double width;
  final int? durationMs;

  @override
  State<_PendingLocalVideoPreview> createState() =>
      _PendingLocalVideoPreviewState();
}

class _PendingLocalVideoPreviewState extends State<_PendingLocalVideoPreview> {
  VideoPlayerController? _controller;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final controller = VideoPlayerController.file(File(widget.localPath));
      await controller.initialize();
      if (!mounted) {
        await controller.dispose();
        return;
      }
      setState(() => _controller = controller);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: SizedBox(
        width: widget.width,
        height: widget.width * 0.62,
        child: Stack(
          fit: StackFit.expand,
          alignment: Alignment.center,
          children: [
            if (controller != null)
              FittedBox(
                fit: BoxFit.cover,
                child: SizedBox(
                  width: controller.value.size.width,
                  height: controller.value.size.height,
                  child: VideoPlayer(controller),
                ),
              )
            else
              ColoredBox(
                color: AppColors.charcoal.withValues(alpha: 0.08),
                child: Icon(
                  Icons.movie_outlined,
                  color: AppColors.charcoal.withValues(alpha: 0.42),
                  size: 42,
                ),
              ),
            ColoredBox(color: Colors.black.withValues(alpha: 0.14)),
            const Center(
              child: SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: AppColors.white,
                ),
              ),
            ),
            Positioned(
              right: 8,
              bottom: 8,
              child: _VideoDurationPill(
                duration: Duration(milliseconds: widget.durationMs ?? 0),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _VideoDurationPill extends StatelessWidget {
  const _VideoDurationPill({required this.duration});

  final Duration duration;

  @override
  Widget build(BuildContext context) {
    final label = _formatShortDuration(duration);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.52),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: AppTypography.textTheme.labelSmall?.copyWith(
          color: AppColors.white,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _EncryptedVideoViewer extends StatefulWidget {
  const _EncryptedVideoViewer({required this.file});

  final File file;

  @override
  State<_EncryptedVideoViewer> createState() => _EncryptedVideoViewerState();
}

class _EncryptedVideoViewerState extends State<_EncryptedVideoViewer> {
  VideoPlayerController? _controller;
  bool _loading = true;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final controller = VideoPlayerController.file(widget.file);
      await controller.initialize();
      await controller.setLooping(true);
      await controller.play();
      if (!mounted) {
        await controller.dispose();
        return;
      }
      setState(() {
        _controller = controller;
        _loading = false;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _loading = false;
          _failed = true;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        child: Stack(
          children: [
            Positioned.fill(
              child: _loading
                  ? const Center(
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppColors.fernGreen,
                      ),
                    )
                  : _failed || controller == null
                      ? Center(
                          child: Text(
                            'Video unavailable',
                            style: AppTypography.textTheme.bodyMedium?.copyWith(
                              color: AppColors.white,
                            ),
                          ),
                        )
                      : GestureDetector(
                          onTap: () {
                            controller.value.isPlaying
                                ? controller.pause()
                                : controller.play();
                            setState(() {});
                          },
                          child: LayoutBuilder(
                            builder: (context, _) {
                              final size = controller.value.size;
                              return Center(
                                child: FittedBox(
                                  fit: BoxFit.contain,
                                  child: SizedBox(
                                    width: size.width <= 0 ? 1 : size.width,
                                    height: size.height <= 0 ? 1 : size.height,
                                    child: VideoPlayer(controller),
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
            ),
            Positioned(
              top: AppSpacing.md,
              right: AppSpacing.md,
              child: IconButton.filled(
                style: IconButton.styleFrom(
                  backgroundColor: Colors.black.withValues(alpha: 0.42),
                  foregroundColor: AppColors.white,
                ),
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close_rounded),
              ),
            ),
            if (controller != null)
              ValueListenableBuilder<VideoPlayerValue>(
                valueListenable: controller,
                builder: (context, value, _) {
                  final duration = value.duration;
                  final position =
                      value.position > duration ? duration : value.position;
                  final canSeek = duration.inMilliseconds > 0;
                  return Stack(
                    children: [
                      if (!value.isPlaying)
                        Center(
                          child: IgnorePointer(
                            child: Container(
                              width: 72,
                              height: 72,
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: 0.38),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.play_arrow_rounded,
                                color: AppColors.white,
                                size: 42,
                              ),
                            ),
                          ),
                        ),
                      Positioned(
                        left: AppSpacing.md,
                        right: AppSpacing.md,
                        bottom: AppSpacing.md,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.46),
                            borderRadius: BorderRadius.circular(18),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(8, 6, 12, 6),
                            child: Row(
                              children: [
                                IconButton(
                                  visualDensity: VisualDensity.compact,
                                  color: AppColors.white,
                                  onPressed: () {
                                    value.isPlaying
                                        ? controller.pause()
                                        : controller.play();
                                  },
                                  icon: Icon(
                                    value.isPlaying
                                        ? Icons.pause_rounded
                                        : Icons.play_arrow_rounded,
                                  ),
                                ),
                                Text(
                                  _formatShortDuration(position),
                                  style: AppTypography.textTheme.labelSmall
                                      ?.copyWith(color: AppColors.white),
                                ),
                                Expanded(
                                  child: SliderTheme(
                                    data: SliderTheme.of(context).copyWith(
                                      trackHeight: 2.6,
                                      thumbShape: const RoundSliderThumbShape(
                                        enabledThumbRadius: 5,
                                      ),
                                      overlayShape:
                                          const RoundSliderOverlayShape(
                                        overlayRadius: 12,
                                      ),
                                      activeTrackColor: AppColors.fernGreen,
                                      inactiveTrackColor:
                                          Colors.white.withValues(alpha: 0.24),
                                      thumbColor: AppColors.white,
                                    ),
                                    child: Slider(
                                      value: canSeek
                                          ? position.inMilliseconds
                                              .clamp(
                                                0,
                                                duration.inMilliseconds,
                                              )
                                              .toDouble()
                                          : 0,
                                      max: canSeek
                                          ? duration.inMilliseconds.toDouble()
                                          : 1,
                                      onChanged: canSeek
                                          ? (value) => controller.seekTo(
                                                Duration(
                                                  milliseconds: value.round(),
                                                ),
                                              )
                                          : null,
                                    ),
                                  ),
                                ),
                                Text(
                                  _formatShortDuration(duration),
                                  style: AppTypography.textTheme.labelSmall
                                      ?.copyWith(color: AppColors.white),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
          ],
        ),
      ),
    );
  }
}

class _EncryptedImage extends StatefulWidget {
  const _EncryptedImage({required this.message, required this.service});

  final SecureRoomMessage message;
  final SecureRoomService service;

  @override
  State<_EncryptedImage> createState() => _EncryptedImageState();
}

class _EncryptedImageState extends State<_EncryptedImage> {
  late final Future<Uint8List> _mediaFuture;

  @override
  void initState() {
    super.initState();
    _mediaFuture = widget.service.decryptMedia(widget.message);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Uint8List>(
      future: _mediaFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const _MediaLoadingBox(icon: Icons.image_outlined);
        }
        if (!snapshot.hasData) {
          return const _MediaErrorBox(text: 'Image unavailable');
        }
        final width = _mediaPreviewWidth(context);
        final bytes = snapshot.data!;
        return GestureDetector(
          onTap: () => _showEncryptedImageViewer(context, bytes),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(18),
            child: SizedBox(
              width: width,
              height: width * 0.72,
              child: Image.memory(
                bytes,
                fit: BoxFit.cover,
                gaplessPlayback: true,
              ),
            ),
          ),
        );
      },
    );
  }
}

class _EncryptedVideo extends StatefulWidget {
  const _EncryptedVideo({required this.message, required this.service});

  final SecureRoomMessage message;
  final SecureRoomService service;

  @override
  State<_EncryptedVideo> createState() => _EncryptedVideoState();
}

class _EncryptedVideoState extends State<_EncryptedVideo> {
  VideoPlayerController? _controller;
  File? _file;
  bool _loading = true;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _controller?.dispose();
    final file = _file;
    if (file != null) {
      unawaited(_deleteTempFile(file));
    }
    super.dispose();
  }

  Future<void> _deleteTempFile(File file) async {
    try {
      await file.delete();
    } catch (_) {
      // Best effort cleanup for decrypted playback cache.
    }
  }

  Future<void> _load() async {
    try {
      final bytes = await widget.service.decryptMedia(widget.message);
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/secure_room_${widget.message.id}.mp4');
      await file.writeAsBytes(bytes, flush: true);
      final controller = VideoPlayerController.file(file);
      await controller.initialize();
      await controller.setLooping(true);
      if (!mounted) {
        await controller.dispose();
        return;
      }
      setState(() {
        _controller = controller;
        _file = file;
        _loading = false;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _loading = false;
          _failed = true;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const _MediaLoadingBox(icon: Icons.videocam_outlined);
    if (_failed || _controller == null) {
      return const _MediaErrorBox(text: 'Video unavailable');
    }
    final controller = _controller!;
    final width = _mediaPreviewWidth(context);
    return GestureDetector(
      onTap: () => _showEncryptedVideoViewer(context, _file!),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: SizedBox(
          width: width,
          height: width * 0.62,
          child: Stack(
            fit: StackFit.expand,
            children: [
              FittedBox(
                fit: BoxFit.cover,
                child: SizedBox(
                  width: controller.value.size.width,
                  height: controller.value.size.height,
                  child: VideoPlayer(controller),
                ),
              ),
              ColoredBox(
                color: Colors.black.withValues(alpha: 0.18),
                child: Center(
                  child: Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.32),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.open_in_full_rounded,
                      color: AppColors.white,
                      size: 24,
                    ),
                  ),
                ),
              ),
              Positioned(
                right: 8,
                bottom: 8,
                child: _VideoDurationPill(
                  duration: controller.value.duration,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EncryptedAudio extends StatefulWidget {
  const _EncryptedAudio({required this.message, required this.service});

  final SecureRoomMessage message;
  final SecureRoomService service;

  @override
  State<_EncryptedAudio> createState() => _EncryptedAudioState();
}

class _EncryptedAudioState extends State<_EncryptedAudio> {
  File? _file;
  bool _loading = true;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    final file = _file;
    if (file != null) {
      unawaited(_deleteTempFile(file));
    }
    super.dispose();
  }

  Future<void> _deleteTempFile(File file) async {
    try {
      await file.delete();
    } catch (_) {
      // Best effort cleanup for decrypted playback cache.
    }
  }

  Future<void> _load() async {
    try {
      final bytes = await widget.service.decryptMedia(widget.message);
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/secure_room_${widget.message.id}.m4a');
      await file.writeAsBytes(bytes, flush: true);
      if (!mounted) return;
      setState(() {
        _file = file;
        _loading = false;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _loading = false;
          _failed = true;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const _MediaLoadingBox(icon: Icons.mic_none_rounded);
    if (_failed || _file == null) {
      return const _MediaErrorBox(text: 'Voice note unavailable');
    }
    return _VoiceMessagePlayer(
      localPath: _file!.path,
      durationMs: widget.message.audioDurationMs,
    );
  }
}

class _VoiceMessagePlayer extends StatefulWidget {
  const _VoiceMessagePlayer({
    required this.localPath,
    this.durationMs,
    this.compact = false,
    this.busy = false,
  });

  final String localPath;
  final int? durationMs;
  final bool compact;
  final bool busy;

  @override
  State<_VoiceMessagePlayer> createState() => _VoiceMessagePlayerState();
}

class _VoiceMessagePlayerState extends State<_VoiceMessagePlayer> {
  late PlayerController _playerController;
  StreamSubscription<PlayerState>? _stateSub;
  StreamSubscription<int>? _durationSub;
  StreamSubscription<void>? _completionSub;
  bool _preparing = true;
  bool _failed = false;
  bool _playing = false;
  int _positionMs = 0;
  int _durationMs = 0;

  @override
  void initState() {
    super.initState();
    _durationMs = widget.durationMs ?? 0;
    _createController();
    unawaited(_prepare());
  }

  @override
  void didUpdateWidget(covariant _VoiceMessagePlayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.localPath != widget.localPath) {
      unawaited(_reloadForNewFile());
      return;
    }
    final durationMs = widget.durationMs;
    if (durationMs != null && durationMs > 0 && durationMs != _durationMs) {
      _durationMs = durationMs;
    }
  }

  @override
  void dispose() {
    _stateSub?.cancel();
    _durationSub?.cancel();
    _completionSub?.cancel();
    _playerController.dispose();
    super.dispose();
  }

  void _createController() {
    _playerController = PlayerController()
      ..updateFrequency =
          widget.compact ? UpdateFrequency.medium : UpdateFrequency.high;
    _stateSub = _playerController.onPlayerStateChanged.listen((state) {
      if (!mounted) return;
      setState(() => _playing = state.isPlaying);
    });
    _durationSub = _playerController.onCurrentDurationChanged.listen((ms) {
      if (!mounted) return;
      setState(() {
        _positionMs = ms.clamp(0, math.max(_durationMs, ms)).toInt();
      });
    });
    _completionSub = _playerController.onCompletion.listen((_) {
      if (!mounted) return;
      setState(() {
        _playing = false;
        if (_durationMs > 0) _positionMs = _durationMs;
      });
    });
  }

  Future<void> _reloadForNewFile() async {
    await _stateSub?.cancel();
    await _durationSub?.cancel();
    await _completionSub?.cancel();
    _playerController.dispose();
    if (!mounted) return;
    setState(() {
      _preparing = true;
      _failed = false;
      _playing = false;
      _positionMs = 0;
      _durationMs = widget.durationMs ?? 0;
    });
    _createController();
    await _prepare();
  }

  Future<void> _prepare() async {
    try {
      final file = File(widget.localPath);
      if (!await file.exists() || await file.length() <= 0) {
        throw Exception('Voice file is missing.');
      }
      await _playerController.preparePlayer(
        path: widget.localPath,
        shouldExtractWaveform: true,
        noOfSamples: widget.compact ? 40 : 54,
        volume: 1,
      );
      await _playerController.setFinishMode(finishMode: FinishMode.pause);
      final detectedDuration = _playerController.maxDuration > 0
          ? _playerController.maxDuration
          : await _playerController.getDuration();
      if (!mounted) return;
      setState(() {
        _durationMs = widget.durationMs != null && widget.durationMs! > 0
            ? widget.durationMs!
            : math.max(0, detectedDuration);
        _preparing = false;
        _failed = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _preparing = false;
        _failed = true;
      });
    }
  }

  Future<void> _togglePlayback() async {
    if (_preparing || _failed) return;
    try {
      if (_playing) {
        await _playerController.pausePlayer();
        return;
      }
      if (_durationMs > 0 && _positionMs >= _durationMs - 180) {
        await _playerController.seekTo(0);
        if (mounted) setState(() => _positionMs = 0);
      }
      await _playerController.startPlayer(forceRefresh: false);
    } catch (_) {
      if (!mounted) return;
      setState(() => _failed = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_failed) {
      return const _MediaErrorBox(text: 'Voice note unavailable');
    }
    final current = Duration(milliseconds: math.max(0, _positionMs));
    final total = Duration(milliseconds: math.max(0, _durationMs));
    final playerHeight = widget.compact ? 32.0 : 38.0;
    return LayoutBuilder(
      builder: (context, constraints) {
        final fallbackWidth =
            widget.compact ? 184.0 : _mediaPreviewWidth(context);
        final availableWidth =
            constraints.hasBoundedWidth ? constraints.maxWidth : fallbackWidth;
        final width = math.max(156.0, math.min(fallbackWidth, availableWidth));
        final waveformWidth = math.max(78.0, width - 106);

        return Container(
          width: width,
          padding: EdgeInsets.symmetric(
            horizontal: widget.compact ? 7 : 9,
            vertical: widget.compact ? 5 : 7,
          ),
          decoration: BoxDecoration(
            color: AppColors.fernGreenLight.withValues(alpha: 0.74),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: AppColors.fernGreen.withValues(alpha: 0.18),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: widget.compact ? 34 : 38,
                height: widget.compact ? 34 : 38,
                child: IconButton(
                  tooltip: _playing ? 'Pause voice note' : 'Play voice note',
                  onPressed: _preparing ? null : _togglePlayback,
                  padding: EdgeInsets.zero,
                  style: IconButton.styleFrom(
                    backgroundColor: AppColors.white,
                    foregroundColor: AppColors.fernGreenDark,
                    disabledForegroundColor: AppColors.textTertiary,
                  ),
                  icon: Icon(
                    _playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                    size: widget.compact ? 20 : 23,
                  ),
                ),
              ),
              const SizedBox(width: 7),
              SizedBox(
                width: waveformWidth,
                height: playerHeight,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    AudioFileWaveforms(
                      size: Size(waveformWidth, playerHeight),
                      playerController: _playerController,
                      waveformType: WaveformType.fitWidth,
                      enableSeekGesture: !_preparing,
                      continuousWaveform: true,
                      playerWaveStyle: _voicePlayerWaveStyle,
                    ),
                    if (_preparing || widget.busy)
                      Positioned.fill(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: AppColors.fernGreenLight.withValues(
                              alpha: 0.58,
                            ),
                          ),
                          child: Center(
                            child: SizedBox(
                              width: widget.compact ? 14 : 16,
                              height: widget.compact ? 14 : 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: widget.busy
                                    ? AppColors.charcoal
                                    : AppColors.fernGreenDark,
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 7),
              SizedBox(
                width: widget.compact ? 35 : 39,
                child: Text(
                  total > Duration.zero
                      ? _formatShortDuration(_playing ? current : total)
                      : '0:00',
                  textAlign: TextAlign.right,
                  maxLines: 1,
                  style: AppTypography.textTheme.labelSmall?.copyWith(
                    color: AppColors.fernGreenDark,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _MediaLoadingBox extends StatelessWidget {
  const _MediaLoadingBox({required this.icon});
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final width = _mediaPreviewWidth(context);
    return Container(
      width: width,
      height: width * 0.62,
      decoration: BoxDecoration(
        color: _chatSurface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: AppColors.borderSubtle.withValues(alpha: 0.8),
        ),
      ),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: AppColors.fernGreenDark),
            const SizedBox(height: AppSpacing.sm),
            const SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: AppColors.fernGreen,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MediaErrorBox extends StatelessWidget {
  const _MediaErrorBox({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    final width = _mediaPreviewWidth(context);
    return Container(
      width: width,
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: AppColors.sunsetCoralLight,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Text(
        text,
        style: AppTypography.textTheme.bodySmall?.copyWith(
          color: AppColors.sunsetCoralDark,
        ),
      ),
    );
  }
}

class _TypingIndicator extends StatelessWidget {
  const _TypingIndicator({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 42, bottom: AppSpacing.md),
      child: Row(
        children: [
          const _DotPulse(),
          const SizedBox(width: AppSpacing.sm),
          Text(
            label,
            style: AppTypography.textTheme.bodySmall?.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

class _DotPulse extends StatefulWidget {
  const _DotPulse();

  @override
  State<_DotPulse> createState() => _DotPulseState();
}

class _DotPulseState extends State<_DotPulse>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (_, __) => Row(
        mainAxisSize: MainAxisSize.min,
        children: List.generate(3, (i) {
          final opacity = 0.35 + 0.65 * ((i * 0.22 + _controller.value) % 1);
          return Container(
            width: 6,
            height: 6,
            margin: const EdgeInsets.only(right: 3),
            decoration: BoxDecoration(
              color: AppColors.fernGreen.withValues(
                alpha: opacity.clamp(0.35, 1).toDouble(),
              ),
              shape: BoxShape.circle,
            ),
          );
        }),
      ),
    );
  }
}

class _Composer extends StatelessWidget {
  const _Composer({
    required this.controller,
    required this.sending,
    required this.enabled,
    required this.ttlSeconds,
    required this.onSend,
    required this.onOpenMediaMenu,
    required this.onStartRecording,
    required this.onStopRecording,
    required this.onCancelRecording,
    required this.onSendVoicePreview,
    required this.onDiscardVoicePreview,
    required this.recording,
    required this.recordingSeconds,
    required this.recorderController,
    required this.voicePreviewPath,
    required this.voicePreviewDuration,
    required this.sendingVoiceNote,
  });

  final TextEditingController controller;
  final bool sending;
  final bool enabled;
  final int ttlSeconds;
  final VoidCallback onSend;
  final VoidCallback onOpenMediaMenu;
  final VoidCallback onStartRecording;
  final VoidCallback onStopRecording;
  final Future<void> Function() onCancelRecording;
  final Future<void> Function() onSendVoicePreview;
  final Future<void> Function() onDiscardVoicePreview;
  final bool recording;
  final int recordingSeconds;
  final RecorderController recorderController;
  final String? voicePreviewPath;
  final Duration voicePreviewDuration;
  final bool sendingVoiceNote;

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.paddingOf(context).bottom;
    final compact = MediaQuery.sizeOf(context).width < 380;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: _chatSurface,
        border: Border(
          top: BorderSide(
            color: AppColors.borderSubtle.withValues(alpha: 0.65),
          ),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.045),
            blurRadius: 22,
            offset: const Offset(0, -8),
          ),
        ],
      ),
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          compact ? AppSpacing.sm : AppSpacing.md,
          AppSpacing.xs,
          compact ? AppSpacing.sm : AppSpacing.md,
          AppSpacing.xs + bottom,
        ),
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 220),
          switchInCurve: Curves.easeOutCubic,
          switchOutCurve: Curves.easeInCubic,
          child: voicePreviewPath != null
              ? _VoiceReviewComposer(
                  localPath: voicePreviewPath!,
                  duration: voicePreviewDuration,
                  sending: sendingVoiceNote,
                  onDelete: onDiscardVoicePreview,
                  onSend: onSendVoicePreview,
                )
              : recording
                  ? _RecordingComposer(
                      seconds: recordingSeconds,
                      sending: sending,
                      onCancel: onCancelRecording,
                      onStop: onStopRecording,
                      recorderController: recorderController,
                    )
                  : ValueListenableBuilder<TextEditingValue>(
                      valueListenable: controller,
                      builder: (context, value, _) {
                        final hasText = value.text.trim().isNotEmpty;
                        final actionColor =
                            hasText ? AppColors.charcoal : AppColors.fernGreen;
                        return DecoratedBox(
                          key: const ValueKey('text-composer'),
                          decoration: BoxDecoration(
                            color: AppColors.white,
                            borderRadius: BorderRadius.circular(30),
                            border: Border.all(
                              color: AppColors.borderSubtle
                                  .withValues(alpha: 0.85),
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.045),
                                blurRadius: 24,
                                offset: const Offset(0, 10),
                              ),
                            ],
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(5),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                SizedBox(
                                  width: 42,
                                  height: 42,
                                  child: IconButton(
                                    tooltip: 'Attach media',
                                    onPressed: enabled && !sending
                                        ? onOpenMediaMenu
                                        : null,
                                    style: IconButton.styleFrom(
                                      backgroundColor: AppColors.fernGreenLight
                                          .withValues(alpha: 0.72),
                                      foregroundColor: AppColors.fernGreenDark,
                                      disabledForegroundColor:
                                          AppColors.textTertiary,
                                    ),
                                    icon:
                                        const Icon(Icons.add_rounded, size: 25),
                                  ),
                                ),
                                const SizedBox(width: 4),
                                Expanded(
                                  child: TextField(
                                    controller: controller,
                                    minLines: 1,
                                    maxLines: 5,
                                    enabled: enabled && !sending,
                                    textInputAction: TextInputAction.newline,
                                    cursorColor: AppColors.fernGreen,
                                    maxLength:
                                        SecureRoomService.maxRoomTextCharacters,
                                    maxLengthEnforcement:
                                        MaxLengthEnforcement.enforced,
                                    inputFormatters: [
                                      FilteringTextInputFormatter.deny(
                                        RegExp(
                                          r'[\u0000-\u0008\u000B\u000C\u000E-\u001F\u007F\u202A-\u202E\u2066-\u2069]',
                                        ),
                                      ),
                                    ],
                                    style: AppTypography.textTheme.bodyMedium
                                        ?.copyWith(
                                      color: _softInk,
                                    ),
                                    decoration: InputDecoration(
                                      counterText: '',
                                      hintText: enabled
                                          ? 'Message expires in ${ttlSeconds ~/ 60} min'
                                          : 'Room is destroyed',
                                      hintStyle: AppTypography
                                          .textTheme.bodyMedium
                                          ?.copyWith(
                                        color: AppColors.textTertiary,
                                      ),
                                      border: InputBorder.none,
                                      isDense: true,
                                      contentPadding:
                                          const EdgeInsets.symmetric(
                                        horizontal: AppSpacing.xs,
                                        vertical: 12,
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 4),
                                SizedBox(
                                  width: 44,
                                  height: 44,
                                  child: FilledButton(
                                    onPressed: enabled && !sending
                                        ? (hasText ? onSend : onStartRecording)
                                        : null,
                                    style: FilledButton.styleFrom(
                                      shape: const CircleBorder(),
                                      padding: EdgeInsets.zero,
                                      backgroundColor: actionColor,
                                      foregroundColor: AppColors.white,
                                      disabledBackgroundColor:
                                          AppColors.borderSubtle,
                                    ),
                                    child: sending
                                        ? const SizedBox(
                                            width: 18,
                                            height: 18,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                              color: AppColors.white,
                                            ),
                                          )
                                        : Icon(
                                            hasText
                                                ? Icons.send_rounded
                                                : Icons.mic_rounded,
                                          ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
        ),
      ),
    );
  }
}

class _RecordingComposer extends StatelessWidget {
  const _RecordingComposer({
    required this.seconds,
    required this.sending,
    required this.onCancel,
    required this.onStop,
    required this.recorderController,
  });

  final int seconds;
  final bool sending;
  final Future<void> Function() onCancel;
  final VoidCallback onStop;
  final RecorderController recorderController;

  @override
  Widget build(BuildContext context) {
    final displaySeconds = seconds.clamp(0, 60).toInt();
    return DecoratedBox(
      key: const ValueKey('recording-composer'),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(30),
        border: Border.all(
          color: AppColors.fernGreen.withValues(alpha: 0.26),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.045),
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(5),
        child: Row(
          children: [
            SizedBox(
              width: 42,
              height: 42,
              child: IconButton(
                tooltip: 'Discard voice note',
                onPressed: sending ? null : onCancel,
                style: IconButton.styleFrom(
                  backgroundColor: AppColors.sunsetCoralLight,
                  foregroundColor: AppColors.sunsetCoralDark,
                ),
                icon: const Icon(Icons.delete_outline_rounded),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            const _RecordingPulse(),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: SizedBox(
                height: 38,
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final width = math.max(80.0, constraints.maxWidth);
                    return AudioWaveforms(
                      size: Size(width, 38),
                      recorderController: recorderController,
                      waveStyle: _voiceWaveStyle,
                    );
                  },
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Text(
              '${displaySeconds ~/ 60}:${(displaySeconds % 60).toString().padLeft(2, '0')}',
              style: AppTypography.textTheme.labelLarge?.copyWith(
                color: AppColors.fernGreenDark,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            SizedBox(
              width: 44,
              height: 44,
              child: FilledButton(
                onPressed: sending ? null : onStop,
                style: FilledButton.styleFrom(
                  shape: const CircleBorder(),
                  padding: EdgeInsets.zero,
                  backgroundColor: AppColors.charcoal,
                  foregroundColor: AppColors.white,
                ),
                child: sending
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: AppColors.white,
                        ),
                      )
                    : const Icon(Icons.check_rounded),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _VoiceReviewComposer extends StatelessWidget {
  const _VoiceReviewComposer({
    required this.localPath,
    required this.duration,
    required this.sending,
    required this.onDelete,
    required this.onSend,
  });

  final String localPath;
  final Duration duration;
  final bool sending;
  final Future<void> Function() onDelete;
  final Future<void> Function() onSend;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      key: const ValueKey('voice-review-composer'),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(30),
        border: Border.all(
          color: AppColors.fernGreen.withValues(alpha: 0.22),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.045),
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(5),
        child: Row(
          children: [
            SizedBox(
              width: 42,
              height: 42,
              child: IconButton(
                tooltip: 'Delete voice note',
                onPressed: sending ? null : onDelete,
                style: IconButton.styleFrom(
                  backgroundColor: AppColors.sunsetCoralLight,
                  foregroundColor: AppColors.sunsetCoralDark,
                ),
                icon: const Icon(Icons.delete_outline_rounded),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: _VoiceMessagePlayer(
                localPath: localPath,
                durationMs: duration.inMilliseconds,
                compact: true,
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            SizedBox(
              width: 44,
              height: 44,
              child: FilledButton(
                onPressed: sending ? null : onSend,
                style: FilledButton.styleFrom(
                  shape: const CircleBorder(),
                  padding: EdgeInsets.zero,
                  backgroundColor: AppColors.charcoal,
                  foregroundColor: AppColors.white,
                ),
                child: sending
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: AppColors.white,
                        ),
                      )
                    : const Icon(Icons.send_rounded),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MediaMenuAction extends StatelessWidget {
  const _MediaMenuAction({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < 420;
    return Material(
      color: AppColors.white,
      borderRadius: BorderRadius.circular(20),
      shadowColor: Colors.black.withValues(alpha: 0.08),
      elevation: 0,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: compact ? AppSpacing.md : AppSpacing.xs,
            vertical: AppSpacing.sm,
          ),
          child: compact
              ? Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _MediaMenuIcon(icon: icon),
                    const SizedBox(width: AppSpacing.sm),
                    Text(
                      label,
                      style: AppTypography.textTheme.labelMedium?.copyWith(
                        color: _softInk,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                )
              : Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _MediaMenuIcon(icon: icon),
                    const SizedBox(height: AppSpacing.xs),
                    FittedBox(
                      child: Text(
                        label,
                        style: AppTypography.textTheme.labelSmall?.copyWith(
                          color: _softInk,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}

class _MediaMenuIcon extends StatelessWidget {
  const _MediaMenuIcon({required this.icon});

  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 42,
      height: 42,
      decoration: BoxDecoration(
        color: AppColors.fernGreenLight.withValues(alpha: 0.78),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Icon(icon, color: AppColors.fernGreenDark),
    );
  }
}

class _RecordingPulse extends StatefulWidget {
  const _RecordingPulse();

  @override
  State<_RecordingPulse> createState() => _RecordingPulseState();
}

class _RecordingPulseState extends State<_RecordingPulse>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1180),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (_, __) => Container(
        width: 10 + _controller.value * 4,
        height: 10 + _controller.value * 4,
        decoration: BoxDecoration(
          color: AppColors.fernGreen,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: AppColors.fernGreen.withValues(alpha: 0.32),
              blurRadius: 8 + _controller.value * 8,
            ),
          ],
        ),
      ),
    );
  }
}

class _RoomClosingView extends StatefulWidget {
  const _RoomClosingView({required this.reason});

  final String reason;

  @override
  State<_RoomClosingView> createState() => _RoomClosingViewState();
}

class _RoomClosingViewState extends State<_RoomClosingView>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(color: _chatCanvas),
      child: Center(
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, _) {
            final t = Curves.easeOutCubic.transform(_controller.value);
            return Opacity(
              opacity: t,
              child: Transform.translate(
                offset: Offset(0, 18 * (1 - t)),
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.xxl),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 74,
                        height: 74,
                        decoration: BoxDecoration(
                          color: AppColors.sunsetCoralLight,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color:
                                AppColors.sunsetCoral.withValues(alpha: 0.22),
                          ),
                        ),
                        child: const Icon(
                          Icons.lock_clock_outlined,
                          color: AppColors.sunsetCoralDark,
                          size: 34,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.lg),
                      Text(
                        'Room closed',
                        style: AppTypography.textTheme.titleLarge?.copyWith(
                          color: _softInk,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      Text(
                        widget.reason,
                        textAlign: TextAlign.center,
                        style: AppTypography.textTheme.bodyMedium?.copyWith(
                          color: AppColors.textSecondary,
                          height: 1.35,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _RoomUnavailable extends StatelessWidget {
  const _RoomUnavailable({required this.error, required this.onBack});
  final String error;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.lock_clock_outlined,
              color: AppColors.textTertiary,
              size: 44,
            ),
            const SizedBox(height: AppSpacing.lg),
            Text('Room unavailable', style: AppTypography.textTheme.titleLarge),
            const SizedBox(height: AppSpacing.sm),
            Text(
              error,
              textAlign: TextAlign.center,
              style: AppTypography.textTheme.bodyMedium?.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            FilledButton.icon(
              onPressed: onBack,
              icon: const Icon(Icons.arrow_back_rounded),
              label: const Text('Back to rooms'),
            ),
          ],
        ),
      ),
    );
  }
}
