// identity verification screen — powered by Didit
// opens didit's hosted verification flow in an external browser
// didit sends webhook to supabase when complete
// docs: https://verification.didit.me

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../../app/theme/colors.dart';
import '../../../../app/theme/spacing.dart';

class IdentityVerificationScreen extends StatelessWidget {
  const IdentityVerificationScreen({super.key});

  // didit workflow id — set this from your didit console
  static const _diditWorkflowId = String.fromEnvironment(
    'DIDIT_WORKFLOW_ID',
    defaultValue: '',
  );


  @override
  Widget build(BuildContext context) {
    final userId = Supabase.instance.client.auth.currentUser?.id ?? '';

    return Scaffold(
      backgroundColor: const Color(0xFFF5FAF7),
      appBar: AppBar(
        title: Text(
          'Verify identity',
          style: GoogleFonts.josefinSans(
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // what we check
            Container(
              padding: const EdgeInsets.all(AppSpacing.xl),
              decoration: BoxDecoration(
                color: AppColors.fernGreenLight,
                borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(
                    Icons.verified_user_outlined,
                    color: AppColors.fernGreen,
                    size: 32,
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Text(
                    'What Didit verifies',
                    style: GoogleFonts.josefinSans(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: AppColors.charcoal,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  ...[
                    'Government-issued ID (passport, national ID, driving licence)',
                    'Passive liveness detection — no blinking or head turning needed',
                    'Face match — selfie vs ID photo',
                    'AI-powered deepfake and fraud detection',
                    '14,000+ documents across 220+ countries supported',
                  ].map((item) => Padding(
                        padding: const EdgeInsets.only(top: AppSpacing.xs),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Padding(
                              padding: EdgeInsets.only(top: 2),
                              child: Icon(
                                Icons.check_circle_outline,
                                size: 14,
                                color: AppColors.fernGreen,
                              ),
                            ),
                            const SizedBox(width: AppSpacing.sm),
                            Expanded(
                              child: Text(
                                item,
                                style: GoogleFonts.josefinSans(
                                  fontSize: 13,
                                  color: AppColors.textSecondary,
                                  height: 1.5,
                                ),
                              ),
                            ),
                          ],
                        ),
                      )),
                ],
              ),
            ),

            const SizedBox(height: AppSpacing.lg),

            // privacy note
            Container(
              padding: const EdgeInsets.all(AppSpacing.lg),
              decoration: BoxDecoration(
                color: AppColors.softSand,
                borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                border: Border.all(color: AppColors.borderSubtle),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.lock_outline,
                    size: 18,
                    color: AppColors.textTertiary,
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      'Your real identity is verified by Didit and stays private. Only your trust level is visible to other users on Echoproof.',
                      style: GoogleFonts.josefinSans(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                        height: 1.5,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: AppSpacing.lg),

            // what changes after verification
            _BenefitRow(
              icon: Icons.trending_up_outlined,
              title: 'Higher trust weight',
              desc:
                  'Your votes count more when the community knows you are a real person.',
            ),
            _BenefitRow(
              icon: Icons.verified_outlined,
              title: 'Verified badge',
              desc: 'A visible verified ring on your avatar in the feed.',
            ),
            _BenefitRow(
              icon: Icons.link_outlined,
              title: 'Portable reputation',
              desc: 'Your trust tier is anchored on-chain — provable anywhere.',
            ),

            const Spacer(),

            // start verification
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => _startVerification(context, userId),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.charcoal,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                child: Text(
                  'Start verification',
                  style: GoogleFonts.josefinSans(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),

            const SizedBox(height: AppSpacing.sm),

            Center(
              child: Text(
                'Powered by Didit — bank-grade identity verification',
                style: GoogleFonts.josefinSans(
                  fontSize: 11,
                  color: AppColors.textTertiary,
                ),
                textAlign: TextAlign.center,
              ),
            ),

            const SizedBox(height: AppSpacing.xl),
          ],
        ),
      ),
    );
  }

  Future<void> _startVerification(BuildContext context, String userId) async {
    // create a didit session via supabase edge function
    // the edge function calls didit's POST /v3/session/ with vendor_data = userId
    // and returns the session URL

    final supabase = Supabase.instance.client;
    final session = supabase.auth.currentSession;
    if (session == null) return;

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Opening verification...'),
        behavior: SnackBarBehavior.floating,
        margin: EdgeInsets.only(bottom: 80, left: 16, right: 16),
      ),
    );

    try {
      final response = await supabase.functions.invoke(
        'create-didit-session',
        body: {
          'user_id': userId,
          'workflow_id': _diditWorkflowId,
          'redirect_uri': 'echoproof://verify-complete',
        },
      );

      final sessionUrl = response.data?['session_url'] as String?;
      if (sessionUrl == null) throw Exception('no session url returned');

      final uri = Uri.parse(sessionUrl);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Verification failed: $e'),
            backgroundColor: AppColors.sunsetCoral,
            margin: const EdgeInsets.only(bottom: 88, left: 16, right: 16),

          ),
        );
      }
    }
  }
}

class _BenefitRow extends StatelessWidget {
  const _BenefitRow({
    required this.icon,
    required this.title,
    required this.desc,
  });
  final IconData icon;
  final String title;
  final String desc;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: AppColors.fernGreenLight,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 18, color: AppColors.fernGreen),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: GoogleFonts.josefinSans(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.charcoal,
                  ),
                ),
                Text(
                  desc,
                  style: GoogleFonts.josefinSans(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                    height: 1.5,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
