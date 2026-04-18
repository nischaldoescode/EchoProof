// identity verification screen
// opens persona's hosted verification flow in a webview
// persona handles: government id ocr, liveness detection, deepfake detection
// result comes back via webhook to supabase edge function
// user sees a pending state until webhook confirms

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../../app/theme/colors.dart';
import '../../../../app/theme/spacing.dart';
import '../../../../app/theme/typography.dart';
import '../providers/auth_provider.dart';

class IdentityVerificationScreen extends ConsumerWidget {
  const IdentityVerificationScreen({super.key});

  // persona inquiry url format:
  // https://withpersona.com/verify?inquiry-template-id={templateId}&reference-id={userId}
  // template id comes from persona dashboard after creating an inquiry template
  // reference id links the verification result back to your user row

  static const _personaTemplateId = String.fromEnvironment('PERSONA_TEMPLATE_ID');

  String _buildPersonaUrl(String userId) {
    return 'https://withpersona.com/verify'
        '?inquiry-template-id=$_personaTemplateId'
        '&reference-id=$userId'
        '&redirect-uri=echoproof://verify-complete';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final client = ref.watch(supabaseProvider);
    final userId = client.auth.currentUser?.id ?? '';

    return Scaffold(
      backgroundColor: AppColors.white,
      appBar: AppBar(title: Text('Verify identity', style: AppTypography.textTheme.titleLarge)),
      body: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(AppSpacing.xl),
              decoration: BoxDecoration(
                color: AppColors.fernGreenLight,
                borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.verified_user_outlined, color: AppColors.fernGreen, size: 32),
                  const SizedBox(height: AppSpacing.md),
                  Text('What we verify', style: AppTypography.textTheme.titleMedium),
                  const SizedBox(height: AppSpacing.sm),
                  ...const [
                    'Government-issued ID (passport, national ID, driving licence)',
                    'Liveness check — a short selfie video',
                    'Deepfake and fraud detection',
                  ].map((item) => Padding(
                    padding: const EdgeInsets.only(top: AppSpacing.xs),
                    child: Row(
                      children: [
                        const Icon(Icons.check_circle_outline, size: 16, color: AppColors.fernGreen),
                        const SizedBox(width: AppSpacing.sm),
                        Expanded(child: Text(item, style: AppTypography.textTheme.bodySmall)),
                      ],
                    ),
                  )),
                ],
              ),
            ),

            const SizedBox(height: AppSpacing.xl),

            Container(
              padding: const EdgeInsets.all(AppSpacing.lg),
              decoration: BoxDecoration(
                color: AppColors.softSand,
                borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                border: Border.all(color: AppColors.borderSubtle),
              ),
              child: Row(
                children: [
                  const Icon(Icons.lock_outline, size: 18, color: AppColors.textTertiary),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      'Your real identity is never shown publicly. Only your trust tier is visible.',
                      style: AppTypography.textTheme.bodySmall,
                    ),
                  ),
                ],
              ),
            ),

            const Spacer(),

            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () async {
                  final url = Uri.parse(_buildPersonaUrl(userId));
                  if (await canLaunchUrl(url)) {
                    await launchUrl(url, mode: LaunchMode.externalApplication);
                  }
                },
                child: const Text('Start verification'),
              ),
            ),

            const SizedBox(height: AppSpacing.md),

            Center(
              child: Text(
                'Powered by Persona — bank-grade identity verification',
                style: AppTypography.textTheme.labelMedium,
                textAlign: TextAlign.center,
              ),
            ),

            const SizedBox(height: AppSpacing.xl),
          ],
        ),
      ),
    );
  }
}