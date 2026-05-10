// settings screen
// account, notifications, subscription, privacy, about

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:package_info_plus/package_info_plus.dart';
import '../../../../app/theme/colors.dart';
import '../../../../app/theme/spacing.dart';
import '../../../auth/presentation/services/auth_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../core/utils/logger.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../onboarding/presentation/services/onboarding_service.dart';
import '../../../../core/services/ad_service.dart';
import 'package:flutter/services.dart';
import '../../../subscription/presentation/services/subscription_service.dart';
import '../../../../core/utils/snack.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:permission_handler/permission_handler.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen>
    with WidgetsBindingObserver {
  String _version = '';
  int _secretTapCount = 0;
  bool _secretUnlocked = false;
  DateTime? _lastSecretTap;
  bool _isVerified = false;
  bool _isVerificationPending = false;

  @override
  void initState() {
    super.initState();
    _loadVersion();
    _loadVerificationStatus();
    _loadNotifPrefs();
    WidgetsBinding.instance.addObserver(this);
  }

  Future<void> _loadVerificationStatus() async {
    try {
      final client = Supabase.instance.client;
      final userId = client.auth.currentUser?.id;
      if (userId == null) return;

      final row = await client
          .from('users_private')
          .select('is_identity_verified, last_verification_request_at')
          .eq('id', userId)
          .maybeSingle();

      if (!mounted) return;
      setState(() {
        _isVerified = row?['is_identity_verified'] as bool? ?? false;
        // Pending = requested in last 30 minutes and not yet verified
        final lastReq = row?['last_verification_request_at'] as String?;
        if (lastReq != null && !_isVerified) {
          final reqTime = DateTime.tryParse(lastReq);
          if (reqTime != null) {
            _isVerificationPending =
                DateTime.now().difference(reqTime).inMinutes < 30;
          }
        }
      });
    } catch (_) {}
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Hide secret panel when app goes to background.
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      if (_secretUnlocked) {
        setState(() {
          _secretUnlocked = false;
          _secretTapCount = 0;
        });
      }
    }
  }

  void _onSecretTap() {
    final now = DateTime.now();
    if (_lastSecretTap != null &&
        now.difference(_lastSecretTap!) > const Duration(seconds: 2)) {
      // Reset if too slow.
      _secretTapCount = 0;
    }
    _lastSecretTap = now;
    _secretTapCount++;
    if (_secretTapCount >= 5) {
      setState(() {
        _secretUnlocked = true;
        _secretTapCount = 0;
      });
      HapticFeedback.heavyImpact();
    } else {
      HapticFeedback.selectionClick();
    }
  }

  static const _languages = [
    ('English', 'en'),
    ('हिन्दी', 'hi'),
    ('தமிழ்', 'ta'),
    ('తెలుగు', 'te'),
    ('ಕನ್ನಡ', 'kn'),
    ('मराठी', 'mr'),
    ('বাংলা', 'bn'),
    ('Español', 'es'),
    ('Français', 'fr'),
    ('Deutsch', 'de'),
    ('العربية', 'ar'),
    ('中文', 'zh'),
  ];

  String _currentLanguageLabel(BuildContext context) {
    final code = context.read<OnboardingService>().language;
    return _languages
        .firstWhere(
          (l) => l.$2 == code,
          orElse: () => ('English', 'en'),
        )
        .$1;
  }

  void _showLanguageSheet(BuildContext context) {
    final onboarding = context.read<OnboardingService>();
    String selected = onboarding.language;

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setSheet) {
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    margin: const EdgeInsets.only(top: 12),
                    decoration: BoxDecoration(
                      color: AppColors.borderMedium,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
                  child: Text(
                    'Choose language',
                    style: GoogleFonts.josefinSans(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Flexible(
                  child: ListView(
                    shrinkWrap: true,
                    children: _languages.map((lang) {
                      final isSelected = selected == lang.$2;
                      return AnimatedContainer(
                        duration: const Duration(milliseconds: 180),
                        color: isSelected
                            ? AppColors.fernGreenLight
                            : Colors.white,
                        child: ListTile(
                          title: Text(
                            lang.$1,
                            style: GoogleFonts.josefinSans(
                              fontWeight: isSelected
                                  ? FontWeight.w600
                                  : FontWeight.w400,
                              color: isSelected
                                  ? AppColors.fernGreenDark
                                  : AppColors.charcoal,
                            ),
                          ),
                          trailing: isSelected
                              ? const Icon(
                                  Icons.check_circle_rounded,
                                  color: AppColors.fernGreen,
                                )
                              : null,
                          onTap: () {
                            setSheet(() => selected = lang.$2);
                          },
                        ),
                      );
                    }).toList(),
                  ),
                ),
                Padding(
                  padding: EdgeInsets.fromLTRB(
                    24,
                    16,
                    24,
                    24 + MediaQuery.of(ctx).padding.bottom,
                  ),
                  child: SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () {
                        onboarding.setLanguage(selected);
                        Navigator.pop(ctx);
                        // Notify user the change applies on next restart
                        // because flutter_localizations requires app rebuild
                        showInfoSnack(context,
                            'Language updated. Restart the app to apply.');
                        setState(() {});
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.charcoal,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        elevation: 0,
                      ),
                      child: Text(
                        'Apply',
                        style: GoogleFonts.josefinSans(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _showAdInfoModal(BuildContext context) {
    final adService = context.read<AdService>();
    final isAdFree = adService.isAdFreeActive;
    final minsLeft = adService.adFreeMinutesRemaining;

    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'dismiss',
      barrierColor: Colors.black54,
      transitionDuration: const Duration(milliseconds: 380),
      transitionBuilder: (ctx, anim, secondAnim, child) {
        final curve = CurvedAnimation(parent: anim, curve: Curves.easeOutBack);
        return ScaleTransition(
          scale: Tween<double>(begin: 0.85, end: 1.0).animate(curve),
          child: FadeTransition(
            opacity: Tween<double>(begin: 0, end: 1).animate(
              CurvedAnimation(parent: anim, curve: Curves.easeOut),
            ),
            child: child,
          ),
        );
      },
      pageBuilder: (ctx, _, __) {
        return Center(
          child: Material(
            color: Colors.transparent,
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 32),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(24),
              ),
              padding: const EdgeInsets.all(AppSpacing.xl),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 300),
                    child: Icon(
                      isAdFree ? Icons.block_rounded : Icons.ads_click_rounded,
                      key: ValueKey(isAdFree),
                      size: 48,
                      color: isAdFree
                          ? AppColors.fernGreen
                          : AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  Text(
                    isAdFree ? 'Ads are paused' : 'About ads on Echoproof',
                    style: GoogleFonts.josefinSans(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: AppColors.charcoal,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Text(
                    isAdFree
                        ? 'You earned $minsLeft more minutes of ad-free browsing by watching a video. Ads will resume after your session ends.'
                        : 'Echoproof is free to use. Ads help keep the platform running. You can remove ads by going Pro, or earn 1 hour ad-free by watching a short video from the feed.',
                    style: GoogleFonts.josefinSans(
                      fontSize: 13,
                      color: AppColors.textSecondary,
                      height: 1.6,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: AppSpacing.xl),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () {
                        Navigator.pop(ctx);

                        showInfoSnack(context, 'Coming soon! Stay tuned.');
                        // context.push('/subscribe');
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.charcoal,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        elevation: 0,
                      ),
                      child: Text(
                        'Go Pro — remove ads',
                        style: GoogleFonts.josefinSans(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: Text(
                      'Close',
                      style: GoogleFonts.josefinSans(
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _loadVersion() async {
    final info = await PackageInfo.fromPlatform();
    if (mounted) {
      setState(() => _version = '${info.version} (${info.buildNumber})');
    }
  }

  bool _pushEnabled = true;
  Map<String, bool> _notifPrefs = {
    'echo_verified': true,
    'new_follower_echo': true,
    'someone_supported': false,
  };

  Future<void> _loadNotifPrefs() async {
    final box = Hive.box('app_settings');
    setState(() {
      _pushEnabled = box.get('push_enabled', defaultValue: true) as bool;
      _notifPrefs = {
        'echo_verified':
            box.get('notif_echo_verified', defaultValue: true) as bool,
        'new_follower_echo':
            box.get('notif_new_follower_echo', defaultValue: true) as bool,
        'someone_supported':
            box.get('notif_someone_supported', defaultValue: false) as bool,
      };
    });
  }

  Future<void> _setPushEnabled(bool v) async {
    final box = Hive.box('app_settings');
    await box.put('push_enabled', v);
    setState(() => _pushEnabled = v);
    if (!v) {
      // Revoke notification permission is not possible programmatically on Android/iOS.
      // Show guidance instead.
      if (mounted) {
        showInfoSnack(context,
            'To fully disable notifications, go to System Settings > Apps > Echoproof > Notifications.');
      }
    }
  }

  Future<void> _setNotifPref(String key, bool v) async {
    final box = Hive.box('app_settings');
    await box.put('notif_$key', v);
    setState(() => _notifPrefs[key] = v);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5FAF7),
      appBar: AppBar(
        title: Text(
          'Settings',
          style: GoogleFonts.josefinSans(
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: AppColors.charcoal,
        actions: [
          GestureDetector(
            onTap: _onSecretTap,
            child: Padding(
              padding: const EdgeInsets.only(right: 16),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: _secretUnlocked
                      ? AppColors.fernGreenLight
                      : AppColors.borderSubtle.withValues(alpha: 0.4),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.question_mark_rounded,
                  size: 14,
                  color: _secretUnlocked
                      ? AppColors.fernGreen
                      : AppColors.textTertiary,
                ),
              ),
            ),
          ),
        ],
      ),
      body: ListView(
        children: [
          _Section(title: 'Language', tiles: [
            _Tile(
              icon: Icons.language_rounded,
              label: 'App language',
              subtitle: _currentLanguageLabel(context),
              onTap: () => _showLanguageSheet(context),
            ),
          ]),
          _Section(title: 'Account', tiles: [
            _Tile(
              icon: Icons.person_outline_rounded,
              label: 'Edit profile',
              onTap: () => context.push('/profile'),
            ),
            _Tile(
              icon: _isVerified
                  ? Icons.verified_rounded
                  : _isVerificationPending
                      ? Icons.pending_outlined
                      : Icons.verified_user_outlined,
              label: _isVerified
                  ? 'Identity verified ✓'
                  : _isVerificationPending
                      ? 'Verification in progress...'
                      : 'Verify identity',
              subtitle: _isVerified
                  ? 'Your identity has been confirmed'
                  : _isVerificationPending
                      ? 'Usually takes a few minutes'
                      : null,
              color: _isVerified ? AppColors.fernGreen : null,
              onTap: _isVerified || _isVerificationPending
                  ? () {} // Disabled — show nothing or a snack
                  : () => context.push('/verify-identity'),
            ),
            // _Tile(
            //   icon: Icons.receipt_long_outlined,
            //   label: 'Purchase history',
            //   onTap: () {
            //     final sub = context.read<SubscriptionService>();
            //     if (!sub.hasEverAttemptedPurchase && !sub.isPro) {
            //       showInfoSnack(context, 'No purchase history yet.');
            //       return;
            //     }
            //     context.push('/purchase-history');
            //   },
            // ),
          ]),
          _Section(title: 'Subscription', tiles: [
            _Tile(
              icon: Icons.star_outline_rounded,
              label: 'Echoproof Pro',
              trailing: const _ProBadge(),
              onTap: () => {
                showInfoSnack(
                  context,
                  'Echoproof Pro is coming soon! In the meantime,\n you can support us by sharing the app with friends.',
                )
              }

              // context.push('/subscribe'),
            ),
          ]),
          _Section(title: 'Notifications', tiles: [
            _SwitchTile(
              icon: Icons.notifications_outlined,
              label: 'Push notifications',
              value: _pushEnabled,
              onChanged: _setPushEnabled,
            ),
            // In-app notifications are always on — shown greyed out.
            _Tile(
              icon: Icons.notifications_active_outlined,
              label: 'In-app notifications',
              subtitle: 'Always enabled (required)',
              color: AppColors.textTertiary,
              onTap: () => showInfoSnack(
                  context, 'In-app notifications cannot be disabled.'),
            ),
            if (_pushEnabled) ...[
              _SwitchTile(
                icon: Icons.verified_outlined,
                label: 'Echo verified',
                value: _notifPrefs['echo_verified'] ?? true,
                onChanged: (v) => _setNotifPref('echo_verified', v),
              ),
              _SwitchTile(
                icon: Icons.people_outline,
                label: 'New echo from someone I follow',
                value: _notifPrefs['new_follower_echo'] ?? true,
                onChanged: (v) => _setNotifPref('new_follower_echo', v),
              ),
              _SwitchTile(
                icon: Icons.arrow_upward_rounded,
                label: 'Someone supported my echo',
                value: _notifPrefs['someone_supported'] ?? false,
                onChanged: (v) => _setNotifPref('someone_supported', v),
              ),
            ],
          ]),

          _Section(title: 'App Permissions', tiles: [
            _PermissionTile(
              icon: Icons.notifications_outlined,
              label: 'Notifications',
              permission: Permission.notification,
            ),
            _PermissionTile(
              icon: Icons.photo_library_outlined,
              label: 'Photo library',
              permission: Permission.photos,
            ),
            _PermissionTile(
              icon: Icons.camera_alt_outlined,
              label: 'Camera',
              permission: Permission.camera,
            ),
          ]),
          _Section(title: 'Privacy', tiles: [
            _Tile(
              icon: Icons.shield_outlined,
              label: 'End-to-end encryption',
              subtitle: 'All echoes encrypted in transit and at rest',
              onTap: () {},
            ),
            _Tile(
              icon: Icons.delete_outline_rounded,
              label: 'Delete account',
              color: AppColors.sunsetCoral,
              onTap: () => _showDeleteAccount(context),
            ),
          ]),
          _Section(title: 'Ads', tiles: [
            _AdStatusTile(onTap: () => _showAdInfoModal(context)),
          ]),
          _Section(title: 'About', tiles: [
            _Tile(
              icon: Icons.info_outline_rounded,
              label: 'About Echoproof',
              onTap: () => _launchUrl('https://echoproof.online/'),
            ),
            _Tile(
              icon: Icons.description_outlined,
              label: 'Terms of service',
              onTap: () => _launchUrl('https://echoproof.online/terms'),
            ),
            _Tile(
              icon: Icons.privacy_tip_outlined,
              label: 'Privacy policy',
              onTap: () => _launchUrl('https://echoproof.online/privacy'),
            ),
            _Tile(
              icon: Icons.support_agent_rounded,
              label: 'Contact support',
              onTap: () => _showContactSheet(context),
            ),
            _Tile(
              icon: Icons.code_rounded,
              label: _version.isEmpty ? 'Version...' : 'Version $_version',
              onTap: () {},
            ),
          ]),
          // Secret developer panel — only visible after 5 quick taps on ?
          AnimatedSize(
            duration: const Duration(milliseconds: 350),
            curve: Curves.easeOutCubic,
            child: _secretUnlocked
                ? _SecretDevPanel(
                    onClose: () => setState(() {
                      _secretUnlocked = false;
                      _secretTapCount = 0;
                    }),
                  )
                : const SizedBox.shrink(),
          ),

          const SizedBox(height: AppSpacing.lg),
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.xl,
              vertical: AppSpacing.sm,
            ),
            child: OutlinedButton.icon(
              onPressed: () async {
                await context.read<AuthService>().signOut();
                if (context.mounted) context.go('/login');
              },
              icon: const Icon(Icons.logout_rounded, size: 18),
              label: Text(
                'Sign out',
                style: GoogleFonts.josefinSans(fontWeight: FontWeight.w600),
              ),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.sunsetCoral,
                side: BorderSide(
                    color: AppColors.sunsetCoral.withValues(alpha: 0.4)),
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),
          ),
          const SizedBox(height: 80),
        ],
      ),
    );
  }

  Future<void> _launchUrl(String url) async {
    final uri = Uri.parse(url);
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      AppLogger.warn('settings: could not launch $url');
    }
  }

  void _showContactSheet(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.borderMedium,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.xl),
            Text('Contact support',
                style: GoogleFonts.josefinSans(
                    fontSize: 18, fontWeight: FontWeight.w700)),
            const SizedBox(height: AppSpacing.md),
            Text(
              'For support, bug reports, or general questions:',
              style: GoogleFonts.josefinSans(
                  fontSize: 14, color: AppColors.textSecondary),
            ),
            const SizedBox(height: AppSpacing.lg),
            GestureDetector(
              onTap: () => _launchUrl('mailto:support@echoproof.online'),
              child: Container(
                padding: const EdgeInsets.all(AppSpacing.md),
                decoration: BoxDecoration(
                  color: AppColors.fernGreenLight,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                      color: AppColors.fernGreen.withValues(alpha: 0.3)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.email_outlined,
                        size: 20, color: AppColors.fernGreen),
                    const SizedBox(width: AppSpacing.md),
                    Text('support@echoproof.online',
                        style: GoogleFonts.josefinSans(
                          fontSize: 14,
                          color: AppColors.fernGreenDark,
                          fontWeight: FontWeight.w600,
                        )),
                  ],
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'This is our only support channel at this time.',
              style: GoogleFonts.josefinSans(
                  fontSize: 12, color: AppColors.textTertiary),
            ),
            const SizedBox(height: AppSpacing.xxl),
          ],
        ),
      ),
    );
  }

  void _showDeleteAccount(BuildContext context) {
    // empty controller — user must type email themselves
    final emailCtrl = TextEditingController();
    final currentEmail = Supabase.instance.client.auth.currentUser?.email ?? '';

    showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Text('Delete account?',
              style: GoogleFonts.josefinSans(fontWeight: FontWeight.w700)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'This permanently deletes your account, echoes, and trust history. This cannot be undone.',
                style: GoogleFonts.josefinSans(fontSize: 14, height: 1.5),
              ),
              const SizedBox(height: 16),
              Text(
                'Type your email address to confirm:',
                style: GoogleFonts.josefinSans(
                    fontSize: 13, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: emailCtrl,
                keyboardType: TextInputType.emailAddress,
                autofocus: true,
                style: GoogleFonts.josefinSans(fontSize: 14),
                decoration: InputDecoration(
                  hintText: 'your email address',
                  hintStyle:
                      GoogleFonts.josefinSans(color: AppColors.textTertiary),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                ),
                onChanged: (_) => setDialogState(() {}),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text('Cancel',
                  style: GoogleFonts.josefinSans(color: AppColors.charcoal)),
            ),
            TextButton(
              onPressed: emailCtrl.text.trim() == currentEmail
                  ? () async {
                      Navigator.pop(ctx);
                      await _deleteAccount(context);
                    }
                  : null,
              child: Text(
                'Delete permanently',
                style: GoogleFonts.josefinSans(
                  color: emailCtrl.text.trim() == currentEmail
                      ? AppColors.sunsetCoral
                      : AppColors.textTertiary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _deleteAccount(BuildContext context) async {
    final auth = context.read<AuthService>();
    final client = Supabase.instance.client;
    final userId = client.auth.currentUser?.id;
    if (userId == null) return;

    AppLogger.info('settings: deleting account for $userId');

    try {
      // delete dependent rows in safe order before removing the user rows
      await client.from('signal_responses').delete().eq('user_id', userId);
      await client.from('echo_interactions').delete().eq('user_id', userId);
      await client.from('echo_replies').delete().eq('user_id', userId);
      final echoIds = await _getUserEchoIds(client, userId);

      if (echoIds.isNotEmpty) {
        await client
            .from('echo_proofs')
            .delete()
            .filter('echo_id', 'in', echoIds);
        await client
            .from('echo_signals')
            .delete()
            .filter('echo_id', 'in', echoIds);
      }
      await client.from('truth_bonds').delete().eq('user_id', userId);
      await client.from('notifications').delete().eq('user_id', userId);
      await client.from('echoes').delete().eq('user_id', userId);
      await client.from('users_public').delete().eq('id', userId);
      await client.from('users_private').delete().eq('id', userId);

      AppLogger.info('settings: user data deleted, signing out');
      await auth.signOut();

      if (context.mounted) {
        context.go('/login');
      }
    } catch (e) {
      AppLogger.error('settings: delete account failed: $e');
      if (context.mounted) {
        showErrorSnack(context, 'Failed to delete account. Please try again.');
      }
    }
  }

  Future<List<String>> _getUserEchoIds(
      SupabaseClient client, String userId) async {
    try {
      final rows =
          await client.from('echoes').select('id').eq('user_id', userId);
      return (rows as List).map((r) => r['id'] as String).toList();
    } catch (_) {
      return [];
    }
  }
}

class _PermissionTile extends StatefulWidget {
  const _PermissionTile({
    required this.icon,
    required this.label,
    required this.permission,
  });
  final IconData icon;
  final String label;
  final Permission permission;

  @override
  State<_PermissionTile> createState() => _PermissionTileState();
}

class _PermissionTileState extends State<_PermissionTile>
    with WidgetsBindingObserver {
  PermissionStatus _status = PermissionStatus.denied;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _check();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _check();
  }

  Future<void> _check() async {
    final s = await widget.permission.status;
    if (mounted) setState(() => _status = s);
  }

  bool get _granted =>
      _status == PermissionStatus.granted ||
      _status == PermissionStatus.limited;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: _status == PermissionStatus.permanentlyDenied
          ? openAppSettings
          : () async {
              await widget.permission.request();
              await _check();
            },
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.lg, vertical: AppSpacing.md),
        child: Row(
          children: [
            Icon(widget.icon,
                size: 20,
                color: _granted ? AppColors.fernGreen : AppColors.charcoal),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.label,
                    style: GoogleFonts.josefinSans(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: AppColors.charcoal),
                  ),
                  Text(
                    _granted
                        ? 'Allowed'
                        : _status == PermissionStatus.permanentlyDenied
                            ? 'Denied — tap to open settings'
                            : 'Not granted',
                    style: GoogleFonts.josefinSans(
                      fontSize: 12,
                      color: _granted
                          ? AppColors.fernGreen
                          : _status == PermissionStatus.permanentlyDenied
                              ? AppColors.sunsetCoral
                              : AppColors.textTertiary,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              _granted
                  ? Icons.check_circle_rounded
                  : Icons.chevron_right_rounded,
              size: 18,
              color: _granted ? AppColors.fernGreen : AppColors.textTertiary,
            ),
          ],
        ),
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.tiles});
  final String title;
  final List<Widget> tiles;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.xl,
            AppSpacing.lg,
            AppSpacing.xl,
            AppSpacing.xs,
          ),
          child: Text(
            title.toUpperCase(),
            style: GoogleFonts.josefinSans(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: AppColors.textTertiary,
              letterSpacing: 1.2,
            ),
          ),
        ),
        Container(
          margin: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.borderSubtle),
          ),
          child: Column(children: tiles),
        ),
      ],
    );
  }
}

