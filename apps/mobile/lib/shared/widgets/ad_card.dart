// ad card shown every 7th item in the feed
// creative: not a banner, looks like content
// pro users never see this checked before rendering
// rewarded: user watches ad to get 1 hour ad-free

import 'package:echoproof/core/utils/snack.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../app/theme/colors.dart';
import '../../app/theme/spacing.dart';
import '../../core/services/ad_service.dart';
import '../../features/subscription/presentation/services/subscription_service.dart';

class AdCard extends StatefulWidget {
  const AdCard({super.key});

  @override
  State<AdCard> createState() => _AdCardState();
}

class _AdCardState extends State<AdCard> with SingleTickerProviderStateMixin {
  late final AnimationController _shimmerController;
  bool _isWatching = false;
  bool _earned = false;

  @override
  void initState() {
    super.initState();
    _shimmerController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat();
  }

  @override
  void dispose() {
    _shimmerController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final adService = context.watch<AdService>();
    final subService = context.watch<SubscriptionService>();

    // pro users and ad-free users never see this
    if (subService.isPro || adService.isAdFreeActive) {
      return const SizedBox.shrink();
    }

    return Container(
      margin: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppSpacing.echoCardRadius),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFF1A1A1A),
            Color(0xFF1E3A2A),
          ],
        ),
        border: Border.all(
          color: AppColors.fernGreen.withValues(alpha: 0.3),
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppSpacing.echoCardRadius),
        child: Stack(
          children: [
            // animated shimmer background
            AnimatedBuilder(
              animation: _shimmerController,
              builder: (context, _) {
                return Positioned.fill(
                  child: CustomPaint(
                    painter: _ShimmerPainter(
                      progress: _shimmerController.value,
                    ),
                  ),
                );
              },
            ),

            // content
            Padding(
              padding: const EdgeInsets.all(AppSpacing.xl),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // label row
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.fernGreen.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(
                            color: AppColors.fernGreen.withValues(alpha: 0.4),
                          ),
                        ),
                        child: Text(
                          'SPONSORED',
                          style: GoogleFonts.josefinSans(
                            fontSize: 9,
                            fontWeight: FontWeight.w700,
                            color: AppColors.fernGreen,
                            letterSpacing: 1.2,
                          ),
                        ),
                      ),
                      const Spacer(),
                      // ad-free timer if active
                      if (adService.adFreeMinutesRemaining > 0)
                        Text(
                          '${adService.adFreeMinutesRemaining}m ad-free left',
                          style: GoogleFonts.josefinSans(
                            fontSize: 11,
                            color: AppColors.fernGreen.withValues(alpha: 0.8),
                          ),
                        ),
                    ],
                  ),

                  const SizedBox(height: AppSpacing.lg),

                  // main message
                  Text(
                    _earned
                        ? '🎉 1 hour ad-free unlocked!'
                        : 'Support Echoproof.',
                    style: GoogleFonts.josefinSans(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                      height: 1.2,
                    ),
                  ),

                  const SizedBox(height: AppSpacing.xs),

                  Text(
                    _earned
                        ? 'Come back in an hour for your next reward.'
                        : 'Watch a short video and browse ad-free for 1 hour.',
                    style: GoogleFonts.josefinSans(
                      fontSize: 13,
                      color: Colors.white.withValues(alpha: 0.7),
                      height: 1.4,
                    ),
                  ),

                  const SizedBox(height: AppSpacing.lg),

                  // action row
                  Row(
                    children: [
                      if (!_earned)
                        _WatchButton(
                          isLoading: _isWatching,
                          isReady: adService.rewardedReady,
                          onTap: _watchAd,
                        ),

                      const SizedBox(width: AppSpacing.sm),

                      // go pro link
                      if (!_earned)
                        GestureDetector(
                          onTap: () =>
                              Navigator.of(context).pushNamed('/subscribe'),
                          child: Text(
                            'Go Pro instead →',
                            style: GoogleFonts.josefinSans(
                              fontSize: 12,
                              color: AppColors.fernGreen,
                              fontWeight: FontWeight.w600,
                              decoration: TextDecoration.underline,
                              decorationColor: AppColors.fernGreen,
                            ),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _watchAd() async {
    if (_isWatching) return;
    setState(() => _isWatching = true);

    final adService = context.read<AdService>();
    final shown = await adService.showRewarded(
      onRewarded: () {
        if (mounted) {
          setState(() {
            _earned = true;
            _isWatching = false;
          });
          showSuccessSnack(context, '1 hour ad-free unlocked!');
        }
      },
      onDismissed: () {
        if (!mounted) return;
        final earned = _earned;
        setState(() => _isWatching = false);
        if (!earned) {
          showWarningSnack(context, 'Ad closed before the reward was earned.');
        }
      },
    );

    if (!shown && mounted) {
      showInfoSnack(
          context, 'No ad available right now — try again in a moment');
    }
  }
}

// animated watch button with progress ring
class _WatchButton extends StatefulWidget {
  const _WatchButton({
    required this.isLoading,
    required this.isReady,
    required this.onTap,
  });
  final bool isLoading;
  final bool isReady;
  final VoidCallback onTap;

  @override
  State<_WatchButton> createState() => _WatchButtonState();
}

class _WatchButtonState extends State<_WatchButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulseController;
  late final Animation<double> _pulse;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);
    _pulse = Tween<double>(begin: 1.0, end: 1.06).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ScaleTransition(
      scale: widget.isReady ? _pulse : const AlwaysStoppedAnimation(1.0),
      child: GestureDetector(
        onTap: widget.isReady && !widget.isLoading ? widget.onTap : null,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            color: widget.isReady
                ? AppColors.fernGreen
                : AppColors.fernGreen.withValues(alpha: 0.3),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (widget.isLoading)
                const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              else
                const Icon(
                  Icons.play_circle_outline_rounded,
                  size: 16,
                  color: Colors.white,
                ),
              const SizedBox(width: 6),
              Text(
                widget.isLoading
                    ? 'Loading...'
                    : widget.isReady
                        ? 'Watch ad (1 hr free)'
                        : 'Ad loading...',
                style: GoogleFonts.josefinSans(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// moving shimmer lines on the dark ad card background
class _ShimmerPainter extends CustomPainter {
  const _ShimmerPainter({required this.progress});
  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          Colors.transparent,
          Colors.white.withValues(alpha: 0.03),
          Colors.transparent,
        ],
        stops: const [0, 0.5, 1],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));

    // diagonal shimmer line that sweeps across
    final x = -size.width + progress * size.width * 2;
    canvas.save();
    canvas.translate(x, 0);
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, size.height),
      paint,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_ShimmerPainter old) => old.progress != progress;
}
