// onboarding step: quick guide / feature tour
// step 5 of 6 (after categories, before first echo)
// animated card carousel showing key features
// shown only once, hidden after onboarding

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../../app/theme/colors.dart';
import '../../../../app/theme/spacing.dart';
import '../../../../app/theme/typography.dart';
import '../../../../core/localization/app_copy.dart';
import '../services/onboarding_service.dart';
import '../widgets/onboarding_story_frame.dart';

class StepGuide extends StatefulWidget {
  const StepGuide({super.key});

  @override
  State<StepGuide> createState() => _StepGuideState();
}

class _StepGuideState extends State<StepGuide> {
  late PageController _pageController;
  int _page = 0;

  static const _cards = [
    _GuideCard(
      icon: Icons.campaign_outlined,
      title: 'Create an Echo',
      body:
          'An Echo is a claim, story, or observation. Post it and the community rates its credibility.',
      color: Color(0xFFE8F5E9),
      iconColor: Color(0xFF388E3C),
    ),
    _GuideCard(
      icon: Icons.verified_outlined,
      title: 'Proof it',
      body:
          'Attach links, screenshots, or sources. More proof = higher trust score for you.',
      color: Color(0xFFE3F2FD),
      iconColor: Color(0xFF1976D2),
    ),
    _GuideCard(
      icon: Icons.how_to_vote_outlined,
      title: 'Signal on others',
      body:
          'Mark Echoes as True, False, or Unverified. Your rating history builds your credibility.',
      color: Color(0xFFFFF3E0),
      iconColor: Color(0xFFF57C00),
    ),
    _GuideCard(
      icon: Icons.shield_outlined,
      title: 'Your trust level',
      body:
          'Start as Unverified. Verify your identity privately to unlock higher trust tiers.',
      color: Color(0xFFEDE7F6),
      iconColor: Color(0xFF7B1FA2),
    ),
    _GuideCard(
      icon: Icons.explore_outlined,
      title: 'Discover topics',
      body:
          'Follow categories you care about. Your feed surfaces the most-debated stories.',
      color: Color(0xFFE8EAF6),
      iconColor: Color(0xFF3949AB),
    ),
  ];

  @override
  void initState() {
    super.initState();
    _pageController = PageController(viewportFraction: 0.88);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _next() {
    if (_page < _cards.length - 1) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeOutCubic,
      );
    } else {
      context.read<OnboardingService>().nextStep();
    }
  }

  @override
  Widget build(BuildContext context) {
    final mediaHeight = MediaQuery.sizeOf(context).height;
    final compactHeight = mediaHeight < 680;

    return OnboardingStoryFrame(
      currentStep: 6,
      totalSteps: 7,
      title: context.l('Watch the loop once.'),
      body: context.l(
        'Create, proof, signal, and discover. These are the moves you will use every day.',
      ),
      sceneIcon: Icons.movie_filter_outlined,
      sceneLabel: context.l('a quick pass through the echo loop'),
      sceneBackground: AppColors.surfaceSecondary,
      footer: Row(
        children: [
          if (_page > 0)
            Expanded(
              child: OutlinedButton(
                onPressed: () => _pageController.previousPage(
                  duration: const Duration(milliseconds: 280),
                  curve: Curves.easeOutCubic,
                ),
                child: Text(context.l('Back')),
              ),
            ),
          if (_page > 0) const SizedBox(width: AppSpacing.md),
          Expanded(
            flex: 2,
            child: ElevatedButton(
              onPressed: _next,
              child: Text(
                _page == _cards.length - 1
                    ? context.l('Let\'s go')
                    : context.l('Next'),
              ),
            ),
          ),
        ],
      ),
      children: [
        SizedBox(
          height: compactHeight ? 236 : 286,
          child: PageView.builder(
            controller: _pageController,
            onPageChanged: (i) => setState(() => _page = i),
            itemCount: _cards.length,
            itemBuilder: (context, i) {
              return AnimatedBuilder(
                animation: _pageController,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: _GuideCardWidget(card: _cards[i]),
                ),
                builder: (context, child) {
                  var pageOffset = _page.toDouble();
                  if (_pageController.hasClients &&
                      _pageController.position.haveDimensions) {
                    pageOffset = _pageController.page ?? pageOffset;
                  }
                  final distance = (pageOffset - i).abs().clamp(0.0, 1.0);
                  final scale = 1 - (distance * 0.035);
                  final translateY = distance * 10;

                  return Transform.translate(
                    offset: Offset(0, translateY),
                    child: Transform.scale(scale: scale, child: child),
                  );
                },
              );
            },
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(_cards.length, (i) {
            return AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOutCubic,
              margin: const EdgeInsets.symmetric(horizontal: 3),
              width: _page == i ? 20 : 6,
              height: 6,
              decoration: BoxDecoration(
                color: _page == i
                    ? AppColors.fernGreen
                    : AppColors.fernGreen.withValues(alpha: 0.25),
                borderRadius: BorderRadius.circular(3),
              ),
            );
          }),
        ),
      ],
    );
  }
}

class _GuideCard {
  final IconData icon;
  final String title;
  final String body;
  final Color color;
  final Color iconColor;

  const _GuideCard({
    required this.icon,
    required this.title,
    required this.body,
    required this.color,
    required this.iconColor,
  });
}

class _GuideCardWidget extends StatelessWidget {
  final _GuideCard card;
  const _GuideCardWidget({required this.card});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxHeight < 260;
        final iconSize = compact ? 48.0 : 56.0;

        return Container(
          decoration: BoxDecoration(
            color: card.color,
            borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
            border: Border.all(color: AppColors.white.withValues(alpha: 0.65)),
          ),
          padding: EdgeInsets.all(compact ? AppSpacing.lg : AppSpacing.xl),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: iconSize,
                height: iconSize,
                decoration: BoxDecoration(
                  color: AppColors.white,
                  borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                  boxShadow: [
                    BoxShadow(
                      color: card.iconColor.withValues(alpha: 0.14),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Icon(
                  card.icon,
                  size: compact ? 24 : 28,
                  color: card.iconColor,
                ),
              ),
              SizedBox(height: compact ? AppSpacing.md : AppSpacing.lg),
              Text(
                context.l(card.title),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: AppTypography.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0,
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              Expanded(
                child: Text(
                  context.l(card.body),
                  overflow: TextOverflow.fade,
                  style: AppTypography.textTheme.bodyMedium?.copyWith(
                    color: AppColors.textSecondary,
                    height: 1.45,
                    letterSpacing: 0,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
