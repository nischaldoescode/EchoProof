import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:didit_sdk/sdk_flutter.dart';
import '../../../../app/theme/colors.dart';
import '../../../../app/theme/spacing.dart';
import '../../../../core/utils/logger.dart';
import '../../../../core/utils/snack.dart';

class IdentityVerificationScreen extends StatefulWidget {
  const IdentityVerificationScreen({super.key});

  @override
  State<IdentityVerificationScreen> createState() =>
      _IdentityVerificationScreenState();
}

class _IdentityVerificationScreenState extends State<IdentityVerificationScreen>
    with TickerProviderStateMixin {
  static const _diditWorkflowId = String.fromEnvironment(
    'DIDIT_WORKFLOW_ID',
    defaultValue: '',
  );

  RealtimeChannel? _verificationChannel;

  void _subscribeToVerificationUpdates() {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) return;

    _verificationChannel = Supabase.instance.client
        .channel('users_private:$userId')
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'users_private',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'id',
            value: userId,
          ),
          callback: (payload) {
            final newRecord = payload.newRecord;
            final isVerified =
                newRecord['is_identity_verified'] as bool? ?? false;
            if (isVerified && mounted) {
              _showResultSheet(
                icon: Icons.verified_rounded,
                iconColor: AppColors.fernGreen,
                title: 'Identity verified!',
                body:
                    'Your identity has been confirmed. Your trust tier has been updated.',
                isSuccess: true,
              );
            }
          },
        )
        .subscribe();
  }

  bool _isLoading = false;

  late final AnimationController _entranceCtrl;
  late final AnimationController _pulseCtrl;
  late final Animation<double> _fade;
  late final Animation<Offset> _slide;
  late final Animation<double> _pulse;

  @override
  void initState() {
    super.initState();
    _entranceCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat(reverse: true);

    _fade = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _entranceCtrl, curve: Curves.easeOut),
    );
    _slide = Tween<Offset>(
      begin: const Offset(0, 0.06),
      end: Offset.zero,
    ).animate(
        CurvedAnimation(parent: _entranceCtrl, curve: Curves.easeOutCubic));
    _pulse = Tween<double>(begin: 1.0, end: 1.05).animate(
      CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut),
    );

    _subscribeToVerificationUpdates();
    _entranceCtrl.forward();
  }

  @override
  void dispose() {
    _entranceCtrl.dispose();
    _pulseCtrl.dispose();
    _verificationChannel?.unsubscribe();
    super.dispose();
  }

  // Block back navigation mid-verification
  Future<bool> _onWillPop() async {
    if (_isLoading) {
      showInfoSnack(context, 'Please complete or cancel verification first.');
      return false;
    }
    return true;
  }

  Future<void> _startVerification() async {
    if (_isLoading) return;
    setState(() {
      _isLoading = true;
    });

    HapticFeedback.mediumImpact();

    final supabase = Supabase.instance.client;
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) {
      setState(() => _isLoading = false);
      return;
    }

    try {
      // Get session token from your edge function
      final response = await supabase.functions.invoke(
        'create-didit-session',
        body: {
          'user_id': userId,
          'workflow_id': _diditWorkflowId,
          'redirect_uri': 'echoproof://verify-complete',
        },
      );

      final sessionToken = response.data?['session_token'] as String?;

      VerificationResult result;

      if (sessionToken != null && sessionToken.isNotEmpty) {
        // Use session token (recommended)
        result = await DiditSdk.startVerification(
          sessionToken,
          config: const DiditConfig(loggingEnabled: true),
        );
      } else {
        // Fallback to workflow ID
        result = await DiditSdk.startVerificationWithWorkflow(
          _diditWorkflowId,
          vendorData: userId,
          config: const DiditConfig(loggingEnabled: true),
        );
      }

      if (!mounted) return;

      setState(() {
        _isLoading = false;
      });

      _handleResult(result);
    } catch (e) {
      AppLogger.error('verification: error $e');
      if (!mounted) return;
      setState(() => _isLoading = false);

      // Parse cooldown error from edge function
      String errorMessage = 'Could not start verification. Please try again.';
      try {
        if (e.toString().contains('verification_cooldown')) {
          errorMessage = 'You can re-apply after your 30-day cooldown period.';
        } else if (e.toString().contains('rate_limited')) {
          errorMessage = 'Too many attempts today. Please try again tomorrow.';
        }
      } catch (_) {}

      showInfoSnack(context, errorMessage);
    }
  }

  void _handleResult(VerificationResult result) {
    switch (result) {
      case VerificationCompleted(:final session):
        switch (session.status) {
          case VerificationStatus.approved:
            HapticFeedback.heavyImpact();
            _showResultSheet(
              icon: Icons.verified_rounded,
              iconColor: AppColors.fernGreen,
              title: 'Identity verified!',
              body:
                  'Your identity has been confirmed. Your trust tier will update shortly.',
              isSuccess: true,
            );
          case VerificationStatus.pending:
            _showResultSheet(
              icon: Icons.hourglass_top_rounded,
              iconColor: AppColors.statusUnderReview,
              title: 'Under review',
              body:
                  'Your verification is being reviewed. This usually takes a few minutes.',
              isSuccess: false,
            );
          case VerificationStatus.declined:
            _showResultSheet(
              icon: Icons.cancel_outlined,
              iconColor: AppColors.sunsetCoral,
              title: 'Verification declined',
              body:
                  'We could not verify your identity. Please try again with a valid ID.',
              isSuccess: false,
            );
        }
      case VerificationCancelled():
        showInfoSnack(context, 'Verification Canceled');

      case VerificationFailed(:final error):
        AppLogger.error('verification: failed ${error.type} ${error.message}');
        _showResultSheet(
          icon: Icons.error_outline_rounded,
          iconColor: AppColors.sunsetCoral,
          title: 'Verification failed',
          body: 'Something went wrong: ${error.message}. Please try again.',
          isSuccess: false,
        );
    }
  }

  void _showResultSheet({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String body,
    required bool isSuccess,
  }) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      isDismissible: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) => SingleChildScrollView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: EdgeInsets.fromLTRB(
          24,
          20,
          24,
          MediaQuery.viewInsetsOf(sheetContext).bottom + 40,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.borderMedium,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 24),
            TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: 1),
              duration: const Duration(milliseconds: 500),
              curve: Curves.easeOutBack,
              builder: (_, v, __) => Transform.scale(
                scale: v,
                child: Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    color: iconColor.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(icon, color: iconColor, size: 36),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              title,
              style: GoogleFonts.josefinSans(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: AppColors.charcoal,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              body,
              style: GoogleFonts.josefinSans(
                fontSize: 14,
                color: AppColors.textSecondary,
                height: 1.5,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => Navigator.pop(context),
                style: ElevatedButton.styleFrom(
                  backgroundColor:
                      isSuccess ? AppColors.fernGreen : AppColors.charcoal,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  elevation: 0,
                ),
                child: Text(
                  isSuccess ? 'Great!' : 'Got it',
                  style: GoogleFonts.josefinSans(fontWeight: FontWeight.w600),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_isLoading,
      onPopInvokedWithResult: (didPop, _) async {
        if (!didPop) await _onWillPop();
      },
      child: Scaffold(
        backgroundColor: const Color(0xFFF5FAF7),
        appBar: AppBar(
          title: Text(
            'Verify identity',
            style: GoogleFonts.josefinSans(
                fontSize: 18, fontWeight: FontWeight.w600),
          ),
          backgroundColor: Colors.transparent,
          elevation: 0,
        ),
        body: SafeArea(
          child: FadeTransition(
            opacity: _fade,
            child: SlideTransition(
              position: _slide,
              child: ListView(
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                padding: EdgeInsets.only(
                  left: AppSpacing.xl,
                  right: AppSpacing.xl,
                  top: AppSpacing.xl,
                  // Bottom padding accounts for home gesture bar
                  bottom: MediaQuery.paddingOf(context).bottom + AppSpacing.xxl,
                ),
                children: [
                  const SizedBox(height: AppSpacing.xl),

                  // Hero icon with pulse
                  Center(
                    child: AnimatedBuilder(
                      animation: _pulseCtrl,
                      builder: (_, __) => Transform.scale(
                        scale: _isLoading ? 1.0 : _pulse.value,
                        child: Container(
                          width: 88,
                          height: 88,
                          decoration: BoxDecoration(
                            color: AppColors.fernGreenLight,
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color:
                                    AppColors.fernGreen.withValues(alpha: 0.2),
                                blurRadius: 20,
                                spreadRadius: 4,
                              ),
                            ],
                          ),
                          child: const Icon(
                            Icons.verified_user_rounded,
                            size: 44,
                            color: AppColors.fernGreen,
                          ),
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: AppSpacing.xl),

                  Text(
                    'Verify your identity',
                    style: GoogleFonts.josefinSans(
                      fontSize: 24,
                      fontWeight: FontWeight.w700,
                      color: AppColors.charcoal,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    'Powered by Didit — bank-grade KYC in under 2 minutes.',
                    style: GoogleFonts.josefinSans(
                      fontSize: 14,
                      color: AppColors.textSecondary,
                      height: 1.5,
                    ),
                    textAlign: TextAlign.center,
                  ),

                  const SizedBox(height: AppSpacing.lg),
                  const _VerificationPillRail(),

                  const SizedBox(height: AppSpacing.lg),
                  const _VerificationTimeline(),

                  const SizedBox(height: AppSpacing.xxl),

                  // What didit checks
                  Container(
                    padding: const EdgeInsets.all(AppSpacing.xl),
                    decoration: BoxDecoration(
                      color: AppColors.fernGreenLight,
                      borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'What Didit verifies',
                          style: GoogleFonts.josefinSans(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: AppColors.charcoal,
                          ),
                        ),
                        const SizedBox(height: AppSpacing.md),
                        ...[
                          'Government-issued ID (passport, national ID, driving licence)',
                          'Passive liveness — no blinking or head turns',
                          'Face match — selfie vs ID photo',
                          'AI deepfake and fraud detection',
                          'NFC e-passport reading (where supported)',
                          '14,000+ documents across 220+ countries',
                        ].map((item) => Padding(
                              padding:
                                  const EdgeInsets.only(top: AppSpacing.xs),
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

                  // Privacy note
                  Container(
                    padding: const EdgeInsets.all(AppSpacing.lg),
                    decoration: BoxDecoration(
                      color: AppColors.softSand,
                      borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                      border: Border.all(color: AppColors.borderSubtle),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.lock_outline,
                            size: 18, color: AppColors.textTertiary),
                        const SizedBox(width: AppSpacing.sm),
                        Expanded(
                          child: Text(
                            'Your identity is verified by Didit and stays private. Only your trust level is visible to others.',
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

                  _BenefitRow(
                    icon: Icons.trending_up_outlined,
                    title: 'Higher trust weight',
                    desc: 'Your votes count more — real people matter more.',
                  ),
                  _BenefitRow(
                    icon: Icons.verified_outlined,
                    title: 'Verified badge',
                    desc: 'A visible verified ring on your avatar.',
                  ),
                  _BenefitRow(
                    icon: Icons.link_outlined,
                    title: 'Portable reputation',
                    desc: 'Your trust tier is anchored on-chain.',
                  ),

                  const SizedBox(height: AppSpacing.xxl),

                  // CTA button
                  ScaleTransition(
                    scale: _isLoading
                        ? const AlwaysStoppedAnimation(0.97)
                        : const AlwaysStoppedAnimation(1.0),
                    child: SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _isLoading ? null : _startVerification,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.charcoal,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                          elevation: 0,
                        ),
                        child: AnimatedSwitcher(
                          duration: const Duration(milliseconds: 200),
                          child: _isLoading
                              ? Row(
                                  key: const ValueKey('loading'),
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.white,
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    Text(
                                      'Starting verification...',
                                      style: GoogleFonts.josefinSans(
                                        fontSize: 15,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                )
                              : Text(
                                  key: const ValueKey('idle'),
                                  'Start verification',
                                  style: GoogleFonts.josefinSans(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: AppSpacing.md),
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
          ),
        ),
      ),
    );
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
                Text(title,
                    style: GoogleFonts.josefinSans(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppColors.charcoal)),
                Text(desc,
                    style: GoogleFonts.josefinSans(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                        height: 1.5)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _VerificationPillRail extends StatelessWidget {
  const _VerificationPillRail();

  @override
  Widget build(BuildContext context) {
    const items = [
      (icon: Icons.lock_outline_rounded, label: 'Private'),
      (icon: Icons.face_retouching_natural_rounded, label: 'Human'),
      (icon: Icons.trending_up_rounded, label: 'Trust lift'),
    ];

    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 520),
      curve: Curves.easeOutCubic,
      builder: (context, value, child) => Opacity(
        opacity: value,
        child: Transform.translate(
          offset: Offset(0, (1 - value) * 10),
          child: child,
        ),
      ),
      child: Row(
        children: [
          for (final item in items) ...[
            Expanded(
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.sm,
                  vertical: AppSpacing.sm,
                ),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppColors.borderSubtle),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.035),
                      blurRadius: 12,
                      offset: const Offset(0, 5),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    Icon(item.icon, size: 18, color: AppColors.fernGreenDark),
                    const SizedBox(height: 5),
                    Text(
                      item.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.josefinSans(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: AppColors.charcoal,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (item != items.last) const SizedBox(width: AppSpacing.sm),
          ],
        ],
      ),
    );
  }
}

class _VerificationTimeline extends StatelessWidget {
  const _VerificationTimeline();

  @override
  Widget build(BuildContext context) {
    const steps = [
      (
        icon: Icons.badge_outlined,
        title: 'Scan ID',
        body: 'Use a clear passport, national ID, or driving licence.'
      ),
      (
        icon: Icons.face_retouching_natural_rounded,
        title: 'Liveness',
        body: 'A quick passive face check confirms you are a real person.'
      ),
      (
        icon: Icons.shield_outlined,
        title: 'Trust update',
        body:
            'EchoProof receives only the verification result and updates trust.'
      ),
    ];

    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
        border: Border.all(color: AppColors.borderSubtle),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.035),
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        children: [
          for (var i = 0; i < steps.length; i++) ...[
            TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: 1),
              duration: Duration(milliseconds: 360 + (i * 90)),
              curve: Curves.easeOutCubic,
              builder: (context, value, child) => Opacity(
                opacity: value,
                child: Transform.translate(
                  offset: Offset(0, (1 - value) * 10),
                  child: child,
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: AppColors.fernGreenLight,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      steps[i].icon,
                      size: 18,
                      color: AppColors.fernGreenDark,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          steps[i].title,
                          style: GoogleFonts.josefinSans(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: AppColors.charcoal,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          steps[i].body,
                          style: GoogleFonts.josefinSans(
                            fontSize: 12,
                            color: AppColors.textSecondary,
                            height: 1.45,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            if (i != steps.length - 1)
              Padding(
                padding: const EdgeInsets.only(left: 16),
                child: Container(
                  width: 2,
                  height: 18,
                  color: AppColors.borderSubtle,
                ),
              ),
          ],
        ],
      ),
    );
  }
}
