// shows the permanent on-chain record for a verified echo
// appears on the echo detail screen when status = verified
// links to solana explorer so anyone can independently verify
// never mentions "solana" or "blockchain" in displayed text

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../../app/theme/colors.dart';
import '../../../../app/theme/spacing.dart';
import '../../../../app/theme/typography.dart';
import '../../../../core/services/solana_service.dart';

class VerifiedEchoRecord extends StatelessWidget {
  const VerifiedEchoRecord({
    super.key,
    required this.transactionSignature,
    required this.verifiedAt,
  });

  final String transactionSignature;
  final DateTime verifiedAt;

  @override
  Widget build(BuildContext context) {
    final explorerUrl = SolanaService.explorerUrl(transactionSignature);
    final shortSig =
        '${transactionSignature.substring(0, 8)}...${transactionSignature.substring(transactionSignature.length - 8)}';

    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: AppColors.fernGreenLight,
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        border: Border.all(
          color: AppColors.fernGreen.withOpacity(0.3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.verified_outlined,
                size: 16,
                color: AppColors.fernGreen,
              ),
              const SizedBox(width: AppSpacing.xs),
              Text(
                'Permanent record created',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.fernGreenDark,
                  fontFamily: AppTypography.fontFamily,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'This echo\'s verification has been permanently recorded and cannot be altered or deleted.',
            style: AppTypography.textTheme.bodySmall?.copyWith(
              color: AppColors.fernGreenDark,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              Expanded(
                child: Text(
                  'Record ID: $shortSig',
                  style: TextStyle(
                    fontSize: 11,
                    fontFamily: 'monospace',
                    color: AppColors.fernGreenDark,
                  ),
                ),
              ),
              GestureDetector(
                onTap: () {
                  Clipboard.setData(ClipboardData(text: transactionSignature));
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: const Text('Record ID copied'),
                      backgroundColor: AppColors.charcoal,
                      behavior: SnackBarBehavior.floating,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  );
                },
                child: const Icon(
                  Icons.copy_outlined,
                  size: 14,
                  color: AppColors.fernGreen,
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              GestureDetector(
                onTap: () async {
                  final uri = Uri.parse(explorerUrl);
                  if (await canLaunchUrl(uri)) {
                    await launchUrl(uri, mode: LaunchMode.externalApplication);
                  }
                },
                child: const Icon(
                  Icons.open_in_new_outlined,
                  size: 14,
                  color: AppColors.fernGreen,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
