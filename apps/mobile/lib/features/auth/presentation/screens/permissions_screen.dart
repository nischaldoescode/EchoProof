// permissions screen
// shown once after OTP verification, before onboarding
// explains each permission clearly — like a human, not legalese
// if denied, shows a button to grant permission in settings

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../../../app/theme/colors.dart';
import '../../../../app/theme/spacing.dart';
import '../../../../core/services/push_notification_service.dart';
import '../../../auth/presentation/services/auth_service.dart';
import '../../../onboarding/presentation/services/onboarding_service.dart';
import 'package:provider/provider.dart';
import 'permission_sheet.dart';

class PermissionsScreen extends StatefulWidget {
  const PermissionsScreen({super.key});

  @override
  State<PermissionsScreen> createState() => _PermissionsScreenState();
}

class _PermissionsScreenState extends State<PermissionsScreen> {
  final Map<Permission, PermissionStatus> _statuses = {};
  bool _allGranted = false;

  static const _permissions = [
    _PermissionInfo(
      permission: Permission.notification,
      icon: Icons.notifications_outlined,
      title: 'Notifications',
      reason:
          'We notify you when your echo gets verified, someone supports your claim, or a community member you follow posts something new.',
      deniedHint:
          'Without notifications, you will miss real-time trust updates on your echoes.',
    ),
    _PermissionInfo(
      permission: Permission.photos,
      icon: Icons.photo_outlined,
      title: 'Photo library',
      reason:
          'When you attach evidence to an echo, you can pick an image from your gallery. We never read your photos without you explicitly choosing one.',
      deniedHint:
          'Without this, you can only attach proof by taking a new photo — not from your gallery.',
    ),
    _PermissionInfo(
      permission: Permission.camera,
      icon: Icons.camera_alt_outlined,
      title: 'Camera',
      reason:
          'Used when you take a photo as evidence for an echo, or during identity verification.',
      deniedHint: 'Without camera access, you cannot take photos as proof.',
    ),
  ];

  @override
  void initState() {
    super.initState();
    _checkStatuses();
  }

  Future<void> _checkStatuses() async {
    for (final info in _permissions) {
      _statuses[info.permission] = await info.permission.status;
    }
    _updateAllGranted();
    if (mounted) setState(() {});
  }

  void _updateAllGranted() {
    _allGranted = _permissions.every((p) {
      final status = _statuses[p.permission];
      return status != null && PermissionsSheet.isAllowed(status);
    });
  }

  Future<void> _requestAll() async {
    for (final info in _permissions) {
      final status = await info.permission.request();
      _statuses[info.permission] = status;
    }
    _updateAllGranted();
    if (mounted) setState(() {});
    await PushNotificationService.instance.initialize();
    if (_allGranted) await PermissionsSheet.markPromptSeen();
  }

  Future<void> _requestSingle(Permission p) async {
    final status = _statuses[p];
    if (status == PermissionStatus.permanentlyDenied) {
      await openAppSettings();
    } else {
      _statuses[p] = await p.request();
      _updateAllGranted();
      if (mounted) setState(() {});
      if (_allGranted) await PermissionsSheet.markPromptSeen();
    }
  }

  Future<void> _proceed(BuildContext context) async {
    await PermissionsSheet.markPromptSeen();
    if (!context.mounted) return;

    final auth = context.read<AuthService>();
    // If user already has a username (returning user who went through permissions again),
    // mark done and go to feed.
    if (auth.hasUsername) {
      context.read<OnboardingService>().complete();
      context.go('/feed');
      return;
    }
    // New user: go to onboarding (username + categories selection).
    // Do NOT call onboarding.complete() here — that happens in StepFirstEcho/StepUsername.
    // Do NOT call markOnboardingComplete() here either.
    context.go('/onboarding');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5FAF7),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: AppSpacing.xl),

              Text(
                'A few quick permissions',
                style: GoogleFonts.josefinSans(
                  fontSize: 26,
                  fontWeight: FontWeight.w700,
                  color: AppColors.charcoal,
                ),
              ),

              const SizedBox(height: AppSpacing.sm),

              Text(
                'We only ask for what we actually need. Tap each one to learn why.',
                style: GoogleFonts.josefinSans(
                  fontSize: 14,
                  color: AppColors.textSecondary,
                  height: 1.5,
                ),
              ),

              const SizedBox(height: AppSpacing.xxl),

              // permission cards
              ..._permissions.map((info) {
                final status = _statuses[info.permission];
                final granted =
                    status != null && PermissionsSheet.isAllowed(status);
                final denied = status == PermissionStatus.permanentlyDenied;

                return _PermissionCard(
                  info: info,
                  granted: granted,
                  isDenied: denied,
                  onRequest: () => _requestSingle(info.permission),
                );
              }),

              const Spacer(),

              // main CTA
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _allGranted
                      ? () async {
                          await PushNotificationService.instance.initialize();
                          if (!context.mounted) return;
                          await _proceed(context);
                        }
                      : _requestAll,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.charcoal,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: Text(
                    _allGranted ? 'Continue' : 'Allow all and continue',
                    style: GoogleFonts.josefinSans(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),

              const SizedBox(height: AppSpacing.md),

              // skip
              Center(
                child: TextButton(
                  onPressed: () => _proceed(context),
                  child: Text(
                    'Skip for now',
                    style: GoogleFonts.josefinSans(
                      fontSize: 13,
                      color: AppColors.textTertiary,
                    ),
                  ),
                ),
              ),

              const SizedBox(height: AppSpacing.xl),
            ],
          ),
        ),
      ),
    );
  }
}

