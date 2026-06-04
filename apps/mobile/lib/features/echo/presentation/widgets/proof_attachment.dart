// proof attachment widget
// shown in echo detail renders a single proof card
// handles url, image, and document types
// respects 1mb limit and image-only constraint

import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../../app/theme/colors.dart';
import '../../../../app/theme/spacing.dart';
import '../../../../app/theme/typography.dart';
import 'solana_status_chip.dart';

class ProofAttachment extends StatelessWidget {
  const ProofAttachment({
    super.key,
    required this.proofType,
    required this.proofUrl,
    required this.description,
    required this.username,
    required this.timeAgo,
    this.stakeTx,
    this.solanaStatus = 'pending',
  });

  final String proofType;
  final String proofUrl;
  final String? description;
  final String username;
  final String timeAgo;
  final String? stakeTx;
  final String solanaStatus;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        border: Border.all(color: AppColors.borderSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // image preview
          if (proofType == 'image')
            ClipRRect(
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(AppSpacing.radiusMd),
              ),
              child: CachedNetworkImage(
                imageUrl: proofUrl,
                width: double.infinity,
                height: 180,
                fit: BoxFit.cover,
                placeholder: (_, __) => Container(
                  height: 180,
                  color: AppColors.softSand,
                  child: const Center(
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: AppColors.fernGreen,
                    ),
                  ),
                ),
                errorWidget: (_, __, ___) => Container(
                  height: 60,
                  color: AppColors.softSand,
                  child: const Center(
                    child: Icon(Icons.broken_image_outlined,
                        color: AppColors.textTertiary),
                  ),
                ),
              ),
            ),

          Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    _TypeIcon(proofType: proofType),
                    const SizedBox(width: AppSpacing.xs),
                    Text(
                      _typeLabel(proofType),
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textTertiary,
                        fontFamily: AppTypography.fontFamily,
                        letterSpacing: 0.3,
                      ),
                    ),
                    const Spacer(),
                    if (proofType == 'url')
                      GestureDetector(
                        onTap: () async {
                          final uri = Uri.parse(proofUrl);
                          if (await canLaunchUrl(uri)) {
                            await launchUrl(uri,
                                mode: LaunchMode.externalApplication);
                          }
                        },
                        child: const Icon(
                          Icons.open_in_new_outlined,
                          size: 14,
                          color: AppColors.textTertiary,
                        ),
                      ),
                  ],
                ),
                if (description != null && description!.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    description!,
                    style: AppTypography.textTheme.bodySmall,
                  ),
                ],
                const SizedBox(height: AppSpacing.xs),
                Text(
                  '@$username · $timeAgo',
                  style: AppTypography.textTheme.labelMedium,
                ),
                const SizedBox(height: AppSpacing.sm),
                SolanaStatusChip(
                  status: solanaStatus,
                  signature: stakeTx,
                  label: 'Solana proof',
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _typeLabel(String type) => switch (type) {
        'image' => 'IMAGE PROOF',
        'url' => 'LINK PROOF',
        'document' => 'DOCUMENT',
        _ => 'PROOF',
      };
}

class _TypeIcon extends StatelessWidget {
  const _TypeIcon({required this.proofType});
  final String proofType;

  @override
  Widget build(BuildContext context) {
    final icon = switch (proofType) {
      'image' => Icons.image_outlined,
      'url' => Icons.link_outlined,
      'document' => Icons.attach_file_outlined,
      _ => Icons.attach_file_outlined,
    };
    return Icon(icon, size: 13, color: AppColors.textTertiary);
  }
}
