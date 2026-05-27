import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';

import '../../../../app/app.dart';
import '../../../../app/theme/colors.dart';
import '../../../../app/theme/spacing.dart';
import '../../../../app/theme/typography.dart';
import '../../../../core/utils/snack.dart';
import '../../../../shared/widgets/app_bottom_nav.dart';
import '../../data/secure_room_service.dart';

class RoomsScreen extends StatefulWidget {
  const RoomsScreen({
    super.key,
    this.initialInviteCode,
    this.initialRoomKey,
  });

  final String? initialInviteCode;
  final String? initialRoomKey;

  @override
  State<RoomsScreen> createState() => _RoomsScreenState();
}

class _RoomsScreenState extends State<RoomsScreen> {
  final _service = SecureRoomService.instance;
  final _codeCtrl = TextEditingController();
  final _keyCtrl = TextEditingController();
  int _ttlSeconds = 120;
  int _maxMembers = 2;
  bool _waitForMembers = false;
  int _waitingTimeoutSeconds = 180;
  bool _creating = false;
  bool _joining = false;
  bool _autoJoinAttempted = false;
  bool _initialJoinSheetShown = false;

  @override
  void initState() {
    super.initState();
    _codeCtrl.text = widget.initialInviteCode?.trim().toUpperCase() ?? '';
    _keyCtrl.text = widget.initialRoomKey?.trim() ?? '';
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _service.loadRooms();
      _maybeAutoJoin();
      _maybeShowPartialInviteSheet();
    });
  }

  @override
  void didUpdateWidget(covariant RoomsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialInviteCode != widget.initialInviteCode ||
        oldWidget.initialRoomKey != widget.initialRoomKey) {
      _autoJoinAttempted = false;
      _codeCtrl.text = widget.initialInviteCode?.trim().toUpperCase() ?? '';
      _keyCtrl.text = widget.initialRoomKey?.trim() ?? '';
      _maybeAutoJoin();
      _maybeShowPartialInviteSheet();
    }
  }

  @override
  void dispose() {
    _codeCtrl.dispose();
    _keyCtrl.dispose();
    super.dispose();
  }

  Future<void> _maybeAutoJoin() async {
    if (_autoJoinAttempted) return;
    if (_codeCtrl.text.trim().isEmpty || _keyCtrl.text.trim().isEmpty) return;
    _autoJoinAttempted = true;
    await _join(auto: true);
  }

  void _maybeShowPartialInviteSheet() {
    if (_initialJoinSheetShown || _autoJoinAttempted || !mounted) return;
    if (_codeCtrl.text.trim().isEmpty && _keyCtrl.text.trim().isEmpty) return;
    _initialJoinSheetShown = true;
    _showJoinRoomSheet();
  }

  bool _applyInviteText(String raw) {
    final text = raw.trim();
    if (text.isEmpty) return false;

    String? code;
    String? key;
    final uri = Uri.tryParse(text);
    if (uri != null) {
      code = uri.queryParameters['code'];
      if (uri.fragment.isNotEmpty) {
        try {
          key = Uri.splitQueryString(uri.fragment)['key'];
        } catch (_) {
          key = null;
        }
      }
    }

    code ??= RegExp(r'\b[A-Z2-9]{8}\b', caseSensitive: false)
        .firstMatch(text)
        ?.group(0);
    key ??= RegExp(r'key=([^&\s]+)').firstMatch(text)?.group(1);

    var changed = false;
    if (code != null && code.trim().isNotEmpty) {
      _codeCtrl.text = code.trim().toUpperCase();
      changed = true;
    }
    if (key != null && key.trim().isNotEmpty) {
      _keyCtrl.text = Uri.decodeComponent(key.trim());
      changed = true;
    }
    return changed;
  }

  Future<void> _pasteInvite(StateSetter sheetSetState) async {
    final clipboard = await Clipboard.getData(Clipboard.kTextPlain);
    if (!mounted) return;
    final pasted = clipboard?.text ?? '';
    if (_applyInviteText(pasted)) {
      sheetSetState(() {});
      showSuccessSnack(context, 'Invite pasted.');
    } else {
      showErrorSnack(context, 'Clipboard does not contain a room invite.');
    }
  }

  Future<void> _createRoom() async {
    if (_creating) return;
    setState(() => _creating = true);
    try {
      final created = await _service.createRoom(
        ttlSeconds: _ttlSeconds,
        maxMembers: _maxMembers,
        waitForMembers: _waitForMembers,
        waitingTimeoutSeconds: _waitingTimeoutSeconds,
      );
      if (!mounted) return;
      await _showCreatedSheet(created);
      if (!mounted) return;
      context.push('/rooms/${created.room.id}');
    } catch (e) {
      if (mounted) showErrorSnack(context, _friendlyError(e));
    } finally {
      if (mounted) setState(() => _creating = false);
    }
  }

  Future<void> _join({bool auto = false}) async {
    if (_joining) return;
    _applyInviteText(_codeCtrl.text);
    _applyInviteText(_keyCtrl.text);
    setState(() => _joining = true);
    try {
      final room = await _service.joinRoom(
        inviteCode: _codeCtrl.text,
        roomKey: _keyCtrl.text,
      );
      if (!mounted) return;
      showSuccessSnack(
        context,
        auto ? 'Secure room opened.' : 'Joined secure room.',
      );
      context.go('/rooms/${room.id}');
    } catch (e) {
      if (mounted) showErrorSnack(context, _friendlyError(e));
    } finally {
      if (mounted) setState(() => _joining = false);
    }
  }

  Future<void> _showCreatedSheet(CreatedSecureRoom created) {
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
          AppSpacing.xl,
          AppSpacing.lg,
          AppSpacing.xl,
          AppSpacing.xl + MediaQuery.paddingOf(sheetContext).bottom,
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
            Text('Room sealed', style: AppTypography.textTheme.headlineSmall),
            const SizedBox(height: AppSpacing.sm),
            Text(
              created.room.waitForMembers
                  ? 'Share the invite. The room opens when all ${created.room.maxMembers} members join, or the wait timer decides the room outcome.'
                  : 'Share the room link or send the code plus secret key. The key is not stored on EchoProof servers.',
              style: AppTypography.textTheme.bodySmall?.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            _SecretValue(
              label: 'Room code',
              value: created.room.inviteCode,
              onCopy: () => _copy(created.room.inviteCode, 'Room code copied'),
            ),
            const SizedBox(height: AppSpacing.sm),
            _SecretValue(
              label: 'Secret key',
              value: created.roomKey,
              compact: true,
              onCopy: () => _copy(created.roomKey, 'Secret key copied'),
            ),
            const SizedBox(height: AppSpacing.lg),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _copy(created.shareLink, 'Invite copied'),
                    icon: const Icon(Icons.copy_rounded),
                    label: const Text('Copy invite'),
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

  Future<void> _showCreateRoomSheet() {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: AppColors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, sheetSetState) {
            return SingleChildScrollView(
              padding: _sheetPadding(sheetContext),
              child: _CreateRoomPanel(
                ttlSeconds: _ttlSeconds,
                maxMembers: _maxMembers,
                waitForMembers: _waitForMembers,
                waitingTimeoutSeconds: _waitingTimeoutSeconds,
                creating: _creating,
                retryAfter: _service.localCreateRetryAfter,
                remainingCreates: _service.localCreatesRemainingToday,
                onTtlChanged: (value) {
                  setState(() => _ttlSeconds = value);
                  sheetSetState(() {});
                },
                onMaxMembersChanged: (value) {
                  setState(() => _maxMembers = value);
                  sheetSetState(() {});
                },
                onWaitForMembersChanged: (value) {
                  setState(() => _waitForMembers = value);
                  sheetSetState(() {});
                },
                onWaitingTimeoutChanged: (value) {
                  setState(() => _waitingTimeoutSeconds = value);
                  sheetSetState(() {});
                },
                onCreate: () {
                  Navigator.pop(sheetContext);
                  _createRoom();
                },
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _showJoinRoomSheet() {
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
            return SingleChildScrollView(
              padding: _sheetPadding(sheetContext),
              child: _JoinRoomPanel(
                codeController: _codeCtrl,
                keyController: _keyCtrl,
                joining: _joining,
                onPasteInvite: () => _pasteInvite(sheetSetState),
                onJoin: () {
                  Navigator.pop(sheetContext);
                  _join();
                },
              ),
            );
          },
        );
      },
    );
  }

  EdgeInsets _sheetPadding(BuildContext sheetContext) {
    final viewInsets = MediaQuery.viewInsetsOf(sheetContext);
    final safeBottom = MediaQuery.paddingOf(sheetContext).bottom;
    return EdgeInsets.fromLTRB(
      AppSpacing.lg,
      AppSpacing.md,
      AppSpacing.lg,
      AppSpacing.xl + safeBottom + viewInsets.bottom,
    );
  }

  void _copy(String value, String message) {
    Clipboard.setData(ClipboardData(text: value));
    showSuccessSnack(context, message);
  }

  String _friendlyError(Object error) {
    final text = error.toString().replaceFirst('Exception: ', '').trim();
    if (text.isEmpty) return 'Could not complete that room action.';
    return text;
  }

  @override
  Widget build(BuildContext context) {
    return SwipeNavigationWrapper(
      currentLocation: '/rooms',
      child: ExitConfirmWrapper(
        child: Scaffold(
          backgroundColor: AppColors.white,
          appBar: AppBar(
            title: const Text('Secure rooms'),
            actions: [
              IconButton(
                tooltip: 'Refresh rooms',
                onPressed: _service.loadRooms,
                icon: const Icon(Icons.refresh_rounded),
              ),
            ],
          ),
          bottomNavigationBar: const AppBottomNav(currentLocation: '/rooms'),
          body: AnimatedBuilder(
            animation: _service,
            builder: (context, _) {
              final size = MediaQuery.sizeOf(context);
              final wide = size.width >= 760;
              final content = [
                _HeroPanel(
                    remainingCreates: _service.localCreatesRemainingToday),
                _RoomActionsPanel(
                  ttlSeconds: _ttlSeconds,
                  maxMembers: _maxMembers,
                  waitForMembers: _waitForMembers,
                  creating: _creating,
                  joining: _joining,
                  remainingCreates: _service.localCreatesRemainingToday,
                  retryAfter: _service.localCreateRetryAfter,
                  onCreate: _showCreateRoomSheet,
                  onJoin: _showJoinRoomSheet,
                ),
                _RoomsList(
                  rooms: _service.rooms,
                  loading: _service.isLoading,
                  onOpen: (room) => context.push('/rooms/${room.id}'),
                  onRefresh: _service.loadRooms,
                ),
              ];

              return RefreshIndicator(
                color: AppColors.fernGreen,
                onRefresh: _service.loadRooms,
                child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: EdgeInsets.fromLTRB(
                    wide ? 36 : AppSpacing.lg,
                    AppSpacing.lg,
                    wide ? 36 : AppSpacing.lg,
                    138,
                  ),
                  children: [
                    if (wide)
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Column(
                              children: [
                                content[0],
                                const SizedBox(height: AppSpacing.lg),
                                content[1],
                              ],
                            ),
                          ),
                          const SizedBox(width: AppSpacing.lg),
                          Expanded(child: content[2]),
                        ],
                      )
                    else
                      for (final child in content) ...[
                        child,
                        const SizedBox(height: AppSpacing.lg),
                      ],
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _HeroPanel extends StatelessWidget {
  const _HeroPanel({required this.remainingCreates});

  final int remainingCreates;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.charcoal,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _FlowingLoader(),
            const SizedBox(height: AppSpacing.xl),
            Text(
              'Private rooms for proof-sensitive conversations.',
              style: AppTypography.josefin(
                size: 26,
                weight: FontWeight.w700,
                color: AppColors.white,
                height: 1.05,
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              'Messages are encrypted on this device, signed per message, and removed automatically after the selected timer.',
              style: AppTypography.textTheme.bodyMedium?.copyWith(
                color: AppColors.white.withValues(alpha: 0.78),
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: [
                const _TinyProofChip(icon: Icons.lock_rounded, text: 'E2E'),
                const _TinyProofChip(
                    icon: Icons.timer_rounded, text: '2-5 min'),
                const _TinyProofChip(
                  icon: Icons.verified_user_rounded,
                  text: 'Signed',
                ),
                _TinyProofChip(
                  icon: Icons.bolt_rounded,
                  text: '$remainingCreates left today',
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _RoomActionsPanel extends StatelessWidget {
  const _RoomActionsPanel({
    required this.ttlSeconds,
    required this.maxMembers,
    required this.waitForMembers,
    required this.creating,
    required this.joining,
    required this.remainingCreates,
    required this.retryAfter,
    required this.onCreate,
    required this.onJoin,
  });

  final int ttlSeconds;
  final int maxMembers;
  final bool waitForMembers;
  final bool creating;
  final bool joining;
  final int remainingCreates;
  final Duration retryAfter;
  final VoidCallback onCreate;
  final VoidCallback onJoin;

  @override
  Widget build(BuildContext context) {
    final limited = remainingCreates <= 0;
    final config =
        '${ttlSeconds ~/ 60} min messages • $maxMembers members • ${waitForMembers ? 'wait mode' : 'soft mode'}';
    return _Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _PanelHeader(
            icon: Icons.tune_rounded,
            title: 'Room actions',
            subtitle: limited
                ? 'Creation unlocks in ${_formatDuration(retryAfter)}.'
                : config,
          ),
          const SizedBox(height: AppSpacing.lg),
          _ActionTile(
            icon: Icons.add_moderator_outlined,
            title: creating ? 'Sealing room...' : 'Create encrypted room',
            subtitle: limited
                ? 'Daily create limit reached on this device.'
                : 'Choose timer, members, and waiting behavior first.',
            enabled: !creating && !limited,
            filled: true,
            onTap: onCreate,
          ),
          const SizedBox(height: AppSpacing.md),
          _ActionTile(
            icon: Icons.key_rounded,
            title: joining ? 'Opening invite...' : 'Join with invite',
            subtitle: 'Paste a room code and secret key in a focused sheet.',
            enabled: !joining,
            filled: false,
            onTap: onJoin,
          ),
        ],
      ),
    );
  }

  String _formatDuration(Duration duration) {
    if (duration.inHours > 0) {
      return '${duration.inHours}h ${duration.inMinutes % 60}m';
    }
    if (duration.inMinutes > 0) return '${duration.inMinutes}m';
    return '${duration.inSeconds}s';
  }
}

class _ActionTile extends StatelessWidget {
  const _ActionTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.enabled,
    required this.filled,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool enabled;
  final bool filled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final background = filled ? AppColors.charcoal : AppColors.surfaceSecondary;
    final foreground = filled ? AppColors.white : AppColors.charcoal;
    return Material(
      color: background,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(18),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: foreground.withValues(alpha: filled ? 0.12 : 0.08),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, color: foreground),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: AppTypography.textTheme.titleSmall?.copyWith(
                        color: foreground.withValues(alpha: enabled ? 1 : 0.48),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: AppTypography.textTheme.bodySmall?.copyWith(
                        color:
                            foreground.withValues(alpha: enabled ? 0.72 : 0.42),
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                color: foreground.withValues(alpha: enabled ? 0.72 : 0.34),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ConfigSection extends StatelessWidget {
  const _ConfigSection({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.child,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surfaceSecondary,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.borderSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, size: 20, color: AppColors.charcoal),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: AppTypography.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
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
          const SizedBox(height: AppSpacing.md),
          child,
        ],
      ),
    );
  }
}

class _RoomOptionChip extends StatelessWidget {
  const _RoomOptionChip({
    required this.label,
    required this.selected,
    required this.onTap,
    this.icon,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final IconData? icon;

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
                selected ? Icons.check_rounded : icon ?? Icons.circle_outlined,
                size: 16,
                color: foreground,
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: AppTypography.textTheme.labelLarge?.copyWith(
                  color: foreground,
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

class _StrongSwitchTile extends StatelessWidget {
  const _StrongSwitchTile({
    required this.value,
    required this.onChanged,
    required this.title,
    required this.subtitle,
  });

  final bool value;
  final ValueChanged<bool> onChanged;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => onChanged(!value),
      borderRadius: BorderRadius.circular(16),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: value ? AppColors.fernGreenLight : AppColors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: value ? AppColors.fernGreen : AppColors.borderMedium,
            width: value ? 1.6 : 1,
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: AppTypography.textTheme.titleSmall?.copyWith(
                      color: AppColors.charcoal,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
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
            const SizedBox(width: AppSpacing.md),
            Switch.adaptive(
              value: value,
              onChanged: onChanged,
              activeThumbColor: AppColors.white,
              activeTrackColor: AppColors.fernGreen,
              inactiveThumbColor: AppColors.textSecondary,
              inactiveTrackColor: AppColors.borderMedium,
            ),
          ],
        ),
      ),
    );
  }
}

class _CreateRoomPanel extends StatelessWidget {
  const _CreateRoomPanel({
    required this.ttlSeconds,
    required this.maxMembers,
    required this.waitForMembers,
    required this.waitingTimeoutSeconds,
    required this.creating,
    required this.retryAfter,
    required this.remainingCreates,
    required this.onTtlChanged,
    required this.onMaxMembersChanged,
    required this.onWaitForMembersChanged,
    required this.onWaitingTimeoutChanged,
    required this.onCreate,
  });

  final int ttlSeconds;
  final int maxMembers;
  final bool waitForMembers;
  final int waitingTimeoutSeconds;
  final bool creating;
  final Duration retryAfter;
  final int remainingCreates;
  final ValueChanged<int> onTtlChanged;
  final ValueChanged<int> onMaxMembersChanged;
  final ValueChanged<bool> onWaitForMembersChanged;
  final ValueChanged<int> onWaitingTimeoutChanged;
  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    final limited = remainingCreates <= 0;
    return _Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _PanelHeader(
            icon: Icons.add_moderator_outlined,
            title: 'Create a room',
            subtitle: limited
                ? 'Your local quota resets at midnight.'
                : 'You can create $remainingCreates more today.',
          ),
          const SizedBox(height: AppSpacing.lg),
          _ConfigSection(
            icon: Icons.timer_outlined,
            title: 'Message timer',
            subtitle:
                'Default is 2 minutes. Max is 5 minutes for safer abandoned sessions.',
            child: Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: [
                for (final option in const [120, 180, 300])
                  _RoomOptionChip(
                    label: '${option ~/ 60} min',
                    selected: ttlSeconds == option,
                    icon: Icons.timer_rounded,
                    onTap: () => onTtlChanged(option),
                  ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          _ConfigSection(
            icon: Icons.groups_2_outlined,
            title: 'Room size',
            subtitle: 'Two members is the default. Three is the maximum.',
            child: Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: [
                _RoomOptionChip(
                  label: '2 members',
                  selected: maxMembers == 2,
                  icon: Icons.people_outline_rounded,
                  onTap: () => onMaxMembersChanged(2),
                ),
                _RoomOptionChip(
                  label: '3 members',
                  selected: maxMembers == 3,
                  icon: Icons.groups_2_outlined,
                  onTap: () => onMaxMembersChanged(3),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          _ConfigSection(
            icon: Icons.meeting_room_outlined,
            title: 'Start behavior',
            subtitle: waitForMembers
                ? 'The chat opens when everyone joins, or when the timeout resolves.'
                : 'Soft mode starts immediately. Late joiners see only new messages.',
            child: _StrongSwitchTile(
              value: waitForMembers,
              onChanged: onWaitForMembersChanged,
              title: waitForMembers ? 'Waiting mode on' : 'Soft mode on',
              subtitle:
                  'Tap to switch between immediate start and wait-for-members.',
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          AnimatedSwitcher(
              duration: const Duration(milliseconds: 220),
              child: waitForMembers
                  ? _ConfigSection(
                      key: const ValueKey('wait-options'),
                      icon: Icons.hourglass_top_rounded,
                      title: 'Waiting timeout',
                      subtitle:
                          'If only the host is present when this ends, the room is destroyed.',
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Wrap(
                            spacing: AppSpacing.sm,
                            runSpacing: AppSpacing.sm,
                            children: [
                              for (final option in const [120, 180, 300])
                                _RoomOptionChip(
                                  label: '${option ~/ 60} min',
                                  selected: waitingTimeoutSeconds == option,
                                  icon: Icons.hourglass_empty_rounded,
                                  onTap: () => onWaitingTimeoutChanged(option),
                                ),
                            ],
                          ),
                          const SizedBox(height: AppSpacing.sm),
                          Text(
                            'If at least one guest joined, the room starts. If nobody joins, it is removed instead of becoming a stale empty room.',
                            style: AppTypography.textTheme.bodySmall?.copyWith(
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    )
                  : Container(
                      key: const ValueKey('soft-mode'),
                      width: double.infinity,
                      padding: const EdgeInsets.all(AppSpacing.md),
                      decoration: BoxDecoration(
                        color: AppColors.fernGreenLight,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: AppColors.fernGreen.withValues(alpha: 0.45),
                        ),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.bolt_rounded,
                            color: AppColors.fernGreenDark,
                          ),
                          const SizedBox(width: AppSpacing.sm),
                          Expanded(
                            child: Text(
                              'Soft mode: the room opens now. New members cannot decrypt messages sent before they joined.',
                              style:
                                  AppTypography.textTheme.bodySmall?.copyWith(
                                color: AppColors.fernGreenDark,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ),
                    )),
          if (limited) ...[
            const SizedBox(height: AppSpacing.md),
            _WarningStrip(
              text:
                  'Room creation is blocked for ${_formatDuration(retryAfter)}.',
            ),
          ],
          const SizedBox(height: AppSpacing.lg),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: creating || limited ? null : onCreate,
              icon: creating
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.lock_open_rounded),
              label: Text(creating ? 'Sealing room...' : 'Create secure room'),
            ),
          ),
        ],
      ),
    );
  }

  String _formatDuration(Duration duration) {
    if (duration.inHours > 0) {
      return '${duration.inHours}h ${duration.inMinutes % 60}m';
    }
    if (duration.inMinutes > 0) return '${duration.inMinutes}m';
    return '${duration.inSeconds}s';
  }
}

class _JoinRoomPanel extends StatelessWidget {
  const _JoinRoomPanel({
    required this.codeController,
    required this.keyController,
    required this.joining,
    required this.onPasteInvite,
    required this.onJoin,
  });

  final TextEditingController codeController;
  final TextEditingController keyController;
  final bool joining;
  final VoidCallback onPasteInvite;
  final VoidCallback onJoin;

  @override
  Widget build(BuildContext context) {
    return _Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _PanelHeader(
            icon: Icons.key_rounded,
            title: 'Join with code',
            subtitle:
                'Paste a full invite link, or enter the room code and secret key manually.',
          ),
          const SizedBox(height: AppSpacing.lg),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(
              color: AppColors.fernGreenLight,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: AppColors.fernGreen.withValues(alpha: 0.45),
              ),
            ),
            child: Row(
              children: [
                const Icon(Icons.content_paste_go_rounded,
                    color: AppColors.fernGreenDark),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    'Copied the full room link? Paste it once and EchoProof will extract the code and key.',
                    style: AppTypography.textTheme.bodySmall?.copyWith(
                      color: AppColors.fernGreenDark,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: joining ? null : onPasteInvite,
                  child: const Text('Paste'),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          TextField(
            controller: codeController,
            textCapitalization: TextCapitalization.characters,
            maxLength: 8,
            decoration: const InputDecoration(
              labelText: 'Room code',
              counterText: '',
              prefixIcon: Icon(Icons.meeting_room_outlined),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          TextField(
            controller: keyController,
            minLines: 1,
            maxLines: 3,
            decoration: const InputDecoration(
              labelText: 'Secret key',
              prefixIcon: Icon(Icons.vpn_key_outlined),
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: joining ? null : onJoin,
              icon: joining
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.login_rounded),
              label: Text(joining ? 'Opening room...' : 'Join room'),
            ),
          ),
        ],
      ),
    );
  }
}

class _RoomsList extends StatelessWidget {
  const _RoomsList({
    required this.rooms,
    required this.loading,
    required this.onOpen,
    required this.onRefresh,
  });

  final List<SecureRoomSummary> rooms;
  final bool loading;
  final ValueChanged<SecureRoomSummary> onOpen;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    return _Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _PanelHeader(
            icon: Icons.forum_outlined,
            title: 'Open rooms',
            subtitle: loading ? 'Refreshing...' : '${rooms.length} active',
            trailing: IconButton(
              tooltip: 'Refresh',
              onPressed: onRefresh,
              icon: const Icon(Icons.refresh_rounded),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          if (loading && rooms.isEmpty)
            const Padding(
              padding: EdgeInsets.all(AppSpacing.xl),
              child: Center(
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: AppColors.fernGreen,
                ),
              ),
            )
          else if (rooms.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.xl),
              child: Center(
                child: Column(
                  children: [
                    const Icon(
                      Icons.lock_clock_outlined,
                      color: AppColors.textTertiary,
                      size: 34,
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Text(
                      'No active secure rooms.',
                      style: AppTypography.textTheme.bodyMedium?.copyWith(
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            )
          else
            for (final room in rooms)
              _RoomTile(room: room, onTap: () => onOpen(room)),
        ],
      ),
    );
  }
}

class _RoomTile extends StatelessWidget {
  const _RoomTile({required this.room, required this.onTap});
  final SecureRoomSummary room;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.fernGreenLight,
              ),
              child: const Icon(Icons.lock_rounded, color: AppColors.fernGreen),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    room.inviteCode,
                    style: AppTypography.textTheme.titleMedium,
                  ),
                  Text(
                    room.isWaiting
                        ? 'Waiting • ${room.memberProgressLabel}'
                        : '${room.messageTtlSeconds ~/ 60} minute message timer',
                    style: AppTypography.textTheme.bodySmall?.copyWith(
                      color: AppColors.textTertiary,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded,
                color: AppColors.textTertiary),
          ],
        ),
      ),
    );
  }
}

class _Panel extends StatelessWidget {
  const _Panel({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: AppColors.borderSubtle),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 18,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: child,
      ),
    );
  }
}

class _PanelHeader extends StatelessWidget {
  const _PanelHeader({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.trailing,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: AppColors.charcoal.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, size: 20, color: AppColors.charcoal),
        ),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: AppTypography.textTheme.titleMedium),
              Text(
                subtitle,
                style: AppTypography.textTheme.bodySmall?.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
        if (trailing != null) trailing!,
      ],
    );
  }
}

class _SecretValue extends StatelessWidget {
  const _SecretValue({
    required this.label,
    required this.value,
    required this.onCopy,
    this.compact = false,
  });

  final String label;
  final String value;
  final VoidCallback onCopy;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.surfaceSecondary,
        borderRadius: BorderRadius.circular(14),
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
                  Text(
                    label,
                    style: AppTypography.textTheme.labelMedium,
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    value,
                    maxLines: compact ? 2 : 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.josefin(
                      size: compact ? 12 : 20,
                      weight: FontWeight.w700,
                      color: AppColors.charcoal,
                    ),
                  ),
                ],
              ),
            ),
            IconButton(
              tooltip: 'Copy',
              onPressed: onCopy,
              icon: const Icon(Icons.copy_rounded),
            ),
          ],
        ),
      ),
    );
  }
}

