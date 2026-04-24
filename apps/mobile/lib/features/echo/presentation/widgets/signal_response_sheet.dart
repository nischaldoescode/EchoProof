// signal response sheet — echoproof comment system
// plain StatefulWidget — no riverpod
// uses Supabase.instance.client directly

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../app/theme/colors.dart';
import '../../../../app/theme/spacing.dart';
import '../../../../app/theme/typography.dart';
import '../../../../core/utils/logger.dart';

void showSignalResponseSheet({
  required BuildContext context,
  required String echoId,
  required VoidCallback onPosted,
}) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(
        top: Radius.circular(AppSpacing.radiusLg),
      ),
    ),
    builder: (_) => _SignalResponseSheet(
      echoId: echoId,
      onPosted: onPosted,
    ),
  );
}

class _SignalResponseSheet extends StatefulWidget {
  const _SignalResponseSheet({
    required this.echoId,
    required this.onPosted,
  });

  final String echoId;
  final VoidCallback onPosted;

  @override
  State<_SignalResponseSheet> createState() => _SignalResponseSheetState();
}

class _SignalResponseSheetState extends State<_SignalResponseSheet> {
  final _controller = TextEditingController();
  String _stance = 'neutral';
  bool _submitting = false;

  static const _stances = [
    (value: 'support', label: 'Supporting', color: AppColors.fernGreen),
    (value: 'neutral', label: 'Neutral', color: AppColors.textTertiary),
    (value: 'challenge', label: 'Challenging', color: AppColors.sunsetCoral),
  ];

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final content = _controller.text.trim();
    if (content.isEmpty || _submitting) return;

    setState(() => _submitting = true);
    HapticFeedback.lightImpact();

    try {
      final client = Supabase.instance.client;
      final userId = client.auth.currentUser?.id;
      if (userId == null) throw Exception('not authenticated');

      await client.from('signal_responses').insert({
        'echo_id': widget.echoId,
        'user_id': userId,
        'content': content,
        'stance': _stance,
      });

      await client.rpc(
        'increment_response_count',
        params: {'p_echo_id': widget.echoId},
      );

      AppLogger.info('signal response posted for echo ${widget.echoId}');

      if (mounted) {
        Navigator.pop(context);
        widget.onPosted();
      }
    } catch (e) {
      AppLogger.error('signal response failed', e);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.toString()),
            backgroundColor: AppColors.sunsetCoral,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        );
        setState(() => _submitting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: SafeArea(
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
              Text(
                'Signal response',
                style: AppTypography.textTheme.titleMedium,
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                'Your response adds to the verification weight of this echo.',
                style: AppTypography.textTheme.bodySmall,
              ),
              const SizedBox(height: AppSpacing.lg),
              Row(
                children: _stances.map((s) {
                  final selected = _stance == s.value;
                  return Expanded(
                    child: GestureDetector(
                      onTap: () => setState(() => _stance = s.value),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 180),
                        margin: const EdgeInsets.only(right: AppSpacing.xs),
                        padding: const EdgeInsets.symmetric(
                          vertical: AppSpacing.sm,
                        ),
                        decoration: BoxDecoration(
                          color: selected
                              ? s.color.withValues(alpha: 0.1)
                              : AppColors.softSand,
                          borderRadius:
                              BorderRadius.circular(AppSpacing.radiusMd),
                          border: Border.all(
                            color: selected ? s.color : AppColors.borderSubtle,
                          ),
                        ),
                        child: Center(
                          child: Text(
                            s.label,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight:
                                  selected ? FontWeight.w600 : FontWeight.w400,
                              color:
                                  selected ? s.color : AppColors.textSecondary,
                              fontFamily: AppTypography.fontFamily,
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: AppSpacing.lg),
              TextField(
                controller: _controller,
                maxLines: 4,
                maxLength: 500,
                autofocus: true,
                decoration: const InputDecoration(
                  hintText: 'Add your signal response...',
                  alignLabelWithHint: true,
                ),
                style: AppTypography.textTheme.bodyMedium,
              ),
              const SizedBox(height: AppSpacing.lg),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _submitting ? null : _submit,
                  child: _submitting
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: AppColors.white,
                          ),
                        )
                      : const Text('Send response'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
