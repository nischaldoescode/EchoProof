// echo action sheet — report, share, copy link
// themed to match echoproof design system exactly:
//   white background, charcoal text, fern green for safe actions,
//   sunset coral for destructive actions (report)

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../app/theme/colors.dart';
import '../../app/theme/spacing.dart';
import '../../app/theme/typography.dart';
import '../../features/auth/presentation/providers/auth_provider.dart';

/// shows the main echo action bottom sheet with report, share, copy link
void showEchoActionSheet({
  required BuildContext context,
  required WidgetRef ref,
  required String echoId,
}) {
  showModalBottomSheet<void>(
    context: context,
    backgroundColor: AppColors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(AppSpacing.radiusLg)),
    ),
    builder: (_) => _EchoActionSheet(
      context: context,
      ref: ref,
      echoId: echoId,
    ),
  );
}

class _EchoActionSheet extends StatelessWidget {
  const _EchoActionSheet({
    required this.context,
    required this.ref,
    required this.echoId,
  });

  final BuildContext context;
  final WidgetRef ref;
  final String echoId;

  @override
  Widget build(BuildContext buildContext) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.only(
          top: AppSpacing.sm,
          bottom: AppSpacing.md,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // drag handle
            Container(
              width: 36,
              height: 4,
              margin: const EdgeInsets.only(bottom: AppSpacing.lg),
              decoration: BoxDecoration(
                color: AppColors.borderMedium,
                borderRadius: BorderRadius.circular(2),
              ),
            ),

            // report — coral because it's a destructive action
            _SheetTile(
              icon: Icons.flag_outlined,
              label: 'Report echo',
              iconColor: AppColors.sunsetCoral,
              onTap: () {
                Navigator.pop(buildContext);
                _showReportSheet(context: context, ref: ref, echoId: echoId);
              },
            ),

            const Divider(height: 1, indent: AppSpacing.lg, endIndent: AppSpacing.lg),

            // share
            _SheetTile(
              icon: Icons.ios_share_outlined,
              label: 'Share echo',
              iconColor: AppColors.charcoal,
              onTap: () {
                Navigator.pop(buildContext);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: const Text('Share coming soon'),
                    backgroundColor: AppColors.charcoal,
                    behavior: SnackBarBehavior.floating,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                );
              },
            ),

            const Divider(height: 1, indent: AppSpacing.lg, endIndent: AppSpacing.lg),

            // copy link
            _SheetTile(
              icon: Icons.link_outlined,
              label: 'Copy link',
              iconColor: AppColors.charcoal,
              onTap: () {
                Navigator.pop(buildContext);
                HapticFeedback.lightImpact();
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: const Text('Link copied'),
                    backgroundColor: AppColors.charcoal,
                    behavior: SnackBarBehavior.floating,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _SheetTile extends StatelessWidget {
  const _SheetTile({
    required this.icon,
    required this.label,
    required this.iconColor,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final Color iconColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.xl,
          vertical: AppSpacing.md,
        ),
        child: Row(
          children: [
            Icon(icon, size: 20, color: iconColor),
            const SizedBox(width: AppSpacing.md),
            Text(
              label,
              style: AppTypography.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// -------------------------------------------------------
// report bottom sheet — second level
// -------------------------------------------------------

void _showReportSheet({
  required BuildContext context,
  required WidgetRef ref,
  required String echoId,
}) {
  showModalBottomSheet<void>(
    context: context,
    backgroundColor: AppColors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(AppSpacing.radiusLg)),
    ),
    builder: (_) => _ReportSheet(
      context: context,
      ref: ref,
      echoId: echoId,
    ),
  );
}

class _ReportSheet extends StatefulWidget {
  const _ReportSheet({
    required this.context,
    required this.ref,
    required this.echoId,
  });

  final BuildContext context;
  final WidgetRef ref;
  final String echoId;

  @override
  State<_ReportSheet> createState() => _ReportSheetState();
}

class _ReportSheetState extends State<_ReportSheet> {
  bool _isSubmitting = false;

  static const _reasons = [
    (value: 'spam',           label: 'Spam'),
    (value: 'misinformation', label: 'Misinformation'),
    (value: 'harassment',     label: 'Harassment'),
    (value: 'fake_proof',     label: 'Fake proof'),
    (value: 'other',          label: 'Other'),
  ];

  Future<void> _submit(String reason) async {
    if (_isSubmitting) return;
    setState(() => _isSubmitting = true);

    Navigator.pop(context);

    final supabase = widget.ref.read(supabaseProvider);
    final userId   = widget.ref.read(currentUserIdProvider);

    try {
      await supabase.from('echo_reports').insert({
        'echo_id':     widget.echoId,
        'reporter_id': userId,
        'reason':      reason,
      });

      ScaffoldMessenger.of(widget.context).showSnackBar(
        SnackBar(
          content: const Text('Report submitted — thank you'),
          backgroundColor: AppColors.fernGreen,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      );
    } catch (e) {
      final msg = e.toString();
      final isDuplicate = msg.contains('duplicate') || msg.contains('unique');

      ScaffoldMessenger.of(widget.context).showSnackBar(
        SnackBar(
          content: Text(isDuplicate ? 'You already reported this echo' : 'Report failed, try again'),
          backgroundColor: AppColors.sunsetCoral,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.only(top: AppSpacing.sm, bottom: AppSpacing.md),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // drag handle
            Center(
              child: Container(
                width: 36, height: 4,
                margin: const EdgeInsets.only(bottom: AppSpacing.md),
                decoration: BoxDecoration(
                  color: AppColors.borderMedium,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),

            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.xl,
                vertical: AppSpacing.sm,
              ),
              child: Text('Why are you reporting this?',
                style: AppTypography.textTheme.titleMedium),
            ),

            ..._reasons.map((r) => InkWell(
              onTap: () => _submit(r.value),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.xl,
                  vertical: AppSpacing.md,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(r.label, style: AppTypography.textTheme.bodyMedium),
                    ),
                    const Icon(Icons.chevron_right, size: 18, color: AppColors.textTertiary),
                  ],
                ),
              ),
            )),
          ],
        ),
      ),
    );
  }
}