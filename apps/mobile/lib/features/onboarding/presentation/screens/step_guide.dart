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
import '../widgets/onboarding_progress.dart';

class StepGuide extends StatefulWidget {
  const StepGuide({super.key});

  @override
  State<StepGuide> createState() => _StepGuideState();
}

class _StepGuideState extends State<StepGuide> with TickerProviderStateMixin {
  late PageController _pageController;
  late AnimationController _entryAnim;
  late Animation<double> _fade;
  late Animation<Offset> _slide;
  int _page = 0;

  static const _cards = [
    _GuideCard(
      icon: Icons.campaign_outlined,
      title: 'Create an Echo',
      body:
          'An Echo is a claim, story, or observation. Post it — the community rates its credibility.',
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
    _pageController = PageController();
    _entryAnim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 450),
    );
    _fade = CurvedAnimation(parent: _entryAnim, curve: Curves.easeOut);
    _slide = Tween<Offset>(
      begin: const Offset(0, 0.05),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _entryAnim, curve: Curves.easeOut));
    _entryAnim.forward();
  }

  @override
  void dispose() {
    _pageController.dispose();
    _entryAnim.dispose();
    super.dispose();
  }

  void _next() {
    if (_page < _cards.length - 1) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    } else {
      context.read<OnboardingService>().nextStep();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.white,
      body: SafeArea(
        child: FadeTransition(
          opacity: _fade,
          child: SlideTransition(
            position: _slide,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.xl,
                    AppSpacing.xl,
                    AppSpacing.xl,
                    0,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const OnboardingProgress(currentStep: 5, totalSteps: 6),
                      const SizedBox(height: AppSpacing.xxl),
                      Text(
                        context.l('Here\'s how it works'),
                        style: AppTypography.textTheme.headlineMedium,
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        context.l('Swipe through to see what you can do.'),
                        style: AppTypography.textTheme.bodyMedium?.copyWith(
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.xxl),
                SizedBox(
                  height: 280,
                  child: PageView.builder(
                    controller: _pageController,
                    onPageChanged: (i) => setState(() => _page = i),
                    itemCount: _cards.length,
                    itemBuilder: (context, i) {
                      return Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        child: _GuideCardWidget(card: _cards[i]),
                      );
                    },
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),
                // dot indicator
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(_cards.length, (i) {
                    return AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
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
                const Spacer(),
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.xl,
                    0,
                    AppSpacing.xl,
                    AppSpacing.xl,
                  ),
                  child: Row(
                    children: [
                      if (_page > 0)
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => _pageController.previousPage(
                              duration: const Duration(milliseconds: 300),
                              curve: Curves.easeInOut,
                            ),
                            child: Text(context.l('Back')),
                          ),
                        ),
                      if (_page > 0) const SizedBox(width: 12),
                      Expanded(
                        flex: 2,
                        child: ElevatedButton(
                          onPressed: _next,
                          child: Text(
                            _page == _cards.length - 1
                                ? context.l('Let\'s go!')
                                : context.l('Next'),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
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
    return Container(
      decoration: BoxDecoration(
        color: card.color,
        borderRadius: BorderRadius.circular(24),
      ),
      padding: const EdgeInsets.all(28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: card.iconColor.withValues(alpha: 0.15),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Icon(card.icon, size: 28, color: card.iconColor),
          ),
          const SizedBox(height: 20),
          Text(
            context.l(card.title),
            style: AppTypography.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            context.l(card.body),
            style: AppTypography.textTheme.bodyMedium?.copyWith(
              color: AppColors.textSecondary,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}
