// interaction buttons — support, challenge, replies, and actions
// applies optimistic update, calls edge function, reverts on failure

import 'package:echoproof/core/utils/snack.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../app/theme/colors.dart';
import '../../../../app/theme/spacing.dart';
import '../../../../app/theme/typography.dart';
import '../../../../core/localization/app_copy.dart';
import '../../../../shared/widgets/echo_action_sheet.dart';
import '../../domain/entities/echo_entity.dart';
import '../services/echo_feed_service.dart';
import 'signal_response_sheet.dart';

class InteractionButtons extends StatelessWidget {
  const InteractionButtons({
    super.key,
    required this.echo,
    this.dense = false,
    this.onEchoHidden,
    this.onContextPosted,
  });

  final EchoEntity echo;
  final bool dense;
  final VoidCallback? onEchoHidden;
  final Future<void> Function()? onContextPosted;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: dense ? 0 : AppSpacing.md,
        vertical: dense ? 0 : AppSpacing.xs,
      ),
      child: Row(
        children: [
          Expanded(
            child: _InteractionButton(
              key: ValueKey('${echo.id}:reply'),
              count: echo.replyCount,
              label: context.l('Reply'),
              icon: Icons.chat_bubble_outline_rounded,
              onTap: () async {
                _openReplies(context);
                return false;
              },
              flashColor: AppColors.fernGreen,
            ),
          ),
          Expanded(
            child: _InteractionButton(
              key: ValueKey('${echo.id}:support'),
              count: echo.supportCount,
              label: context.l('Support'),
              icon: Icons.thumb_up_alt_outlined,
              onTap: () => _openContextSheet(context, 'support'),
              flashColor: AppColors.fernGreen,
            ),
          ),
          Expanded(
            child: _InteractionButton(
              key: ValueKey('${echo.id}:challenge'),
              count: echo.challengeCount,
              label: context.l('Challenge'),
              icon: Icons.arrow_downward_rounded,
              onTap: () => _openContextSheet(context, 'challenge'),
              flashColor: AppColors.sunsetCoralDark,
            ),
          ),
          Expanded(
            child: _InteractionButton(
              key: ValueKey('${echo.id}:bonds'),
              count: echo.bondCount,
              label: context.l('Bonds'),
              icon: Icons.link_outlined,
              onTap: () async {
                _openBonds(context);
                return false;
              },
              flashColor: AppColors.fernGreenDark,
            ),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.more_horiz_rounded, size: 19),
            color: AppColors.textTertiary,
            tooltip: context.l('More actions'),
            onPressed: () => showEchoActionSheet(
              context: context,
              echoId: echo.id,
              authorId: echo.userId,
              authorUsername: echo.username,
              onHidden: () {
                context.read<EchoFeedService>().removeEcho(echo.id);
                onEchoHidden?.call();
              },
            ),
          ),
        ],
      ),
    );
  }

  void _openBonds(BuildContext context) {
    if (showOfflineSnackIfNeeded(context)) return;
    showInfoSnack(context, context.l('Opening echo bonds and evidence.'));
    context.push('/feed/echo/${echo.id}');
  }

  void _openReplies(BuildContext context) {
    final avatarParam = echo.userAvatarUrl == null
        ? ''
        : '&avatar=${Uri.encodeComponent(echo.userAvatarUrl!)}';

    context.push(
      '/echo/${echo.id}/replies'
      '?author=${Uri.encodeComponent(echo.username)}'
      '&content=${Uri.encodeComponent(echo.content)}'
      '&authorId=${Uri.encodeComponent(echo.userId)}'
      '$avatarParam',
    );
  }

  Future<bool> _openContextSheet(BuildContext context, String type) async {
    if (showOfflineSnackIfNeeded(context)) return false;

    final currentUserId = Supabase.instance.client.auth.currentUser?.id;
    if (currentUserId == null) {
      showInfoSnack(context, context.l('Sign in again to continue.'));
      return false;
    }
    if (echo.userId.isNotEmpty && echo.userId == currentUserId) {
      showInfoSnack(
        context,
        context.l('You cannot support or challenge your own echo.'),
      );
      return false;
    }

    HapticFeedback.selectionClick();
    showSignalResponseSheet(
      context: context,
      echoId: echo.id,
      initialStance: type,
      onPosted: () async {
        if (onContextPosted != null) {
          await onContextPosted!();
        } else {
          await context.read<EchoFeedService>().refresh();
        }
        if (context.mounted) {
          showSuccessSnack(
            context,
            type == 'support'
                ? context.l('Support context added.')
                : context.l('Challenge context added.'),
          );
        }
      },
    );
    return false;
  }
}

class _InteractionButton extends StatefulWidget {
  const _InteractionButton({
    super.key,
    required this.count,
    required this.label,
    required this.icon,
    required this.onTap,
    required this.flashColor,
  });

  final int count;
  final String label;
  final IconData icon;
  final Future<bool> Function() onTap;
  final Color flashColor;

  @override
  State<_InteractionButton> createState() => _InteractionButtonState();
}

class _InteractionButtonState extends State<_InteractionButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _scale;
  bool _isFlashing = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 100),
      reverseDuration: const Duration(milliseconds: 80),
    );
    _scale = Tween<double>(begin: 1.0, end: 0.88).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeIn),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _handleTap() async {
    await _controller.forward();
    await _controller.reverse();
    final shouldActivate = await widget.onTap();
    if (!mounted) return;
    if (shouldActivate) {
      setState(() => _isFlashing = true);
    }
    await Future<void>.delayed(const Duration(milliseconds: 420));
    if (mounted) setState(() => _isFlashing = false);
  }

  @override
  Widget build(BuildContext context) {
    final label =
        widget.count > 0 ? '${widget.count} ${widget.label}' : widget.label;
    final color = _isFlashing ? widget.flashColor : AppColors.textSecondary;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _handleTap,
      child: ScaleTransition(
        scale: _scale,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              AnimatedScale(
                scale: _isFlashing ? 1.18 : 1.0,
                duration: const Duration(milliseconds: 180),
                curve: Curves.easeOutBack,
                child: Icon(widget.icon, size: 15, color: color),
              ),
              const SizedBox(width: 4),
              Flexible(
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 180),
                  transitionBuilder: (child, animation) {
                    return FadeTransition(
                      opacity: animation,
                      child: SlideTransition(
                        position: Tween<Offset>(
                          begin: const Offset(0, 0.25),
                          end: Offset.zero,
                        ).animate(animation),
                        child: child,
                      ),
                    );
                  },
                  child: Text(
                    label,
                    key: ValueKey(label),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight:
                          _isFlashing ? FontWeight.w700 : FontWeight.w600,
                      color: color,
                      fontFamily: AppTypography.fontFamily,
                    ),
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
