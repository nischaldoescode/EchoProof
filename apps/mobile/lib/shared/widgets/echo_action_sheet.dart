// echo action sheet — report, share, copy link
// themed to match echoproof design system
// no riverpod — uses supabase instance directly

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../app/theme/colors.dart';
import '../../app/theme/spacing.dart';
import '../../app/theme/typography.dart';
import '../../../../core/utils/snack.dart';

void showEchoActionSheet({
  required BuildContext context,
  required String echoId,
}) {
  showModalBottomSheet<void>(
    context: context,
    backgroundColor: AppColors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(
        top: Radius.circular(AppSpacing.radiusLg),
      ),
    ),
    builder: (_) => _EchoActionSheet(
      parentContext: context,
      echoId: echoId,
    ),
  );
}

class _EchoActionSheet extends StatelessWidget {
  const _EchoActionSheet({
    required this.parentContext,
    required this.echoId,
  });

  final BuildContext parentContext;
  final String echoId;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.only(
          top: AppSpacing.sm,
          bottom: AppSpacing.md,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 36,
              height: 4,
              margin: const EdgeInsets.only(bottom: AppSpacing.lg),
              decoration: BoxDecoration(
                color: AppColors.borderMedium,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            _SheetTile(
              icon: Icons.flag_outlined,
              label: 'Report echo',
              iconColor: AppColors.sunsetCoral,
              onTap: () {
                Navigator.pop(context);
                _showReportSheet(parentContext: parentContext, echoId: echoId);
              },
            ),
            const Divider(
                height: 1, indent: AppSpacing.lg, endIndent: AppSpacing.lg),
            _SheetTile(
              icon: Icons.ios_share_outlined,
              label: 'Share echo',
              iconColor: AppColors.charcoal,
              onTap: () {
                Navigator.pop(context);
                showInfoSnack(context, 'Share Coming Soon');
              },
            ),
            const Divider(
                height: 1, indent: AppSpacing.lg, endIndent: AppSpacing.lg),
            _SheetTile(
              icon: Icons.link_outlined,
              label: 'Copy link',
              iconColor: AppColors.charcoal,
              onTap: () {
                Navigator.pop(context);
                final url = 'https://echoproof.online/echo/$echoId';
                Clipboard.setData(ClipboardData(text: url));
                showSuccessSnack(parentContext, 'Link copied');
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

void _showReportSheet({
  required BuildContext parentContext,
  required String echoId,
}) {
  showModalBottomSheet<void>(
    context: parentContext,
    backgroundColor: AppColors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(
        top: Radius.circular(AppSpacing.radiusLg),
      ),
    ),
    builder: (_) => _ReportSheet(
      parentContext: parentContext,
      echoId: echoId,
    ),
  );
}

class _ReportSheet extends StatefulWidget {
  const _ReportSheet({
    required this.parentContext,
    required this.echoId,
  });

  final BuildContext parentContext;
  final String echoId;

  @override
  State<_ReportSheet> createState() => _ReportSheetState();
}

class _ReportSheetState extends State<_ReportSheet> {
  bool _isSubmitting = false;

  static const _reasons = [
    (value: 'spam', label: 'Spam'),
    (value: 'misinformation', label: 'Misinformation'),
    (value: 'harassment', label: 'Harassment'),
    (value: 'fake_proof', label: 'Fake proof'),
    (value: 'other', label: 'Other'),
  ];

  Future<void> _submit(String reason) async {
    if (_isSubmitting) return;
    setState(() => _isSubmitting = true);

    Navigator.pop(context);

    final supabase = Supabase.instance.client;
    final userId = supabase.auth.currentUser?.id;

    try {
      await supabase.from('echo_reports').insert({
        'echo_id': widget.echoId,
        'reporter_id': userId,
        'reason': reason,
      });

      if (widget.parentContext.mounted) {
        showSuccessSnack(widget.parentContext, 'Report submitted — thank you');
      }
    } catch (e) {
      final isDuplicate =
          e.toString().contains('duplicate') || e.toString().contains('unique');

      if (widget.parentContext.mounted) {
        ScaffoldMessenger.of(widget.parentContext).showSnackBar(
          SnackBar(
            content: Text(
              isDuplicate
                  ? 'You already reported this echo'
                  : 'Report failed, try again',
            ),
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

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.only(
          top: AppSpacing.sm,
          bottom: AppSpacing.md,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
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
              child: Text(
                'Why are you reporting this?',
                style: AppTypography.textTheme.titleMedium,
              ),
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
                          child: Text(
                            r.label,
                            style: AppTypography.textTheme.bodyMedium,
                          ),
                        ),
                        const Icon(
                          Icons.chevron_right,
                          size: 18,
                          color: AppColors.textTertiary,
                        ),
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
