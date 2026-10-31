// anonymous secure room screens
// signed-out guests use this isolated flow so anonymous rooms never create accounts

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:share_plus/share_plus.dart';

import '../../../../app/theme/colors.dart';
import '../../../../app/theme/spacing.dart';
import '../../../../app/theme/typography.dart';
import '../../../../core/utils/media_file_safety.dart';
import '../../../../core/utils/snack.dart';
import '../../../../shared/widgets/app_bottom_nav.dart';
import '../../data/anonymous_secure_room_service.dart';

class AnonymousRoomEntryScreen extends StatefulWidget {
  const AnonymousRoomEntryScreen({
    super.key,
    this.initialInviteCode,
    this.initialRoomKey,
  });

  final String? initialInviteCode;
  final String? initialRoomKey;

  @override
  State<AnonymousRoomEntryScreen> createState() =>
      _AnonymousRoomEntryScreenState();
}

class _AnonymousRoomEntryScreenState extends State<AnonymousRoomEntryScreen>
    with SingleTickerProviderStateMixin {
  final _service = AnonymousSecureRoomService.instance;
  final _nameCtrl = TextEditingController();
  final _codeCtrl = TextEditingController();
  final _keyCtrl = TextEditingController();
  late final AnimationController _motionCtrl;
  bool _creating = false;
  bool _joining = false;
  int _ttlSeconds = 120;
  int _maxMembers = 2;
  String? _resumableRoomId;

  @override
  void initState() {
    super.initState();
    _motionCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 520),
    )..forward();
    _codeCtrl.text = widget.initialInviteCode ?? '';
    _keyCtrl.text = widget.initialRoomKey ?? '';
    _codeCtrl.addListener(_onInviteFieldsChanged);
    _keyCtrl.addListener(_onInviteFieldsChanged);
    _loadResumableRoom();
  }

  @override
  void dispose() {
    _motionCtrl.dispose();
    _codeCtrl.removeListener(_onInviteFieldsChanged);
    _keyCtrl.removeListener(_onInviteFieldsChanged);
    _nameCtrl.dispose();
    _codeCtrl.dispose();
    _keyCtrl.dispose();
    super.dispose();
  }

  void _onInviteFieldsChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _loadResumableRoom() async {
    if (_service.accountIsSignedIn) return;
    final roomId = await _service.resumableRoomId();
    if (!mounted) return;
    setState(() => _resumableRoomId = roomId);
  }

  bool _applyInviteText(String raw) {
    final invite = AnonymousSecureRoomService.parseInviteText(raw);
    var changed = false;
    if (invite.code != null) {
      _codeCtrl.text = invite.code!;
      changed = true;
    }
    if (invite.key != null && invite.key!.trim().isNotEmpty) {
      _keyCtrl.text = Uri.decodeComponent(invite.key!.trim());
      changed = true;
    }
    return changed;
  }

  Future<void> _pasteInvite() async {
    final clipboard = await Clipboard.getData(Clipboard.kTextPlain);
    if (!mounted) return;
    if (_applyInviteText(clipboard?.text ?? '')) {
      setState(() {});
      showSuccessSnack(context, 'Anonymous invite pasted.');
    } else {
      showErrorSnack(
        context,
        'Clipboard does not contain an anonymous invite.',
      );
    }
  }

  void _clearInvite() {
    _codeCtrl.clear();
    _keyCtrl.clear();
    setState(() {});
  }

  Future<void> _createRoom() async {
    if (_creating || _joining) return;
    setState(() => _creating = true);
    try {
      final created = await _service.createRoom(
        displayName: _nameCtrl.text,
        ttlSeconds: _ttlSeconds,
        maxMembers: _maxMembers,
      );
      if (!mounted) return;
      await _showCreatedSheet(created);
      if (!mounted) return;
      context.go('/anonymous-room/${created.room.id}');
    } catch (e) {
      if (mounted) showErrorSnack(context, _friendlyError(e));
    } finally {
      if (mounted) setState(() => _creating = false);
    }
  }

  Future<void> _joinRoom() async {
    if (_creating || _joining) return;
    _applyInviteText(_codeCtrl.text);
    _applyInviteText(_keyCtrl.text);
    setState(() => _joining = true);
    try {
      final room = await _service.joinRoom(
        inviteCode: _codeCtrl.text,
        roomKey: _keyCtrl.text,
        displayName: _nameCtrl.text,
      );
      if (!mounted) return;
      showSuccessSnack(context, 'Anonymous room opened.');
      context.go('/anonymous-room/${room.id}');
    } catch (e) {
      if (mounted) showErrorSnack(context, _friendlyError(e));
    } finally {
      if (mounted) setState(() => _joining = false);
    }
  }

  Future<void> _showCreatedSheet(CreatedAnonymousSecureRoom created) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: AppColors.white,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) => Padding(
        padding: EdgeInsets.fromLTRB(
          AppSpacing.lg,
          AppSpacing.sm,
          AppSpacing.lg,
          AppSpacing.xl + MediaQuery.paddingOf(sheetContext).bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Anonymous room sealed',
              style: AppTypography.textTheme.headlineSmall,
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'Share this invite once. The key stays in the link fragment and is not stored on EchoProof servers.',
              style: AppTypography.textTheme.bodySmall?.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            _SecretBlock(label: 'Code', value: created.room.inviteCode),
            const SizedBox(height: AppSpacing.sm),
            _SecretBlock(label: 'Secret key', value: created.roomKey),
            const SizedBox(height: AppSpacing.lg),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: created.shareLink));
                      showSuccessSnack(context, 'Anonymous invite copied.');
                    },
                    icon: const Icon(Icons.copy_rounded),
                    label: const Text('Copy'),
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: () => SharePlus.instance.share(
                      ShareParams(text: created.shareLink),
                    ),
                    icon: const Icon(Icons.ios_share_rounded),
                    label: const Text('Share'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _friendlyError(Object error) {
    return error.toString().replaceFirst('Exception: ', '').trim();
  }

  @override
  Widget build(BuildContext context) {
    final signedIn = _service.accountIsSignedIn;
    final width = MediaQuery.sizeOf(context).width;
    final isWide = width >= 760;
    final hasInvite =
        _codeCtrl.text.trim().isNotEmpty ||
        (widget.initialInviteCode?.trim().isNotEmpty ?? false);

    return SwipeNavigationWrapper(
      currentLocation: '/anonymous-room',
      child: Scaffold(
        backgroundColor: const Color(0xFFF3F8F4),
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              padding: EdgeInsets.fromLTRB(
                isWide ? 40 : AppSpacing.lg,
                AppSpacing.lg,
                isWide ? 40 : AppSpacing.lg,
                AppSpacing.xl + MediaQuery.paddingOf(context).bottom,
              ),
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: isWide ? 720 : 480),
                child: AnimatedBuilder(
                  animation: _motionCtrl,
                  builder: (context, child) {
                    final value = Curves.easeOutCubic.transform(
                      _motionCtrl.value,
                    );
                    return Opacity(
                      opacity: value,
                      child: Transform.translate(
                        offset: Offset(0, (1 - value) * 18),
                        child: child,
                      ),
                    );
                  },
                  child: signedIn
                      ? _SignedInAnonymousBlock(
                          onBack: () => context.go('/feed'),
                        )
                      : _AnonymousEntryPanel(
                          nameCtrl: _nameCtrl,
                          codeCtrl: _codeCtrl,
                          keyCtrl: _keyCtrl,
                          creating: _creating,
                          joining: _joining,
                          hasInvite: hasInvite,
                          ttlSeconds: _ttlSeconds,
                          maxMembers: _maxMembers,
                          onTtlChanged: (value) =>
                              setState(() => _ttlSeconds = value),
                          onMaxMembersChanged: (value) =>
                              setState(() => _maxMembers = value),
                          onPaste: _pasteInvite,
                          onCreate: _createRoom,
                          onJoin: _joinRoom,
                          onClearInvite: _clearInvite,
                          onResume: hasInvite || _resumableRoomId == null
                              ? null
                              : () => context.go(
                                  '/anonymous-room/$_resumableRoomId',
                                ),
                          onBack: () => context.go('/login'),
                        ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class AnonymousRoomChatScreen extends StatefulWidget {
  const AnonymousRoomChatScreen({super.key, required this.roomId});

  final String roomId;

  @override
  State<AnonymousRoomChatScreen> createState() =>
      _AnonymousRoomChatScreenState();
}

class _AnonymousRoomChatScreenState extends State<AnonymousRoomChatScreen>
    with WidgetsBindingObserver {
  // give real devices a grace window before closing the room
  // android can pause networking briefly during app switches and screen locks
  static const _peerMissingGrace = Duration(seconds: 90);

  final _service = AnonymousSecureRoomService.instance;
  final _picker = ImagePicker();
  final _textCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  final _pendingMessages = <AnonymousRoomMessage>[];
  Timer? _pollTimer;
  AnonymousRoomState? _state;
  bool _loading = true;
  bool _sending = false;
  bool _leaving = false;
  bool _offline = false;
  bool _sawPeer = false;
  bool _roomEndDialogOpen = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
    _pollTimer = Timer.periodic(
      const Duration(seconds: 2),
      (_) => _load(silent: true),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pollTimer?.cancel();
    _textCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _load(silent: true);
      _pollTimer ??= Timer.periodic(
        const Duration(seconds: 2),
        (_) => _load(silent: true),
      );
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      _pollTimer?.cancel();
      _pollTimer = null;
    }
  }

  Future<void> _load({bool silent = false}) async {
    if (!mounted) return;
    if (!silent) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final state = await _service.loadState(widget.roomId);
      if (!mounted) return;
      final shouldScroll =
          _state == null ||
          state.messages.length + _pendingMessages.length >
              (_state?.messages.length ?? 0);
      setState(() {
        final serverIds = state.messages
            .map((message) => message.clientMessageId)
            .toSet();
        _pendingMessages.removeWhere(
          (message) => serverIds.contains(message.clientMessageId),
        );
        _state = state;
        _loading = false;
        _error = null;
        _offline = false;
      });
      if (shouldScroll) _scrollToEnd();
      _observePeerPresence(state);
    } catch (e) {
      if (!mounted) return;
      final friendly = _friendlyError(e);
      if (_shouldForgetRoom(friendly)) {
        await _service.forgetRoom(widget.roomId);
        if (!mounted) return;
        setState(() {
          _loading = false;
          _error = null;
        });
        await _showRoomEndedDialog(friendly);
        return;
      }
      if (silent && _state != null) {
        setState(() => _offline = true);
        return;
      }
      setState(() {
        _loading = false;
        _error = friendly;
      });
    }
  }

  void _observePeerPresence(AnonymousRoomState state) {
    // the first guest should be able to wait alone for the invite to be used
    // once a peer has joined, their heartbeat becomes part of the room contract
    final peers = state.members
        .where((member) => member.id != state.currentMember.id)
        .toList(growable: false);
    if (peers.isNotEmpty) _sawPeer = true;
    if (!_sawPeer || _roomEndDialogOpen) return;

    final connectedPeer = peers.any((member) {
      final lastSeen = member.lastSeenAt?.toUtc();
      if (lastSeen == null) return true;
      return state.serverNow.difference(lastSeen) <= _peerMissingGrace;
    });
    if (!connectedPeer) {
      _showRoomEndedDialog(
<<<<<<< HEAD
        'The other guest left or went offline, so this anonymous room was closed.',
        closeServerRoom: true,
=======
        'The other guest left or went offline, so this anonymous room was closed.'
>>>>>>> master
      );
    }
  }

  Future<void> _showRoomEndedDialog(
    String message, {
    bool closeServerRoom = false,
  }) async {
    if (_roomEndDialogOpen || !mounted) return;
    _roomEndDialogOpen = true;
    _pollTimer?.cancel();
    _pollTimer = null;

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('Anonymous room closed'),
        content: Text(message),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Back to login'),
          ),
        ],
      ),
    );
    if (!mounted) return;

    if (closeServerRoom) {
      try {
        await _service.leaveRoom(widget.roomId);
      } catch (_) {
        await _service.forgetRoom(widget.roomId);
      }
    }
    if (mounted) context.go('/login');
  }

  Future<void> _send() async {
    if (_sending) return;
    final state = _state;
    if (state == null || !state.room.isActive) return;
    final rawText = _textCtrl.text;
    final text = AnonymousSecureRoomService.sanitizeAnonymousText(rawText);
    if (text.isEmpty) return;
    final clientMessageId = AnonymousSecureRoomService.newClientMessageId();
    setState(() {
      _sending = true;
      _pendingMessages.add(
        AnonymousSecureRoomService.pendingTextMessage(
          roomId: widget.roomId,
          senderMemberId: state.currentMember.id,
          clientMessageId: clientMessageId,
          text: text,
          ttlSeconds: state.room.messageTtlSeconds,
        ),
      );
    });
    _scrollToEnd();
    try {
      _textCtrl.clear();
      final sent = await _service.sendText(
        roomId: widget.roomId,
        text: text,
        ttlSeconds: _state?.room.messageTtlSeconds ?? 120,
        clientMessageId: clientMessageId,
      );
      _replacePendingMessage(clientMessageId, sent);
      unawaited(_load(silent: true));
    } catch (e) {
      if (mounted) {
        _removePendingMessage(clientMessageId);
        showErrorSnack(context, _friendlyError(e));
        _textCtrl.text = rawText;
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _pickMedia(MediaFileKind kind) async {
    final state = _state;
    if (state == null || !state.room.isActive || _sending) return;
    String? clientMessageId;
    try {
      final picked = kind == MediaFileKind.image
          // image_picker re-encodes photos before validation, while videos
          // stay untouched so we never hide a slow transcoding step behind
          // the composer or damage a user's original clip
          ? await _picker.pickImage(
              source: ImageSource.gallery,
              maxWidth: 1280,
              maxHeight: 1280,
              imageQuality: 72,
            )
          : await _picker.pickVideo(
              source: ImageSource.gallery,
              maxDuration: const Duration(seconds: 20),
            );
      if (picked == null) return;
      final validation = await MediaFileSafety.validateLocalFile(
        picked.path,
        expectedKind: kind,
      );
      if (!validation.isValid) {
        if (mounted) {
          showErrorSnack(context, validation.error ?? 'Unsupported media.');
        }
        return;
      }
      final maxBytes = kind == MediaFileKind.video
          ? AnonymousSecureRoomService.maxAnonymousVideoBytes
          : AnonymousSecureRoomService.maxAnonymousImageBytes;
      if (validation.sizeBytes > maxBytes) {
        if (mounted) {
          showErrorSnack(
            context,
            kind == MediaFileKind.video
                ? 'Pick a video under 5 MB. Short clips upload fastest here.'
                : 'Pick a photo under 1 MB. Large images are compressed before this check.',
          );
        }
        return;
      }

      final messageKind = validation.kind == MediaFileKind.video
          ? 'video'
          : validation.extension.toLowerCase() == 'gif'
          ? 'gif'
          : 'image';
      final label = switch (messageKind) {
        'gif' => 'Encrypted GIF',
        'video' => 'Encrypted video',
        _ => 'Encrypted image',
      };
      clientMessageId = AnonymousSecureRoomService.newClientMessageId();
      setState(() {
        _sending = true;
        _pendingMessages.add(
          AnonymousSecureRoomService.pendingMediaMessage(
            roomId: widget.roomId,
            senderMemberId: state.currentMember.id,
            clientMessageId: clientMessageId!,
            kind: messageKind,
            label: label,
            localMediaPath: picked.path,
            ttlSeconds: state.room.messageTtlSeconds,
          ),
        );
      });
      _scrollToEnd();

      final sent = await _service.sendMedia(
        roomId: widget.roomId,
        localPath: picked.path,
        kind: kind,
        ttlSeconds: state.room.messageTtlSeconds,
        clientMessageId: clientMessageId,
      );
      _replacePendingMessage(clientMessageId, sent);
      unawaited(_load(silent: true));
    } catch (e) {
      if (!mounted) return;
      if (clientMessageId != null) _removePendingMessage(clientMessageId);
      showErrorSnack(context, _friendlyError(e));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  void _replacePendingMessage(
    String clientMessageId,
    AnonymousRoomMessage sent,
  ) {
    if (!mounted) return;
    setState(() {
      final index = _pendingMessages.indexWhere(
        (message) => message.clientMessageId == clientMessageId,
      );
      if (index >= 0) {
        _pendingMessages[index] = sent;
      }
    });
  }

  void _removePendingMessage(String clientMessageId) {
    if (!mounted) return;
    setState(() {
      _pendingMessages.removeWhere(
        (message) => message.clientMessageId == clientMessageId,
      );
    });
  }

  Future<void> _leave() async {
    if (_leaving) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Leave anonymous room?'),
        content: const Text(
          'Leaving destroys this anonymous room for everyone and removes live messages.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Stay'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Leave'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    setState(() => _leaving = true);
    try {
      await _service.leaveRoom(widget.roomId);
      if (!mounted) return;
      context.go('/login');
    } catch (e) {
      if (mounted) showErrorSnack(context, _friendlyError(e));
    } finally {
      if (mounted) setState(() => _leaving = false);
    }
  }

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollCtrl.hasClients) return;
      _scrollCtrl.animateTo(
        _scrollCtrl.position.maxScrollExtent,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
      );
    });
  }

  String _friendlyError(Object error) =>
      error.toString().replaceFirst('Exception: ', '').trim();

  bool _shouldForgetRoom(String message) {
    final lower = message.toLowerCase();
    return lower.contains('not found') ||
        lower.contains('destroyed') ||
        lower.contains('expired') ||
        lower.contains('credentials are missing');
  }

  List<AnonymousRoomMessage> _mergedMessages(AnonymousRoomState state) {
    final serverIds = state.messages
        .map((message) => message.clientMessageId)
        .toSet();
    final merged = <AnonymousRoomMessage>[
      ...state.messages,
      ..._pendingMessages.where(
        (message) => !serverIds.contains(message.clientMessageId),
      ),
    ];
    merged.sort((a, b) => a.createdAt.compareTo(b.createdAt));
    return merged;
  }

  @override
  Widget build(BuildContext context) {
    final state = _state;
    final bottom = MediaQuery.paddingOf(context).bottom;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) context.go('/anonymous-room');
      },
      child: Scaffold(
        backgroundColor: const Color(0xFFF7FBF6),
        body: SafeArea(
          bottom: false,
          child: Column(
            children: [
              _AnonymousRoomTopBar(
                state: state,
                offline: _offline,
                leaving: _leaving,
                onBack: () => context.go('/anonymous-room'),
                onCopy: state == null
                    ? null
                    : () {
                        Clipboard.setData(
                          ClipboardData(text: state.room.inviteCode),
                        );
                        showSuccessSnack(context, 'Code copied.');
                      },
                onLeave: _leave,
              ),
              Expanded(
                child: _loading
                    ? const _AnonymousRoomSkeleton()
                    : _error != null
                    ? _AnonymousRoomError(
                        message: _error!,
                        onBack: () => context.go('/anonymous-room'),
                      )
                    : Column(
                        children: [
                          _AnonymousSecurityStrip(state: state!),
                          Expanded(
                            child: Builder(
                              builder: (context) {
                                final messages = _mergedMessages(state);
                                return ListView.builder(
                                  controller: _scrollCtrl,
                                  keyboardDismissBehavior:
                                      ScrollViewKeyboardDismissBehavior.onDrag,
                                  padding: const EdgeInsets.fromLTRB(
                                    AppSpacing.lg,
                                    AppSpacing.md,
                                    AppSpacing.lg,
                                    AppSpacing.lg,
                                  ),
                                  itemCount: messages.length,
                                  itemBuilder: (context, index) {
                                    final message = messages[index];
                                    final sender = state.members.firstWhere(
                                      (m) => m.id == message.senderMemberId,
                                      orElse: () => AnonymousRoomMember(
                                        id: message.senderMemberId,
                                        role: 'member',
                                        displayName: 'Guest',
                                        avatarSeed: message.senderMemberId,
                                        joinedAt: message.createdAt,
                                      ),
                                    );
                                    return _AnonymousMessageBubble(
                                      message: message,
                                      sender: sender,
                                      mine:
                                          message.senderMemberId ==
                                          state.currentMember.id,
                                    );
                                  },
                                );
                              },
                            ),
                          ),
                          _AnonymousComposer(
                            controller: _textCtrl,
                            sending: _sending,
                            enabled: state.room.isActive,
                            onSend: _send,
                            onPickImage: () => _pickMedia(MediaFileKind.image),
                            onPickVideo: () => _pickMedia(MediaFileKind.video),
                            bottomPadding: bottom,
                          ),
                        ],
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AnonymousRoomTopBar extends StatelessWidget {
  const _AnonymousRoomTopBar({
    required this.state,
    required this.offline,
    required this.leaving,
    required this.onBack,
    required this.onCopy,
    required this.onLeave,
  });

  final AnonymousRoomState? state;
  final bool offline;
  final bool leaving;
  final VoidCallback onBack;
  final VoidCallback? onCopy;
  final VoidCallback onLeave;

  @override
  Widget build(BuildContext context) {
    final room = state?.room;
    final status = room == null
        ? 'Opening'
        : offline
        ? 'Reconnecting'
        : room.friendlyPresenceLabel;
    return Container(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.sm,
        AppSpacing.sm,
        AppSpacing.sm,
        AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: const Color(0xFFF7FBF6).withValues(alpha: 0.96),
        border: Border(
          bottom: BorderSide(
            color: AppColors.fernGreen.withValues(alpha: 0.10),
          ),
        ),
      ),
      child: Row(
        children: [
          IconButton(
            tooltip: 'Back',
            onPressed: onBack,
            icon: const Icon(Icons.arrow_back_rounded),
          ),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  room?.inviteCode ?? 'Anonymous room',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w900,
                    color: const Color(0xFF173B34),
                  ),
                ),
                const SizedBox(height: 1),
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        '$status • E2EE',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTypography.textTheme.labelSmall?.copyWith(
                          color: offline
                              ? AppColors.sunsetCoralDark
                              : AppColors.textSecondary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    if (room != null) ...[
                      const SizedBox(width: 6),
                      Container(
                        width: 6,
                        height: 6,
                        decoration: BoxDecoration(
                          color: offline
                              ? AppColors.sunsetCoral
                              : AppColors.fernGreen,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Copy code',
            onPressed: onCopy,
            icon: const Icon(Icons.copy_rounded),
          ),
          IconButton(
            tooltip: 'Leave room',
            onPressed: leaving ? null : onLeave,
            icon: const Icon(Icons.logout_rounded),
          ),
        ],
      ),
    );
  }
}

class _AnonymousEntryPanel extends StatelessWidget {
  const _AnonymousEntryPanel({
    required this.nameCtrl,
    required this.codeCtrl,
    required this.keyCtrl,
    required this.creating,
    required this.joining,
    required this.hasInvite,
    required this.ttlSeconds,
    required this.maxMembers,
    required this.onTtlChanged,
    required this.onMaxMembersChanged,
    required this.onPaste,
    required this.onCreate,
    required this.onJoin,
    required this.onClearInvite,
    required this.onResume,
    required this.onBack,
  });

  final TextEditingController nameCtrl;
  final TextEditingController codeCtrl;
  final TextEditingController keyCtrl;
  final bool creating;
  final bool joining;
  final bool hasInvite;
  final int ttlSeconds;
  final int maxMembers;
  final ValueChanged<int> onTtlChanged;
  final ValueChanged<int> onMaxMembersChanged;
  final VoidCallback onPaste;
  final VoidCallback onCreate;
  final VoidCallback onJoin;
  final VoidCallback onClearInvite;
  final VoidCallback? onResume;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.white.withValues(alpha: 0.96),
        borderRadius: BorderRadius.circular(28),
        boxShadow: [
          BoxShadow(
            color: AppColors.fernGreenDark.withValues(alpha: 0.10),
            blurRadius: 38,
            offset: const Offset(0, 22),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            IconButton(
              tooltip: 'Back to login',
              onPressed: onBack,
              icon: const Icon(Icons.arrow_back_rounded),
            ),
            const SizedBox(height: AppSpacing.sm),
            const _AnonymousPulseMark(),
            const SizedBox(height: AppSpacing.lg),
            Text(
              'Enter quietly',
              style: AppTypography.josefin(
                size: 32,
                weight: FontWeight.w800,
                color: const Color(0xFF183D35),
                height: 1.02,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'Use a temporary name. No account is created, and anonymous codes stay separate from account rooms.',
              style: AppTypography.textTheme.bodyMedium?.copyWith(
                color: AppColors.textSecondary,
                height: 1.4,
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 180),
              child: onResume == null
                  ? const SizedBox.shrink(key: ValueKey('no-resume-room'))
                  : Padding(
                      key: const ValueKey('resume-room'),
                      padding: const EdgeInsets.only(bottom: AppSpacing.md),
                      child: OutlinedButton.icon(
                        onPressed: creating || joining ? null : onResume,
                        icon: const Icon(Icons.history_rounded),
                        label: const Text('Continue last anonymous room'),
                      ),
                    ),
            ),
            _AnonTextField(
              controller: nameCtrl,
              label: 'Temporary name',
              hint: 'display name',
              icon: Icons.badge_outlined,
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: AppSpacing.md),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 220),
              child: hasInvite
                  ? const SizedBox.shrink(key: ValueKey('join-settings'))
                  : Column(
                      key: const ValueKey('create-settings'),
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _AnonChoiceRow(
                          label: 'Messages live for',
                          value: ttlSeconds,
                          options: const {120: '2 min', 300: '5 min'},
                          onChanged: creating || joining ? null : onTtlChanged,
                        ),
                        const SizedBox(height: AppSpacing.sm),
                        _AnonChoiceRow(
                          label: 'Room size',
                          value: maxMembers,
                          options: const {2: '2 guests', 3: '3 guests'},
                          onChanged: creating || joining
                              ? null
                              : onMaxMembersChanged,
                        ),
                        const SizedBox(height: AppSpacing.md),
                      ],
                    ),
            ),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 220),
              child: hasInvite
                  ? Column(
                      key: const ValueKey('join-fields'),
                      children: [
                        _AnonTextField(
                          controller: codeCtrl,
                          label: 'Anonymous code',
                          hint: 'anon-xxxxxxxxxx',
                          icon: Icons.tag_rounded,
                          textInputAction: TextInputAction.next,
                        ),
                        const SizedBox(height: AppSpacing.md),
                        _AnonTextField(
                          controller: keyCtrl,
                          label: 'Secret key',
                          hint: 'from the invite link',
                          icon: Icons.key_rounded,
                          textInputAction: TextInputAction.done,
                        ),
                        const SizedBox(height: AppSpacing.sm),
                      ],
                    )
                  : const SizedBox.shrink(key: ValueKey('create-copy')),
            ),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: joining || creating ? null : onPaste,
                    icon: const Icon(Icons.content_paste_rounded),
                    label: const Text('Paste invite'),
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: joining || creating
                        ? null
                        : hasInvite
                        ? onJoin
                        : onCreate,
                    icon: creating || joining
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Icon(
                            hasInvite
                                ? Icons.login_rounded
                                : Icons.add_moderator_rounded,
                          ),
                    label: Text(hasInvite ? 'Join' : 'Create'),
                  ),
                ),
              ],
            ),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 180),
              child: hasInvite
                  ? Padding(
                      key: const ValueKey('clear-invite'),
                      padding: const EdgeInsets.only(top: AppSpacing.md),
                      child: TextButton.icon(
                        onPressed: creating || joining ? null : onClearInvite,
                        icon: const Icon(Icons.auto_awesome_rounded),
                        label: const Text(
                          'Create a fresh anonymous room instead',
                        ),
                      ),
                    )
                  : const SizedBox.shrink(key: ValueKey('no-clear-invite')),
            ),
          ],
        ),
      ),
    );
  }
}

