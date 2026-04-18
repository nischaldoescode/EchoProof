// interaction buttons — support and challenge
// ripple animation on tap, optimistic update, haptic feedback

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../app/theme/colors.dart';
import '../../../../app/theme/spacing.dart';
import '../../../../app/theme/typography.dart';
import '../../domain/entities/echo_entity.dart';
import '../../../../shared/widgets/echo_action_sheet.dart';
import '../../../../core/services/echo_interaction_service.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../providers/echo_feed_provider.dart';

class InteractionButtons extends ConsumerWidget {
  const InteractionButtons({super.key, required this.echo});
  final EchoEntity echo;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.xs,
      ),
      child: Row(
        children: [
          // support button
          _InteractionButton(
            label: '${echo.supportCount}',
            icon: Icons.arrow_upward_rounded,
            activeColor: AppColors.fernGreen,
            onTap: () => _interact(context, ref, 'support'),
          ),

          const SizedBox(width: AppSpacing.sm),

          // challenge button
          _InteractionButton(
            label: '${echo.challengeCount}',
            icon: Icons.arrow_downward_rounded,
            activeColor: AppColors.sunsetCoral,
            onTap: () => _interact(context, ref, 'challenge'),
          ),

          const Spacer(),

          // proof count
          if (echo.proofCount > 0)
            Row(
              children: [
                const Icon(Icons.attach_file_outlined,
                    size: 14, color: AppColors.textTertiary),
                const SizedBox(width: 3),
                Text(
                  '${echo.proofCount}',
                  style: AppTypography.textTheme.labelMedium,
                ),
                const SizedBox(width: AppSpacing.sm),
              ],
            ),

          // share / menu
          IconButton(
            icon: const Icon(Icons.more_horiz, size: 18),
            color: AppColors.textTertiary,
            onPressed: () {
              showEchoActionSheet(
                context: context,
                ref: ref,
                echoId: echo.id,
              );
            },
          ),
        ],
      ),
    );
  }

  Future<void> _interact(
      BuildContext context, WidgetRef ref, String type) async {
    HapticFeedback.selectionClick();
    ref.read(echoFeedProvider.notifier).applyOptimisticInteraction(
          echoId: echo.id,
          type: type,
        );

    final service = ref.read(echoInteractionServiceProvider);

    final session = ref.read(supabaseProvider).auth.currentSession;
    final jwt = session?.accessToken;

    if (jwt == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Not authenticated'),
          backgroundColor: AppColors.charcoal,
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      );
      return;
    }

    try {
      await service.interact(
        echoId: echo.id,
        type: type,
        jwtToken: jwt,
      );
    } catch (e) {
      final opposite = type == 'support' ? 'challenge' : 'support';

      ref.read(echoFeedProvider.notifier).applyOptimisticInteraction(
            echoId: echo.id,
            type: opposite,
          );

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.toString()),
          backgroundColor: AppColors.sunsetCoral,
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      );
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