class _SecretDevPanel extends StatefulWidget {
  const _SecretDevPanel({required this.onClose});
  final VoidCallback onClose;

  @override
  State<_SecretDevPanel> createState() => _SecretDevPanelState();
}

class _SecretDevPanelState extends State<_SecretDevPanel>
    with SingleTickerProviderStateMixin {
  late final AnimationController _entranceCtrl;
  late final Animation<double> _fade;
  late final Animation<Offset> _slide;

  @override
  void initState() {
    super.initState();
    _entranceCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _fade = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _entranceCtrl, curve: Curves.easeOut),
    );
    _slide = Tween<Offset>(
      begin: const Offset(0, -0.1),
      end: Offset.zero,
    ).animate(
        CurvedAnimation(parent: _entranceCtrl, curve: Curves.easeOutCubic));
    _entranceCtrl.forward();
  }

  @override
  void dispose() {
    _entranceCtrl.dispose();
    super.dispose();
  }

  Future<void> _showDevAd(BuildContext context) async {
    final adService = context.read<AdService>();
    if (!adService.rewardedReady) return;

    // Shows the rewarded ad but deliberately does NOT call onRewarded
    // with any user-facing reward. Developer earns impression revenue.
    await adService.showRewarded(
      onRewarded: () {
        // Intentionally empty — developer earns, user gets no reward.
        if (context.mounted) {
          showErrorSnack(
              context, 'Ad Completed Thank You For Supporting EchoProof.');
        }
      },
      onDismissed: () {},
    );
  }

  @override
  Widget build(BuildContext context) {
    final adService = context.watch<AdService>();
    final isAdReady = adService.rewardedReady;

    return FadeTransition(
      opacity: _fade,
      child: SlideTransition(
        position: _slide,
        child: Container(
          margin: const EdgeInsets.symmetric(
            horizontal: AppSpacing.lg,
            vertical: AppSpacing.sm,
          ),
          decoration: BoxDecoration(
            color: const Color(0xFF0D1117), // dark dev feel
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: AppColors.fernGreen.withValues(alpha: 0.3),
            ),
          ),
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Text('⚙️', style: TextStyle(fontSize: 16)),
                  const SizedBox(width: 8),
                  Text(
                    'Developer panel',
                    style: GoogleFonts.josefinSans(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: AppColors.fernGreen,
                    ),
                  ),
                  const Spacer(),
                  GestureDetector(
                    onTap: widget.onClose,
                    child: const Icon(
                      Icons.close_rounded,
                      size: 16,
                      color: AppColors.textTertiary,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                'Hidden section. Not visible to regular users.',
                style: GoogleFonts.josefinSans(
                  fontSize: 11,
                  color: AppColors.textTertiary,
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              Tooltip(
                message: isAdReady ? '' : 'No ad available right now',
                child: SizedBox(
                  width: double.infinity,
                  child: AnimatedOpacity(
                    opacity: isAdReady ? 1.0 : 0.4,
                    duration: const Duration(milliseconds: 200),
                    child: ElevatedButton.icon(
                      onPressed: isAdReady ? () => _showDevAd(context) : null,
                      icon: Icon(
                        isAdReady
                            ? Icons.play_arrow_rounded
                            : Icons.block_rounded,
                        size: 16,
                      ),
                      label: Text(
                        isAdReady
                            ? 'Show rewarded ad (dev revenue)'
                            : 'Ad not available',
                        style: GoogleFonts.josefinSans(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: isAdReady
                            ? AppColors.fernGreen
                            : AppColors.borderMedium,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        elevation: 0,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                isAdReady
                    ? '● Ad loaded and ready'
                    : '○ Waiting for ad to load...',
                style: GoogleFonts.josefinSans(
                  fontSize: 11,
                  color:
                      isAdReady ? AppColors.fernGreen : AppColors.textTertiary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({
    required this.icon,
    required this.label,
    required this.onTap,
    this.subtitle,
    this.trailing,
    this.color,
  });
  final IconData icon;
  final String label;
  final String? subtitle;
  final Widget? trailing;
  final Color? color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.md,
        ),
        child: Row(
          children: [
            Icon(icon, size: 20, color: color ?? AppColors.charcoal),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: GoogleFonts.josefinSans(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: color ?? AppColors.charcoal,
                    ),
                  ),
                  if (subtitle != null)
                    Text(
                      subtitle!,
                      style: GoogleFonts.josefinSans(
                        fontSize: 12,
                        color: AppColors.textTertiary,
                      ),
                    ),
                ],
              ),
            ),
            trailing ??
                const Icon(
                  Icons.chevron_right_rounded,
                  size: 16,
                  color: AppColors.textTertiary,
                ),
          ],
        ),
      ),
    );
  }
}

class _SwitchTile extends StatefulWidget {
  const _SwitchTile({
    required this.icon,
    required this.label,
    required this.value,
    required this.onChanged,
  });
  final IconData icon;
  final String label;
  final bool value;
  final void Function(bool) onChanged;

  @override
  State<_SwitchTile> createState() => _SwitchTileState();
}

class _SwitchTileState extends State<_SwitchTile> {
  late bool _value;

  @override
  void initState() {
    super.initState();
    _value = widget.value;
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.sm,
      ),
      child: Row(
        children: [
          Icon(widget.icon,
              size: 20,
              color: _value ? AppColors.fernGreen : AppColors.textTertiary),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Text(
              widget.label,
              style: GoogleFonts.josefinSans(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: _value ? AppColors.charcoal : AppColors.textSecondary,
              ),
            ),
          ),
          Switch.adaptive(
            value: _value,
            onChanged: (v) {
              setState(() => _value = v);
              widget.onChanged(v);
            },
            activeThumbColor: AppColors.fernGreen,
            activeTrackColor: AppColors.fernGreen.withValues(alpha: 0.4),
            inactiveThumbColor: AppColors.textTertiary,
            inactiveTrackColor: AppColors.borderMedium,
          ),
        ],
      ),
    );
  }
}

class _ProBadge extends StatelessWidget {
  const _ProBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF2D2D2D), Color(0xFF4CAF6E)],
        ),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        'PRO',
        style: GoogleFonts.josefinSans(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: Colors.white,
          letterSpacing: 0.8,
        ),
      ),
    );
  }
}

