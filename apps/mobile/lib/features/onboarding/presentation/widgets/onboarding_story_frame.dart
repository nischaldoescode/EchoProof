// shared onboarding story layout
// keeps all onboarding steps consistent across phones, tablets, and split view

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../app/theme/colors.dart';
import '../../../../app/theme/spacing.dart';
import '../../../../app/theme/typography.dart';
import 'onboarding_progress.dart';

/// wraps each onboarding step in the same cinematic, responsive structure.
///
/// the frame centralizes safe-area padding, keyboard insets, width caps, and
/// reduced-motion handling so individual steps do not drift into different
/// layouts over time. this matters in split screen because the available width
/// and height can change while a route animation is still running.
class OnboardingStoryFrame extends StatelessWidget {
  const OnboardingStoryFrame({
    super.key,
    required this.currentStep,
    required this.totalSteps,
    required this.title,
    required this.body,
    required this.sceneIcon,
    required this.sceneLabel,
    required this.children,
    this.footer,
    this.accentColor = AppColors.fernGreen,
    this.sceneBackground = AppColors.fernGreenLight,
    this.backgroundColor = AppColors.white,
  });

  final int currentStep;
  final int totalSteps;
  final String title;
  final String body;
  final IconData sceneIcon;
  final String sceneLabel;
  final List<Widget> children;
  final Widget? footer;
  final Color accentColor;
  final Color sceneBackground;
  final Color backgroundColor;

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final reduceMotion = MediaQuery.disableAnimationsOf(context);

