// profile screen
// shows user's reputation card, their echoes, and bond history
// accessible from the feed screen app bar

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../app/theme/colors.dart';
import '../../../../app/theme/spacing.dart';
import '../../../../app/theme/typography.dart';
import '../../../../shared/widgets/shimmer_loader.dart';
import '../providers/profile_provider.dart';
import '../widgets/reputation_card.dart';
import '../../../echo/presentation/widgets/echo_card.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../../auth/presentation/screens/identity_verification_screen.dart';

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profileAsync = ref.watch(profileProvider);

    return Scaffold(
      backgroundColor: AppColors.white,
      appBar: AppBar(
        title: Text('Profile', style: AppTypography.textTheme.titleLarge),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout_outlined, size: 20),
            onPressed: () {
              ref.read(authNotifierProvider.notifier).signOut();
            },
          ),
        ],
      ),
      body: profileAsync.when(
        loading: () => const Padding(
          padding: EdgeInsets.all(AppSpacing.xl),
          child: EchoCardShimmer(),
        ),
        error: (e, _) => Center(
          child: Text('could not load profile', style: AppTypography.textTheme.bodyMedium),
        ),
        data: (profile) => RefreshIndicator(
          color: AppColors.fernGreen,
          onRefresh: () => ref.refresh(profileProvider.future),
          child: ListView(
            padding: const EdgeInsets.all(AppSpacing.xl),
            children: [
              ReputationCard(profile: profile),

              const SizedBox(height: AppSpacing.lg),

              // identity verification prompt — only if not yet verified
              if (!profile.isIdentityVerified)
                GestureDetector(
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const IdentityVerificationScreen(),
                    ),
                  ),
                  child: Container(
                    padding: const EdgeInsets.all(AppSpacing.md),
                    decoration: BoxDecoration(
                      color: AppColors.fernGreenLight,
                      borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                      border: Border.all(
                        color: AppColors.fernGreen.withOpacity(0.3),
                      ),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.shield_outlined,
                            size: 18, color: AppColors.fernGreen),
                        const SizedBox(width: AppSpacing.sm),
                        Expanded(
                          child: Text(
                            'Verify your identity to increase your trust weight',
                            style: TextStyle(
                              fontSize: 13,
                              color: AppColors.fernGreenDark,
                              fontFamily: AppTypography.fontFamily,
                            ),
                          ),
                        ),
                        const Icon(Icons.chevron_right,
                            size: 16, color: AppColors.fernGreen),
                      ],
                    ),
                  ),
                ),

              if (!profile.isIdentityVerified)
                const SizedBox(height: AppSpacing.lg),

              // echoes list
              Text('Echoes', style: AppTypography.textTheme.titleMedium),
              const SizedBox(height: AppSpacing.sm),

              if (profile.echoes.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: AppSpacing.xl),
                  child: Text(
                    'No echoes yet',
                    style: AppTypography.textTheme.bodySmall,
                    textAlign: TextAlign.center,
                  ),
                ),

              ...profile.echoes.map((echo) => Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                child: EchoCard(
                  echo: echo,
                  onTap: () => context.push('/feed/echo/${echo.id}'),
                ),
              )),
            ],
          ),
        ),
      ),
    );
  }
}