class _PermissionInfo {
  const _PermissionInfo({
    required this.permission,
    required this.icon,
    required this.title,
    required this.reason,
    required this.deniedHint,
  });
  final Permission permission;
  final IconData icon;
  final String title;
  final String reason;
  final String deniedHint;
}

class _PermissionCard extends StatefulWidget {
  const _PermissionCard({
    required this.info,
    required this.granted,
    required this.isDenied,
    required this.onRequest,
  });
  final _PermissionInfo info;
  final bool granted;
  final bool isDenied;
  final VoidCallback onRequest;

  @override
  State<_PermissionCard> createState() => _PermissionCardState();
}

class _PermissionCardState extends State<_PermissionCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      margin: const EdgeInsets.only(bottom: AppSpacing.md),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: widget.granted
              ? AppColors.fernGreen.withValues(alpha: 0.25)
              : AppColors.borderSubtle,
          width: widget.granted ? 1.5 : 1,
        ),
      ),
      child: Column(
        children: [
          // header row
          InkWell(
            onTap: () => setState(() => _expanded = !_expanded),
            borderRadius: BorderRadius.circular(16),
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: widget.granted
                          ? AppColors.fernGreenLight
                          : AppColors.softSand,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      widget.info.icon,
                      size: 20,
                      color: widget.granted
                          ? AppColors.fernGreen
                          : AppColors.textTertiary,
                    ),
                  ),

                  const SizedBox(width: AppSpacing.md),

                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.info.title,
                          style: GoogleFonts.josefinSans(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: AppColors.charcoal,
                          ),
                        ),
                        Text(
                          widget.granted
                              ? 'Allowed'
                              : widget.isDenied
                                  ? 'Denied — open settings to allow'
                                  : 'Tap to allow',
                          style: GoogleFonts.josefinSans(
                            fontSize: 12,
                            color: widget.granted
                                ? AppColors.fernGreen
                                : widget.isDenied
                                    ? AppColors.sunsetCoral
                                    : AppColors.textTertiary,
                          ),
                        ),
                      ],
                    ),
                  ),

                  // granted checkmark or allow button
                  if (widget.granted)
                    const Icon(
                      Icons.check_circle_rounded,
                      color: AppColors.fernGreen,
                      size: 22,
                    )
                  else if (widget.isDenied)
                    TextButton(
                      onPressed: widget.onRequest,
                      style: TextButton.styleFrom(
                        foregroundColor: AppColors.sunsetCoral,
                        padding: EdgeInsets.zero,
                      ),
                      child: Text(
                        'Open settings',
                        style: GoogleFonts.josefinSans(fontSize: 12),
                      ),
                    )
                  else
                    TextButton(
                      onPressed: widget.onRequest,
                      style: TextButton.styleFrom(
                        foregroundColor: AppColors.fernGreen,
                        padding: EdgeInsets.zero,
                      ),
                      child: Text(
                        'Allow',
                        style: GoogleFonts.josefinSans(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),

                  const SizedBox(width: AppSpacing.sm),

                  // expand arrow
                  AnimatedRotation(
                    turns: _expanded ? 0.5 : 0,
                    duration: const Duration(milliseconds: 200),
                    child: const Icon(
                      Icons.expand_more_rounded,
                      size: 18,
                      color: AppColors.textTertiary,
                    ),
                  ),
                ],
              ),
            ),
          ),

          // expanded reason
          AnimatedCrossFade(
            duration: const Duration(milliseconds: 250),
            crossFadeState: _expanded
                ? CrossFadeState.showFirst
                : CrossFadeState.showSecond,
            firstChild: Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg,
                0,
                AppSpacing.lg,
                AppSpacing.lg,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    height: 1,
                    color: AppColors.borderSubtle,
                    margin: const EdgeInsets.only(bottom: AppSpacing.md),
                  ),
                  Text(
                    widget.info.reason,
                    style: GoogleFonts.josefinSans(
                      fontSize: 13,
                      color: AppColors.textSecondary,
                      height: 1.6,
                    ),
                  ),
                  if (!widget.granted) ...[
                    const SizedBox(height: AppSpacing.sm),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(
                          Icons.info_outline,
                          size: 13,
                          color: AppColors.textTertiary,
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            widget.info.deniedHint,
                            style: GoogleFonts.josefinSans(
                              fontSize: 12,
                              color: AppColors.textTertiary,
                              fontStyle: FontStyle.italic,
                              height: 1.5,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            secondChild: const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }
}