    return Scaffold(
      backgroundColor: backgroundColor,
      resizeToAvoidBottomInset: false,
      body: AnimatedPadding(
        duration: reduceMotion
            ? Duration.zero
            : const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
        padding: EdgeInsets.only(bottom: media.viewInsets.bottom),
        child: SafeArea(
          bottom: false,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final width = constraints.maxWidth;
              final height = constraints.maxHeight;
              final compactWidth = width < 380;
              final compactHeight = height < 680;
              final horizontalPadding = compactWidth
                  ? AppSpacing.lg
                  : AppSpacing.xl;
              final topPadding = compactHeight ? AppSpacing.lg : AppSpacing.xl;
              final bottomPadding =
                  math.max(media.viewPadding.bottom, AppSpacing.lg) +
                  AppSpacing.lg;
              final sceneHeight = compactHeight ? 132.0 : 168.0;
              final maxContentWidth = math.min(width, 560.0);

              return Align(
                alignment: Alignment.topCenter,
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: maxContentWidth),
                  child: SingleChildScrollView(
                    physics: const ClampingScrollPhysics(),
                    keyboardDismissBehavior:
                        ScrollViewKeyboardDismissBehavior.onDrag,
                    padding: EdgeInsets.fromLTRB(
                      horizontalPadding,
                      topPadding,
                      horizontalPadding,
                      bottomPadding,
                    ),
                    child: RepaintBoundary(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          OnboardingProgress(
                            currentStep: currentStep,
                            totalSteps: totalSteps,
                          ),
                          const SizedBox(height: AppSpacing.lg),
                          OnboardingStoryScene(
                            icon: sceneIcon,
                            label: sceneLabel,
                            accentColor: accentColor,
                            backgroundColor: sceneBackground,
                            height: sceneHeight,
                          ),
                          SizedBox(
                            height: compactHeight
                                ? AppSpacing.lg
                                : AppSpacing.xxl,
                          ),
                          Text(
                            title,
                            style: AppTypography.textTheme.headlineMedium
                                ?.copyWith(
                                  fontSize: compactWidth ? 24 : 28,
                                  height: 1.08,
                                  letterSpacing: 0,
                                  color: AppColors.charcoal,
                                ),
                          ),
                          const SizedBox(height: AppSpacing.sm),
                          Text(
                            body,
                            style: AppTypography.textTheme.bodyMedium?.copyWith(
                              color: AppColors.textSecondary,
                              height: 1.45,
                              letterSpacing: 0,
                            ),
                          ),
                          SizedBox(
                            height: compactHeight
                                ? AppSpacing.lg
                                : AppSpacing.xxl,
                          ),
                          ...children,
                          if (footer != null) ...[
                            SizedBox(
                              height: compactHeight
                                  ? AppSpacing.lg
                                  : AppSpacing.xxl,
                            ),
                            footer!,
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

/// paints a lightweight story panel without image assets.
///
/// the scene is intentionally simple: it gives onboarding a cinematic anchor
/// while avoiding heavy shaders, oversized bitmaps, and continuous animation.
/// the painter uses only stable geometry so it stays cheap on low-end devices
/// and during split-screen resizes.
class OnboardingStoryScene extends StatelessWidget {
  const OnboardingStoryScene({
    super.key,
    required this.icon,
    required this.label,
    required this.accentColor,
    required this.backgroundColor,
    required this.height,
  });

  final IconData icon;
  final String label;
  final Color accentColor;
  final Color backgroundColor;
  final double height;

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final scene = Container(
      height: height,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
        border: Border.all(color: AppColors.borderSubtle),
      ),
      child: Stack(
        children: [
          Positioned.fill(
            child: CustomPaint(
              painter: _StoryScenePainter(
                accentColor: accentColor,
                backgroundColor: backgroundColor,
              ),
            ),
          ),
          Align(
            alignment: Alignment.center,
            child: Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: AppColors.white.withValues(alpha: 0.92),
                borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
                border: Border.all(color: accentColor.withValues(alpha: 0.18)),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.charcoal.withValues(alpha: 0.08),
                    blurRadius: 18,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: Icon(icon, color: accentColor, size: 30),
            ),
          ),
          Positioned(
            left: AppSpacing.lg,
            right: AppSpacing.lg,
            bottom: AppSpacing.md,
            child: Text(
              label,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: AppTypography.textTheme.labelLarge?.copyWith(
                color: AppColors.charcoal,
                height: 1.25,
                letterSpacing: 0,
              ),
            ),
          ),
        ],
      ),
    );

    if (reduceMotion) {
      return scene;
    }

    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: 1),
      duration: const Duration(milliseconds: 420),
      curve: Curves.easeOutCubic,
      builder: (context, value, child) {
        final progress = value.clamp(0.0, 1.0).toDouble();
        return Opacity(
          opacity: progress,
          child: Transform.translate(
            offset: Offset(0, (1 - progress) * 8),
            child: child,
          ),
        );
      },
      child: scene,
    );
  }
}

class _StoryScenePainter extends CustomPainter {
  const _StoryScenePainter({
    required this.accentColor,
    required this.backgroundColor,
  });

  final Color accentColor;
  final Color backgroundColor;

  @override
  void paint(Canvas canvas, Size size) {
    final base = Paint()..color = backgroundColor;
    canvas.drawRect(Offset.zero & size, base);

    final band = Paint()
      ..color = AppColors.white.withValues(alpha: 0.42)
      ..style = PaintingStyle.fill;
    final bandPath = Path()
      ..moveTo(0, size.height * 0.18)
      ..lineTo(size.width, size.height * 0.02)
      ..lineTo(size.width, size.height * 0.42)
      ..lineTo(0, size.height * 0.58)
      ..close();
    canvas.drawPath(bandPath, band);

    final lowerBand = Paint()
      ..color = AppColors.sunsetCoral.withValues(alpha: 0.10)
      ..style = PaintingStyle.fill;
    final lowerPath = Path()
      ..moveTo(0, size.height * 0.72)
      ..lineTo(size.width, size.height * 0.52)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(lowerPath, lowerBand);

    final line = Paint()
      ..color = accentColor.withValues(alpha: 0.32)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    final y = size.height * 0.34;
    canvas.drawLine(
      Offset(size.width * 0.14, y),
      Offset(size.width * 0.86, y),
      line,
    );

    final markerPaint = Paint()
      ..color = accentColor.withValues(alpha: 0.70)
      ..style = PaintingStyle.fill;
    for (final x in [0.18, 0.50, 0.82]) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(
            center: Offset(size.width * x, y),
            width: 8,
            height: 8,
          ),
          const Radius.circular(3),
        ),
        markerPaint,
      );
    }

    final framePaint = Paint()
      ..color = AppColors.charcoal.withValues(alpha: 0.06)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(
          size.width * 0.08,
          size.height * 0.12,
          size.width * 0.84,
          size.height * 0.72,
        ),
        const Radius.circular(AppSpacing.radiusLg),
      ),
      framePaint,
    );
  }

  @override
  bool shouldRepaint(covariant _StoryScenePainter oldDelegate) {
    return accentColor != oldDelegate.accentColor ||
        backgroundColor != oldDelegate.backgroundColor;
  }
}