class _AnonymousSecurityStrip extends StatelessWidget {
  const _AnonymousSecurityStrip({required this.state});

  final AnonymousRoomState state;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(AppSpacing.lg, 0, AppSpacing.lg, 0),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.white.withValues(alpha: 0.86),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.fernGreenLight),
      ),
      child: Row(
        children: [
          _AnonAvatar(
            seed: state.currentMember.avatarSeed,
            label: state.currentMember.displayName,
            size: 34,
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              '${state.currentMember.displayName} • ${state.room.friendlyPresenceLabel} • expires in ${state.room.messageTtlSeconds ~/ 60} min',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: AppTypography.textTheme.bodySmall?.copyWith(
                color: AppColors.textSecondary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const Icon(Icons.lock_rounded, size: 18, color: AppColors.fernGreen),
        ],
      ),
    );
  }
}

class _AnonymousComposer extends StatelessWidget {
  const _AnonymousComposer({
    required this.controller,
    required this.sending,
    required this.enabled,
    required this.onSend,
    required this.onPickImage,
    required this.onPickVideo,
    required this.bottomPadding,
  });

  final TextEditingController controller;
  final bool sending;
  final bool enabled;
  final VoidCallback onSend;
  final VoidCallback onPickImage;
  final VoidCallback onPickVideo;
  final double bottomPadding;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 20,
            offset: const Offset(0, -8),
          ),
        ],
      ),
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          AppSpacing.lg,
          AppSpacing.md,
          AppSpacing.lg,
          AppSpacing.md + bottomPadding,
        ),
        child: Row(
          children: [
            IconButton.filledTonal(
              tooltip: 'Attach media',
              onPressed: enabled && !sending
                  ? () => _showAttachSheet(context)
                  : null,
              icon: const Icon(Icons.add_photo_alternate_rounded),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: TextField(
                controller: controller,
                enabled: enabled,
                minLines: 1,
                maxLines: 5,
                textInputAction: TextInputAction.newline,
                decoration: InputDecoration(
                  hintText: 'Encrypted message',
                  filled: true,
                  fillColor: AppColors.fernGreenLight.withValues(alpha: 0.45),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(18),
                    borderSide: BorderSide.none,
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(18),
                    borderSide: const BorderSide(
                      color: AppColors.fernGreen,
                      width: 1.4,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            FilledButton(
              onPressed: enabled && !sending ? onSend : null,
              style: FilledButton.styleFrom(
                shape: const CircleBorder(),
                padding: const EdgeInsets.all(16),
              ),
              child: sending
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.arrow_upward_rounded),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showAttachSheet(BuildContext context) {
    return showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      useSafeArea: true,
      backgroundColor: AppColors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) => Center(
        heightFactor: 1,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              AppSpacing.lg,
              AppSpacing.sm,
              AppSpacing.lg,
              AppSpacing.lg + MediaQuery.paddingOf(sheetContext).bottom,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  leading: const Icon(Icons.image_rounded),
                  title: const Text('Photo'),
                  subtitle: const Text('Encrypted, 1 MB max'),
                  onTap: () {
                    Navigator.pop(sheetContext);
                    onPickImage();
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.movie_creation_outlined),
                  title: const Text('Short video'),
                  subtitle: const Text('Encrypted, 5 MB max'),
                  onTap: () {
                    Navigator.pop(sheetContext);
                    onPickVideo();
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _AnonymousMessageBubble extends StatelessWidget {
  const _AnonymousMessageBubble({
    required this.message,
    required this.sender,
    required this.mine,
  });

  final AnonymousRoomMessage message;
  final AnonymousRoomMember sender;
  final bool mine;

  @override
  Widget build(BuildContext context) {
    final bubbleColor = mine ? AppColors.fernGreenDark : AppColors.white;
    final textColor = mine ? AppColors.white : AppColors.charcoal;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 240),
      curve: Curves.easeOutCubic,
      builder: (context, value, child) => Opacity(
        opacity: value,
        child: Transform.translate(
          offset: Offset(0, (1 - value) * 8),
          child: child,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.only(bottom: AppSpacing.md),
        child: Row(
          mainAxisAlignment: mine
              ? MainAxisAlignment.end
              : MainAxisAlignment.start,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            if (!mine) ...[
              _AnonAvatar(
                seed: sender.avatarSeed,
                label: sender.displayName,
                size: 34,
              ),
              const SizedBox(width: AppSpacing.sm),
            ],
            Flexible(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: bubbleColor,
                  borderRadius: BorderRadius.only(
                    topLeft: const Radius.circular(18),
                    topRight: const Radius.circular(18),
                    bottomLeft: Radius.circular(mine ? 18 : 5),
                    bottomRight: Radius.circular(mine ? 5 : 18),
                  ),
                  border: mine
                      ? null
                      : Border.all(color: AppColors.borderSubtle),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.md,
                    vertical: AppSpacing.sm,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (!mine)
                        Text(
                          sender.displayName,
                          style: AppTypography.textTheme.labelMedium?.copyWith(
                            color: AppColors.fernGreenDark,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      if (message.hasMedia) ...[
                        if (!mine) const SizedBox(height: 4),
                        _AnonymousMediaPreview(message: message, mine: mine),
                        const SizedBox(height: 6),
                      ],
                      Text(
                        message.integrityOk
                            ? message.text ?? ''
                            : 'Message could not be verified',
                        style: AppTypography.textTheme.bodyMedium?.copyWith(
                          color: message.integrityOk
                              ? textColor.withValues(
                                  alpha: message.pending ? 0.72 : 1,
                                )
                              : AppColors.sunsetCoralDark,
                          height: 1.32,
                        ),
                      ),
                      if (message.pending)
                        Padding(
                          padding: const EdgeInsets.only(top: 3),
                          child: Text(
                            'sending...',
                            style: AppTypography.textTheme.labelSmall?.copyWith(
                              color: mine
                                  ? AppColors.white.withValues(alpha: 0.68)
                                  : AppColors.textSecondary,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
            if (mine) ...[
              const SizedBox(width: AppSpacing.sm),
              const Icon(
                Icons.verified_user_rounded,
                size: 14,
                color: AppColors.fernGreen,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _AnonymousMediaPreview extends StatefulWidget {
  const _AnonymousMediaPreview({required this.message, required this.mine});

  final AnonymousRoomMessage message;
  final bool mine;

  @override
  State<_AnonymousMediaPreview> createState() => _AnonymousMediaPreviewState();
}

class _AnonymousMediaPreviewState extends State<_AnonymousMediaPreview> {
  Future<Uint8List>? _future;
  String? _futureKey;

  @override
  void initState() {
    super.initState();
    _prepareFuture();
  }

  @override
  void didUpdateWidget(covariant _AnonymousMediaPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    final oldKey = _mediaKey(oldWidget.message);
    if (oldKey != _mediaKey(widget.message)) _prepareFuture();
  }

  String _mediaKey(AnonymousRoomMessage message) =>
      message.localMediaPath ?? message.mediaPath ?? message.id;

  void _prepareFuture() {
    final message = widget.message;
    if (message.isVideo) return;
    final key = _mediaKey(message);
    if (_futureKey == key && _future != null) return;
    _futureKey = key;
    _future = AnonymousSecureRoomService.instance.decryptMedia(message);
  }

  @override
  Widget build(BuildContext context) {
    final message = widget.message;
    final mine = widget.mine;
    if (message.isVideo) {
      return _AnonymousVideoTile(message: message, mine: mine);
    }
    return FutureBuilder<Uint8List>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return _AnonymousMediaShell(
            mine: mine,
            child: const Center(
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          );
        }
        final bytes = snapshot.data;
        if (bytes == null || snapshot.hasError) {
          return _AnonymousMediaShell(
            mine: mine,
            child: const Center(child: Icon(Icons.broken_image_rounded)),
          );
        }
        return ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 260, maxHeight: 220),
            child: Image.memory(
              bytes,
              fit: BoxFit.cover,
              gaplessPlayback: true,
              filterQuality: FilterQuality.medium,
            ),
          ),
        );
      },
    );
  }
}

class _AnonymousVideoTile extends StatelessWidget {
  const _AnonymousVideoTile({required this.message, required this.mine});

  final AnonymousRoomMessage message;
  final bool mine;

  @override
  Widget build(BuildContext context) {
    final size = message.mediaSizeBytes == null
        ? null
        : _formatBytes(message.mediaSizeBytes!);
    return _AnonymousMediaShell(
      mine: mine,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.play_circle_fill_rounded, size: 30),
          const SizedBox(width: AppSpacing.sm),
          Flexible(
            child: Text(
              size == null ? 'Encrypted video' : 'Encrypted video • $size',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTypography.textTheme.labelMedium?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AnonymousMediaShell extends StatelessWidget {
  const _AnonymousMediaShell({required this.mine, required this.child});

  final bool mine;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 220,
      height: 132,
      decoration: BoxDecoration(
        color: mine
            ? AppColors.white.withValues(alpha: 0.14)
            : AppColors.fernGreenLight.withValues(alpha: 0.42),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: mine
              ? AppColors.white.withValues(alpha: 0.16)
              : AppColors.fernGreen.withValues(alpha: 0.12),
        ),
      ),
      alignment: Alignment.center,
      child: child,
    );
  }
}

String _formatBytes(int bytes) {
  if (bytes >= 1024 * 1024) {
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
  if (bytes >= 1024) return '${(bytes / 1024).round()} KB';
  return '$bytes B';
}

class _AnonAvatar extends StatelessWidget {
  const _AnonAvatar({
    required this.seed,
    required this.label,
    required this.size,
  });

  final String seed;
  final String label;
  final double size;

  @override
  Widget build(BuildContext context) {
    final hash = seed.codeUnits.fold<int>(
      0,
      (a, b) => (a * 31 + b) & 0x7fffffff,
    );
    final hue = (hash % 68) / 68.0;
    final color = HSVColor.fromAHSV(1, 120 + hue * 70, 0.42, 0.72).toColor();
    final initial = label.trim().isEmpty ? '?' : label.trim()[0].toUpperCase();
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [color.withValues(alpha: 0.70), color],
        ),
      ),
      alignment: Alignment.center,
      child: Text(
        initial,
        style: AppTypography.josefin(
          size: size * 0.42,
          weight: FontWeight.w800,
          color: AppColors.white,
        ),
      ),
    );
  }
}

class _AnonymousPulseMark extends StatefulWidget {
  const _AnonymousPulseMark();

  @override
  State<_AnonymousPulseMark> createState() => _AnonymousPulseMarkState();
}

class _AnonymousPulseMarkState extends State<_AnonymousPulseMark>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 86,
      height: 86,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) => CustomPaint(
          painter: _AnonymousPulsePainter(progress: _controller.value),
          child: const Center(
            child: Icon(
              Icons.visibility_off_rounded,
              color: AppColors.fernGreenDark,
              size: 34,
            ),
          ),
        ),
      ),
    );
  }
}

class _AnonymousPulsePainter extends CustomPainter {
  const _AnonymousPulsePainter({required this.progress});

  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final base = Paint()
      ..color = AppColors.fernGreenLight
      ..style = PaintingStyle.fill;
    canvas.drawCircle(center, size.shortestSide * 0.36, base);

    final ring = Paint()
      ..color = AppColors.fernGreen.withValues(alpha: 0.28 * (1 - progress))
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    canvas.drawCircle(
      center,
      size.shortestSide * (0.34 + progress * 0.16),
      ring,
    );
  }

  @override
  bool shouldRepaint(covariant _AnonymousPulsePainter oldDelegate) =>
      progress != oldDelegate.progress;
}

class _AnonChoiceRow extends StatelessWidget {
  const _AnonChoiceRow({
    required this.label,
    required this.value,
    required this.options,
    required this.onChanged,
  });

  final String label;
  final int value;
  final Map<int, String> options;
  final ValueChanged<int>? onChanged;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 380;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: AppTypography.textTheme.labelMedium?.copyWith(
                color: AppColors.textSecondary,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: compact ? 6 : AppSpacing.sm,
              runSpacing: 6,
              children: options.entries.map((entry) {
                final selected = value == entry.key;
                return ChoiceChip(
                  selected: selected,
                  label: Text(entry.value),
                  onSelected: onChanged == null
                      ? null
                      : (_) => onChanged!(entry.key),
                  selectedColor: AppColors.fernGreenLight,
                  checkmarkColor: AppColors.fernGreenDark,
                  labelStyle: AppTypography.textTheme.labelMedium?.copyWith(
                    color: selected
                        ? AppColors.fernGreenDark
                        : AppColors.textSecondary,
                    fontWeight: FontWeight.w800,
                  ),
                  side: BorderSide(
                    color: selected
                        ? AppColors.fernGreen.withValues(alpha: 0.32)
                        : AppColors.borderSubtle,
                  ),
                );
              }).toList(),
            ),
          ],
        );
      },
    );
  }
}

class _AnonTextField extends StatelessWidget {
  const _AnonTextField({
    required this.controller,
    required this.label,
    required this.hint,
    required this.icon,
    required this.textInputAction,
  });

  final TextEditingController controller;
  final String label;
  final String hint;
  final IconData icon;
  final TextInputAction textInputAction;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      textInputAction: textInputAction,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        prefixIcon: Icon(icon),
        filled: true,
        fillColor: AppColors.surfaceSecondary,
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: const BorderSide(color: AppColors.borderSubtle),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: const BorderSide(color: AppColors.fernGreen, width: 1.4),
        ),
      ),
    );
  }
}

