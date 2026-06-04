// echo action sheet report, share, copy link
// themed to match echoproof design system
// no riverpod uses supabase instance directly

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
  required String authorId,
  required String authorUsername,
  VoidCallback? onHidden,
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
      authorId: authorId,
      authorUsername: authorUsername,
      onHidden: onHidden,
    ),
  );
}

class _EchoActionSheet extends StatelessWidget {
  const _EchoActionSheet({
    required this.parentContext,
    required this.echoId,
    required this.authorId,
    required this.authorUsername,
    this.onHidden,
  });

  final BuildContext parentContext;
  final String echoId;
  final String authorId;
  final String authorUsername;
  final VoidCallback? onHidden;

  @override
  Widget build(BuildContext context) {
    final currentUserId = Supabase.instance.client.auth.currentUser?.id;
    final isOwnEcho = authorId.isNotEmpty && authorId == currentUserId;

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
            if (isOwnEcho) ...[
              _SheetTile(
                icon: Icons.delete_outline_rounded,
                label: 'Delete echo',
                subtitle: 'Server limit: 1 echo deletion per day',
                iconColor: AppColors.sunsetCoral,
                onTap: () {
                  Navigator.pop(context);
                  _confirmDeleteEcho(
                    parentContext: parentContext,
                    echoId: echoId,
                    onDeleted: onHidden,
                  );
                },
              ),
              const Divider(
                  height: 1, indent: AppSpacing.lg, endIndent: AppSpacing.lg),
            ] else ...[
              _SheetTile(
                icon: Icons.visibility_off_outlined,
                label: 'Not interested',
                iconColor: AppColors.textSecondary,
                onTap: () async {
                  Navigator.pop(context);
                  await _recordFeedback(
                    parentContext: parentContext,
                    echoId: echoId,
                    authorId: authorId,
                    type: 'not_interested',
                    onHidden: onHidden,
                  );
                },
              ),
              const Divider(
                  height: 1, indent: AppSpacing.lg, endIndent: AppSpacing.lg),
              _SheetTile(
                icon: Icons.block_rounded,
                label: authorUsername.isEmpty
                    ? 'Block author'
                    : 'Block @$authorUsername',
                subtitle: 'Their echoes and profile will be hidden both ways',
                iconColor: AppColors.sunsetCoral,
                onTap: () async {
                  Navigator.pop(context);
                  await _blockAuthor(
                    parentContext: parentContext,
                    echoId: echoId,
                    authorId: authorId,
                    authorUsername: authorUsername,
                    onHidden: onHidden,
                  );
                },
              ),
              const Divider(
                  height: 1, indent: AppSpacing.lg, endIndent: AppSpacing.lg),
              _SheetTile(
                icon: Icons.flag_outlined,
                label: 'Report echo',
                iconColor: AppColors.sunsetCoral,
                onTap: () {
                  Navigator.pop(context);
                  _showReportSheet(
                    parentContext: parentContext,
                    echoId: echoId,
                    authorId: authorId,
                    onHidden: onHidden,
                  );
                },
              ),
              const Divider(
                  height: 1, indent: AppSpacing.lg, endIndent: AppSpacing.lg),
            ],
            _SheetTile(
              icon: Icons.ios_share_outlined,
              label: 'Share echo',
              iconColor: AppColors.charcoal,
              onTap: () {
                Navigator.pop(context);
                showInfoSnack(parentContext, 'Share Coming Soon');
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

Future<void> _recordFeedback({
  required BuildContext parentContext,
  required String echoId,
  required String authorId,
  required String type,
  VoidCallback? onHidden,
}) async {
  final supabase = Supabase.instance.client;
  final userId = supabase.auth.currentUser?.id;
  if (userId == null) return;
  if (authorId == userId) {
    if (parentContext.mounted) {
      showInfoSnack(
          parentContext, 'You cannot hide your own echo from yourself.');
    }
    return;
  }

  try {
    await supabase.from('user_feed_feedback').upsert({
      'user_id': userId,
      'echo_id': echoId,
      'author_id': authorId.isEmpty ? null : authorId,
      'feedback_type': type,
    }, onConflict: 'user_id,echo_id,feedback_type');

    if (parentContext.mounted) {
      showSuccessSnack(parentContext, 'We will show fewer echoes like this');
    }
    onHidden?.call();
  } catch (_) {
    if (parentContext.mounted) {
      showErrorSnack(parentContext, 'Could not save feedback');
    }
  }
}

Future<void> _blockAuthor({
  required BuildContext parentContext,
  required String echoId,
  required String authorId,
  required String authorUsername,
  VoidCallback? onHidden,
}) async {
  final supabase = Supabase.instance.client;
  final userId = supabase.auth.currentUser?.id;
  if (userId == null || authorId.isEmpty) return;
  if (authorId == userId) {
    if (parentContext.mounted) {
      showInfoSnack(parentContext, 'You cannot block yourself.');
    }
    return;
  }

  try {
    await supabase.from('user_blocks').upsert({
      'blocker_id': userId,
      'blocked_id': authorId,
    }, onConflict: 'blocker_id,blocked_id');

    await supabase.from('user_feed_feedback').upsert({
      'user_id': userId,
      'echo_id': echoId,
      'author_id': authorId,
      'feedback_type': 'block_author',
    }, onConflict: 'user_id,echo_id,feedback_type');

    if (parentContext.mounted) {
      final label = authorUsername.isEmpty ? 'author' : '@$authorUsername';
      showSuccessSnack(parentContext, 'Blocked $label');
    }
    onHidden?.call();
  } catch (_) {
    if (parentContext.mounted) {
      showErrorSnack(parentContext, 'Could not block author');
    }
  }
}

class _SheetTile extends StatelessWidget {
  const _SheetTile({
    required this.icon,
    required this.label,
    required this.iconColor,
    required this.onTap,
    this.subtitle,
  });

  final IconData icon;
  final String label;
  final String? subtitle;
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
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: AppTypography.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      subtitle!,
                      style: AppTypography.textTheme.bodySmall?.copyWith(
                        color: AppColors.textTertiary,
                      ),
                    ),
                  ],
                ],
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
  required String authorId,
  VoidCallback? onHidden,
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
      authorId: authorId,
      onHidden: onHidden,
    ),
  );
}