class _WarningStrip extends StatelessWidget {
  const _WarningStrip({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.sunsetCoralLight,
        borderRadius: BorderRadius.circular(12),
        border:
            Border.all(color: AppColors.sunsetCoral.withValues(alpha: 0.35)),
      ),
      child: Text(
        text,
        style: AppTypography.textTheme.bodySmall?.copyWith(
          color: AppColors.sunsetCoralDark,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _TinyProofChip extends StatelessWidget {
  const _TinyProofChip({required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: AppColors.white.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: AppColors.white.withValues(alpha: 0.14)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: AppColors.white),
          const SizedBox(width: 6),
          Text(
            text,
            style: AppTypography.josefin(
              size: 12,
              weight: FontWeight.w600,
              color: AppColors.white,
            ),
          ),
        ],
      ),
    );
  }
}

class _FlowingLoader extends StatefulWidget {
  const _FlowingLoader();

  @override
  State<_FlowingLoader> createState() => _FlowingLoaderState();
}

class _FlowingLoaderState extends State<_FlowingLoader>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
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
      builder: (context, _) {
        return SizedBox(
          width: 108,
          height: 34,
          child: Stack(
            children: [
              for (var i = 0; i < 5; i++)
                Positioned(
                  left: i * 20,
                  top: 10 + (i.isEven ? 0 : 8),
                  child: Transform.scale(
                    scale: 0.75 +
                        0.25 * (1 - ((_controller.value - i * 0.12).abs() % 1)),
                    child: Container(
                      width: 14,
                      height: 14,
                      decoration: BoxDecoration(
                        color: i.isEven
                            ? AppColors.fernGreen
                            : AppColors.sunsetCoral,
                        shape: BoxShape.circle,
                      ),
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
