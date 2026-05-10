// empty feed widget
// shown when there are no echoes to display
// animated with floating echo waves and intro text about the ecosystem

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../../app/theme/colors.dart';
import '../../../../app/theme/spacing.dart';

class EmptyFeed extends StatefulWidget {
  const EmptyFeed({super.key});

  @override
  State<EmptyFeed> createState() => _EmptyFeedState();
}

class _EmptyFeedState extends State<EmptyFeed>
    with SingleTickerProviderStateMixin {

  late final AnimationController _controller;
  late final Animation<double>   _logoFloat;
  late final Animation<double>   _ringPulse;
  late final Animation<double>   _textFade;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..repeat(reverse: true);

    _logoFloat = Tween<double>(begin: -6, end: 6).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );

    _ringPulse = Tween<double>(begin: 0.8, end: 1.1).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );

    _textFade = Tween<double>(begin: 0.7, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // animated logo with rings
            AnimatedBuilder(
              animation: _controller,
              builder: (context, _) {
                return SizedBox(
                  width: 140, height: 140,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      // pulsing rings
                      Transform.scale(
                        scale: _ringPulse.value,
                        child: Container(
                          width: 120, height: 120,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: AppColors.fernGreen.withValues(alpha: 0.15),
                              width: 2,
                            ),
                          ),
                        ),
                      ),
                      Transform.scale(
                        scale: _ringPulse.value * 0.85,
                        child: Container(
                          width: 100, height: 100,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: AppColors.fernGreen.withValues(alpha: 0.25),
                              width: 1.5,
                            ),
                          ),
                        ),
                      ),

                      // floating logo
                      Transform.translate(
                        offset: Offset(0, _logoFloat.value),
                        child: Container(
                          width: 72, height: 72,
                          decoration: BoxDecoration(
                            color: AppColors.fernGreenLight,
                            borderRadius: BorderRadius.circular(20),
                            boxShadow: [
                              BoxShadow(
                                color:       AppColors.fernGreen.withValues(alpha: 0.3),
                                blurRadius:  16,
                                offset:      Offset(0, 4 + _logoFloat.value * 0.3),
                              ),
                            ],
                          ),
                          child: const Icon(
                            Icons.radio_button_unchecked_rounded,
                            size:  36,
                            color: AppColors.fernGreen,
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),

            const SizedBox(height: AppSpacing.xxl),

            AnimatedBuilder(
              animation: _textFade,
              builder: (context, child) => Opacity(
                opacity: _textFade.value,
                child: child,
              ),
              child: Column(
                children: [
                  Text(
                    'No echoes yet.',
                    style: GoogleFonts.josefinSans(
                      fontSize:   22,
                      fontWeight: FontWeight.w700,
                      color:      AppColors.charcoal,
                      letterSpacing: -0.3,
                    ),
                  ),

                  const SizedBox(height: AppSpacing.sm),

                  Text(
                    'Be the first to send one.',
                    style: GoogleFonts.josefinSans(
                      fontSize: 15,
                      color:    AppColors.textSecondary,
                    ),
                  ),

                  const SizedBox(height: AppSpacing.xl),

                  // ecosystem explainer
                  _EcosystemCard(),

                  const SizedBox(height: AppSpacing.xxl),

                  // CTA
                  ElevatedButton.icon(
                    onPressed: () => context.push('/create'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.charcoal,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 28, vertical: 14,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    icon: const Icon(Icons.add, size: 18),
                    label: Text(
                      'Create your first Echo',
                      style: GoogleFonts.josefinSans(
                        fontSize:   14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EcosystemCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color:        AppColors.softSand,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.borderSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'How Echoproof works',
            style: GoogleFonts.josefinSans(
              fontSize:   14,
              fontWeight: FontWeight.w600,
              color:      AppColors.charcoal,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          ...[
            (Icons.record_voice_over_outlined, 'Post an Echo — any opinion or claim'),
            (Icons.people_outline,             'Community supports or challenges it'),
            (Icons.verified_outlined,          'High-signal echoes get verified on-chain'),
            (Icons.link_outlined,              'Bond your reputation to verified truths'),
          ].map((item) => Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.sm),
            child: Row(
              children: [
                Icon(item.$1, size: 16, color: AppColors.fernGreen),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    item.$2,
                    style: GoogleFonts.josefinSans(
                      fontSize: 13,
                      color:    AppColors.textSecondary,
                    ),
                  ),
                ),
              ],
            ),
          )),
        ],
      ),
    );
  }
}