class _AdStatusTile extends StatelessWidget {
  const _AdStatusTile({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final adService = context.watch<AdService>();
    final isAdFree = adService.isAdFreeActive;
    final minsLeft = adService.adFreeMinutesRemaining;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.md,
        ),
        child: Row(
          children: [
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 300),
              child: Icon(
                isAdFree ? Icons.block_rounded : Icons.ads_click_rounded,
                key: ValueKey(isAdFree),
                size: 20,
                color: isAdFree ? AppColors.fernGreen : AppColors.charcoal,
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 200),
                    child: Text(
                      isAdFree ? 'Ads paused' : 'Ad information',
                      key: ValueKey(isAdFree),
                      style: GoogleFonts.josefinSans(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: isAdFree
                            ? AppColors.fernGreenDark
                            : AppColors.charcoal,
                      ),
                    ),
                  ),
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 200),
                    child: Text(
                      isAdFree
                          ? '$minsLeft minutes remaining'
                          : 'Tap to learn about ads and go Pro',
                      key: ValueKey('$isAdFree-$minsLeft'),
                      style: GoogleFonts.josefinSans(
                        fontSize: 12,
                        color: AppColors.textTertiary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const Icon(
              Icons.chevron_right_rounded,
              size: 16,
              color: AppColors.textTertiary,
            ),
          ],
        ),
      ),
    );
  }
}