class _ReportSheet extends StatefulWidget {
  const _ReportSheet({
    required this.parentContext,
    required this.echoId,
    required this.authorId,
    this.onHidden,
  });

  final BuildContext parentContext;
  final String echoId;
  final String authorId;
  final VoidCallback? onHidden;

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

      await supabase.from('user_feed_feedback').upsert({
        'user_id': userId,
        'echo_id': widget.echoId,
        'author_id': widget.authorId.isEmpty ? null : widget.authorId,
        'feedback_type': 'report',
      }, onConflict: 'user_id,echo_id,feedback_type');

      if (widget.parentContext.mounted) {
        showSuccessSnack(widget.parentContext, 'Report submitted — thank you');
      }
      widget.onHidden?.call();
    } catch (e) {
      final isDuplicate =
          e.toString().contains('duplicate') || e.toString().contains('unique');

      if (widget.parentContext.mounted) {
        showErrorSnack(
          widget.parentContext,
          isDuplicate
              ? 'You already reported this echo'
              : 'Report failed, try again',
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

void _confirmDeleteEcho({
  required BuildContext parentContext,
  required String echoId,
  VoidCallback? onDeleted,
}) {
  showModalBottomSheet<void>(
    context: parentContext,
    backgroundColor: AppColors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(
        top: Radius.circular(AppSpacing.radiusLg),
      ),
    ),
    builder: (context) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                margin: const EdgeInsets.only(bottom: AppSpacing.lg),
                decoration: BoxDecoration(
                  color: AppColors.borderMedium,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Text('Delete this echo?',
                style: AppTypography.textTheme.titleMedium),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'Echo deletion is limited to 1 per day and is checked on the server before anything is removed.',
              style: AppTypography.textTheme.bodySmall?.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            Row(
              children: [
                Expanded(
                  child: TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Cancel'),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () async {
                      Navigator.pop(context);
                      await _deleteEcho(
                        parentContext: parentContext,
                        echoId: echoId,
                        onDeleted: onDeleted,
                      );
                    },
                    icon: const Icon(Icons.delete_outline_rounded, size: 17),
                    label: const Text('Delete'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.sunsetCoral,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}

Future<void> _deleteEcho({
  required BuildContext parentContext,
  required String echoId,
  VoidCallback? onDeleted,
}) async {
  try {
    await Supabase.instance.client.rpc(
      'delete_own_echo_limited',
      params: {'p_echo_id': echoId},
    );
    if (parentContext.mounted) {
      showSuccessSnack(parentContext, 'Echo deleted');
    }
    onDeleted?.call();
  } catch (e) {
    final message = e.toString().contains('daily_echo_delete_limit')
        ? 'You can delete only 1 echo per day.'
        : 'Could not delete echo.';
    if (parentContext.mounted) {
      showErrorSnack(parentContext, message);
    }
  }
}