class _SecretBlock extends StatelessWidget {
  const _SecretBlock({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.surfaceSecondary,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.borderSubtle),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: AppTypography.textTheme.labelMedium),
                  const SizedBox(height: 2),
                  Text(
                    value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
            IconButton(
              tooltip: 'Copy $label',
              onPressed: () {
                Clipboard.setData(ClipboardData(text: value));
                showSuccessSnack(context, '$label copied.');
              },
              icon: const Icon(Icons.copy_rounded),
            ),
          ],
        ),
      ),
    );
  }
}

class _SignedInAnonymousBlock extends StatelessWidget {
  const _SignedInAnonymousBlock({required this.onBack});

  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(28),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.account_circle_outlined,
              size: 42,
              color: AppColors.fernGreenDark,
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              'Anonymous rooms are signed-out only',
              textAlign: TextAlign.center,
              style: AppTypography.textTheme.titleLarge,
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'Use normal secure rooms from your account, or sign out before opening an anonymous invite.',
              textAlign: TextAlign.center,
              style: AppTypography.textTheme.bodySmall?.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            FilledButton(onPressed: onBack, child: const Text('Back to app')),
          ],
        ),
      ),
    );
  }
}

class _AnonymousRoomSkeleton extends StatelessWidget {
  const _AnonymousRoomSkeleton();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0.65, end: 1),
        duration: const Duration(milliseconds: 720),
        curve: Curves.easeInOut,
        builder: (context, value, child) => Opacity(
          opacity: value,
          child: Transform.scale(scale: 0.98 + value * 0.02, child: child),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const _AnonymousPulseMark(),
            const SizedBox(height: AppSpacing.md),
            Text(
              'Opening encrypted space',
              style: AppTypography.textTheme.titleMedium,
            ),
          ],
        ),
      ),
    );
  }
}

class _AnonymousRoomError extends StatelessWidget {
  const _AnonymousRoomError({required this.message, required this.onBack});

  final String message;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.lock_reset_rounded,
              size: 42,
              color: AppColors.sunsetCoral,
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              message,
              textAlign: TextAlign.center,
              style: AppTypography.textTheme.bodyMedium,
            ),
            const SizedBox(height: AppSpacing.lg),
            FilledButton(onPressed: onBack, child: const Text('Back')),
          ],
        ),
      ),
    );
  }
}
