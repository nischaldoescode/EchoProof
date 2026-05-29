import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../../app/theme/colors.dart';
import '../../../../app/theme/spacing.dart';
import '../../../../app/theme/typography.dart';
import '../../../../core/services/solana_service.dart';

class SolanaStatusChip extends StatelessWidget {
  const SolanaStatusChip({
    super.key,
    required this.status,
    this.signature,
    this.label = 'Solana',
    this.compact = true,
    this.onRetry,
    this.isRetrying = false,
  });

  final String status;
  final String? signature;
  final String label;
  final bool compact;
  final Future<void> Function()? onRetry;
  final bool isRetrying;

  bool get _isAnchored =>
      (signature != null && signature!.isNotEmpty) || status == 'anchored';

  @override
  Widget build(BuildContext context) {
    final canRetry = !_isAnchored && onRetry != null;
    final normalized =
        isRetrying ? 'recording' : (_isAnchored ? 'anchored' : status);
    final (text, icon, color, bg) = switch (normalized) {
      'anchored' => (
          '$label anchored',
          Icons.hub_outlined,
          AppColors.fernGreenDark,
          AppColors.fernGreenLight,
        ),
      'recording' => (
          '$label recording',
          Icons.sync_rounded,
          const Color(0xFF6B4FA0),
          const Color(0xFFF3EEF9),
        ),
      'failed' => (
          canRetry ? '$label retry' : '$label delayed',
          canRetry ? Icons.refresh_rounded : Icons.warning_amber_rounded,
          AppColors.sunsetCoralDark,
          AppColors.sunsetCoralLight,
        ),
      _ => (
          canRetry ? '$label queued' : '$label pending',
          canRetry ? Icons.refresh_rounded : Icons.schedule_rounded,
          AppColors.textTertiary,
          AppColors.softSand,
        ),
    };

    final child = AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      padding: EdgeInsets.symmetric(
        horizontal: compact ? AppSpacing.sm : AppSpacing.md,
        vertical: compact ? AppSpacing.xs : AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(AppSpacing.radiusFull),
        border: Border.all(color: color.withValues(alpha: 0.18)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: compact ? 12 : 14, color: color),
          const SizedBox(width: 5),
          Text(
            text,
            style: TextStyle(
              fontSize: compact ? 10.5 : 12,
              fontWeight: FontWeight.w600,
              color: color,
              fontFamily: AppTypography.fontFamily,
            ),
          ),
          if (signature != null && signature!.isNotEmpty) ...[
            const SizedBox(width: 5),
            Icon(
              Icons.open_in_new_rounded,
              size: compact ? 11 : 13,
              color: color,
            ),
          ] else if (canRetry) ...[
            const SizedBox(width: 5),
            Icon(
              Icons.touch_app_outlined,
              size: compact ? 11 : 13,
              color: color,
            ),
          ],
        ],
      ),
    );

    if (signature == null || signature!.isEmpty) {
      if (!canRetry || isRetrying) return child;
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onRetry,
        child: child,
      );
    }

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () async {
        final uri = Uri.parse(SolanaService.explorerUrl(signature!));
        if (await canLaunchUrl(uri)) {
          await launchUrl(uri, mode: LaunchMode.externalApplication);
        }
      },
      child: child,
    );
  }
}