class _ChangePasswordSheet extends StatefulWidget {
  const _ChangePasswordSheet();

  @override
  State<_ChangePasswordSheet> createState() => _ChangePasswordSheetState();
}

class _ChangePasswordSheetState extends State<_ChangePasswordSheet> {
  final _controller = TextEditingController();
  bool _loading = false;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.viewInsetsOf(context).bottom,
        left: AppSpacing.xl,
        right: AppSpacing.xl,
        top: AppSpacing.xl,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'New password',
            style: GoogleFonts.josefinSans(
              fontSize: 18,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          TextField(
            controller: _controller,
            obscureText: true,
            decoration: InputDecoration(
              hintText: 'Enter new password (min 8 chars)',
              hintStyle: GoogleFonts.josefinSans(color: AppColors.textTertiary),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _loading
                  ? null
                  : () async {
                      if (_controller.text.length < 8) return;
                      setState(() => _loading = true);
                      // supabase update password
                      await Supabase.instance.client.auth.updateUser(
                        UserAttributes(password: _controller.text),
                      );
                      if (mounted) Navigator.pop(context);
                    },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.charcoal,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              child: Text(
                'Update password',
                style: GoogleFonts.josefinSans(fontWeight: FontWeight.w600),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.xl),
        ],
      ),
    );
  }
}
