// rating_prompt.dart
// shows an animated in-app rating popup after the user has been active for
// ~1 hour total across sessions (tracked via hive)
// uses in_app_review package for real store prompt on confirm
// import this and call ratingprompt.maybeshow(context) from feed_screen
// after the feed loads

import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:in_app_review/in_app_review.dart';
import '../../../app/theme/colors.dart';
import '../../../app/theme/typography.dart';

class RatingPrompt {
  static const _kFirstLaunch = 'rating_first_launch_ms';

// prompt thresholds in minutes of cumulative active time
  // 60 = first prompt after 1 hour
  // 180 = second prompt after 3 hours total
  // 10080 = weekly thereafter (7 days * 60 * 24)
  static const _kThresholds = [60, 180, 10080];
  static const _kDismissCount = 'rating_dismiss_count';
  static const _kLastDismissMs = 'rating_last_dismiss_ms';
  static const _kRated = 'rating_completed';

  static Future<void> maybeShow(BuildContext context) async {
    final box = Hive.box('app_settings');

    // never show again if user already rated
    final rated = box.get(_kRated, defaultValue: false) as bool;
    if (rated) return;

    final firstLaunchMs = box.get(_kFirstLaunch) as int?;
    final now = DateTime.now().millisecondsSinceEpoch;

    if (firstLaunchMs == null) {
      await box.put(_kFirstLaunch, now);
      return;
    }

    final elapsedMinutes = (now - firstLaunchMs) / 60000;
    final dismissCount = box.get(_kDismissCount, defaultValue: 0) as int;
    final lastDismissMs = box.get(_kLastDismissMs) as int?;

    // determine which threshold to use based on dismiss count
    final thresholdIndex = dismissCount.clamp(0, _kThresholds.length - 1);
    final thresholdMinutes = _kThresholds[thresholdIndex];

    if (elapsedMinutes < thresholdMinutes) return;

    // if dismissed before, ensure minimum gap of 2 hours since last dismiss
    if (lastDismissMs != null) {
      final minutesSinceDismiss = (now - lastDismissMs) / 60000;
      if (minutesSinceDismiss < 120) return;
    }

    if (!context.mounted) return;
    await showGeneralDialog(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black54,
      transitionDuration: const Duration(milliseconds: 400),
      transitionBuilder: (ctx, anim, secondAnim, child) {
        final curve = CurvedAnimation(parent: anim, curve: Curves.elasticOut);
        return ScaleTransition(scale: curve, child: child);
      },
      pageBuilder: (ctx, _, __) => const _RatingDialog(),
    );
  }
}

class _RatingDialog extends StatefulWidget {
  const _RatingDialog();

  @override
  State<_RatingDialog> createState() => _RatingDialogState();
}

class _RatingDialogState extends State<_RatingDialog>
    with SingleTickerProviderStateMixin {
  late AnimationController _starAnim;
  static const _kDismissCount = 'rating_dismiss_count';
  static const _kLastDismissMs = 'rating_last_dismiss_ms';
  static const _kRated = 'rating_completed';
  int _hovered = 0;
  int _selected = 0;

  @override
  void initState() {
    super.initState();
    _starAnim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    )..forward();
  }

  @override
  void dispose() {
    _starAnim.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    Navigator.of(context).pop();
    final box = Hive.box('app_settings');
    await box.put(_kRated, true);
    if (_selected >= 4) {
      final review = InAppReview.instance;
      if (await review.isAvailable()) {
        await review.requestReview();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Material(
        color: Colors.transparent,
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 32),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(28),
          ),
          padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // animated emoji
              FadeTransition(
                opacity: _starAnim,
                child: const Text('🌟', style: TextStyle(fontSize: 52)),
              ),
              const SizedBox(height: 16),
              Text(
                'Enjoying Echoproof?',
                style: AppTypography.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                'Tell us what you think — it takes 10 seconds.',
                style: AppTypography.textTheme.bodyMedium?.copyWith(
                  color: AppColors.textSecondary,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              // star row
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(5, (i) {
                  final val = i + 1;
                  final filled = val <= (_hovered > 0 ? _hovered : _selected);
                  return GestureDetector(
                    onTap: () => setState(() => _selected = val),
                    child: MouseRegion(
                      onEnter: (_) => setState(() => _hovered = val),
                      onExit: (_) => setState(() => _hovered = 0),
                      child: AnimatedScale(
                        scale: filled ? 1.2 : 1.0,
                        duration: const Duration(milliseconds: 150),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          child: Icon(
                            filled
                                ? Icons.star_rounded
                                : Icons.star_outline_rounded,
                            size: 36,
                            color: filled
                                ? const Color(0xFFFFC107)
                                : AppColors.textSecondary,
                          ),
                        ),
                      ),
                    ),
                  );
                }),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _selected > 0 ? _submit : null,
                  child: const Text('Submit'),
                ),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () async {
                  final box = Hive.box('app_settings');
                  final count = box.get(_kDismissCount, defaultValue: 0) as int;
                  await box.put(_kDismissCount, count + 1);
                  await box.put(
                    _kLastDismissMs,
                    DateTime.now().millisecondsSinceEpoch,
                  );
                  Navigator.of(context).pop();
                },
                child: Text(
                  'Maybe later',
                  style: TextStyle(color: AppColors.textSecondary),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
