// interaction buttons — support and challenge
// applies optimistic update, calls edge function, reverts on failure
// uses EchoFeedService via provider — no riverpod

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../app/theme/colors.dart';
import '../../../../app/theme/spacing.dart';
import '../../../../app/theme/typography.dart';
import '../../domain/entities/echo_entity.dart';
import '../../../../core/services/echo_interaction_service.dart';
import '../../../../core/utils/logger.dart';
import '../../../../shared/widgets/echo_action_sheet.dart';
import '../services/echo_feed_service.dart';
import 'package:go_router/go_router.dart';

class InteractionButtons extends StatelessWidget {
  const InteractionButtons({super.key, required this.echo});
  final EchoEntity echo;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.xs,
      ),
      child: Row(
        children: [
          _InteractionButton(
            label: '${echo.supportCount}',
            icon: Icons.arrow_upward_rounded,
            activeColor: AppColors.fernGreen,
            onTap: () => _interact(context, 'support'),
          ),
          const SizedBox(width: AppSpacing.sm),
          _InteractionButton(
            label: '${echo.challengeCount}',
            icon: Icons.arrow_downward_rounded,
            activeColor: AppColors.sunsetCoral,
            onTap: () => _interact(context, 'challenge'),
          ),
          const Spacer(),
          GestureDetector(
            onTap: () => context.push(
              '/echo/${echo.id}/replies?author=${echo.username}&content=${Uri.encodeComponent(echo.content)}',
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.chat_bubble_outline_rounded,
                  size: 14,
                  color: AppColors.textTertiary,
                ),
                const SizedBox(width: 3),
                Text(
                  '${echo.replyCount}',
                  style: AppTypography.textTheme.labelMedium,
                ),
                const SizedBox(width: AppSpacing.sm),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.more_horiz, size: 18),
            color: AppColors.textTertiary,
            onPressed: () => showEchoActionSheet(
              context: context,
              echoId: echo.id,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _interact(BuildContext context, String type) async {
    HapticFeedback.selectionClick();

    final feed = context.read<EchoFeedService>();
    feed.applyOptimisticInteraction(echoId: echo.id, type: type);

    final client = Supabase.instance.client;
    final session = client.auth.currentSession;

    if (session == null) {
      feed.revertOptimisticInteraction(echoId: echo.id, type: type);
      return;
    }

    try {
      // pass client and supabaseUrl explicitly — no Riverpod provider needed
      const supabaseUrl = String.fromEnvironment('SUPABASE_URL');

      final service = EchoInteractionService(client, supabaseUrl);
      final result = await service.interact(
        echoId: echo.id,
        type: type,
        jwtToken: session.accessToken,
      );

      final updated = result.updatedEcho;
      feed.updateEchoScores(
        echoId: echo.id,
        trustScore: updated.trustScore,
        confidenceScore: updated.confidenceScore,
        supportCount: updated.supportCount,
        challengeCount: updated.challengeCount,
        status: updated.status,
      );
    } catch (e) {
      AppLogger.error('interaction failed', e);
      feed.revertOptimisticInteraction(echoId: echo.id, type: type);

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.toString()),
            backgroundColor: AppColors.sunsetCoral,
            behavior: SnackBarBehavior.floating,
            margin: const EdgeInsets.only(bottom: 88, left: 16, right: 16),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        );
      }
    }
  }
}

class _InteractionButton extends StatefulWidget {
  const _InteractionButton({
    required this.label,
    required this.icon,
    required this.activeColor,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final Color activeColor;
  final VoidCallback onTap;

  @override
  State<_InteractionButton> createState() => _InteractionButtonState();
}

class _InteractionButtonState extends State<_InteractionButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _scale;

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
    widget.onTap();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: _handleTap,
      child: ScaleTransition(
        scale: _scale,
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.sm,
            vertical: AppSpacing.xs,
          ),
          decoration: BoxDecoration(
            color: AppColors.softSand,
            borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(widget.icon, size: 14, color: AppColors.textSecondary),
              const SizedBox(width: 4),
              Text(
                widget.label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textSecondary,
                  fontFamily: AppTypography.fontFamily,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
