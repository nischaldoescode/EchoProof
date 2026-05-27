// settings screen
// account, notifications, subscription, privacy, about

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:package_info_plus/package_info_plus.dart';
import '../../../../app/theme/colors.dart';
import '../../../../app/theme/spacing.dart';
import '../../../auth/presentation/services/auth_service.dart';
import '../../../auth/presentation/services/verification_error_parser.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../core/utils/logger.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../onboarding/presentation/services/onboarding_service.dart';
import '../../../../core/services/ad_service.dart';
import '../../../../core/services/account_device_service.dart';
import '../../../../core/services/push_notification_service.dart';
import '../../../subscription/presentation/services/subscription_service.dart';
import '../../../../core/localization/app_copy.dart';
import 'package:flutter/services.dart';
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
  static const _verificationBlockUserKey = 'verification_block_user_id';
  static const _verificationBlockMessageKey = 'verification_block_message';
  static const _verificationBlockExpiresKey = 'verification_block_expires_at';

  String _version = '';
  int _secretTapCount = 0;
  bool _secretUnlocked = false;
  DateTime? _lastSecretTap;
  bool _isVerified = false;
  bool _isVerificationPending = false;
  bool _isCheckingVerification = false;
  String? _verificationBlockedMessage;

  @override
  void initState() {
    super.initState();
    _loadVersion();
    _loadVerificationStatus();
    _loadCachedVerificationBlock();
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

  Future<void> _openIdentityVerification() async {
    final blockedMessage = _verificationBlockedMessage;
    if (blockedMessage != null && blockedMessage.isNotEmpty) {
      showInfoSnack(context, blockedMessage);
      return;
    }

    if (_isCheckingVerification) return;
    setState(() => _isCheckingVerification = true);
    final preflightMessage = await _preflightIdentityVerification();
    if (!mounted) return;
    setState(() => _isCheckingVerification = false);

    if (preflightMessage != null && preflightMessage.trim().isNotEmpty) {
      await _setVerificationBlockedMessage(preflightMessage);
      if (!mounted) return;
      showInfoSnack(context, preflightMessage.trim());
      return;
    }

    await _clearCachedVerificationBlock();
    if (!mounted) return;

    final result = await context.push<String>('/verify-identity');
    if (!mounted) return;

    await _loadVerificationStatus();
    if (!mounted) return;

    if (result != null && result.trim().isNotEmpty) {
      await _setVerificationBlockedMessage(result);
      if (!mounted) return;
      showInfoSnack(context, result.trim());
    }
  }

  Future<String?> _preflightIdentityVerification() async {
    try {
      final client = Supabase.instance.client;
      final userId = client.auth.currentUser?.id;
      if (userId == null) return 'Sign in again to continue.';

      final response = await client.functions.invoke(
        'create-didit-session',
        body: {
          'user_id': userId,
          'redirect_uri': 'echoproof://verify-complete',
          'dry_run': true,
        },
      );

      final message =
          VerificationErrorParser.messageFromResponseData(response.data);
      if (message != null) return message;

      return null;
    } catch (e) {
      AppLogger.warn('settings: verification preflight failed $e');
      return VerificationErrorParser.messageFrom(e);
    }
  }

  Future<void> _loadCachedVerificationBlock() async {
    try {
      final client = Supabase.instance.client;
      final userId = client.auth.currentUser?.id;
      if (userId == null) return;

      final box = Hive.isBoxOpen('app_settings')
          ? Hive.box('app_settings')
          : await Hive.openBox('app_settings');
      final cachedUserId = box.get(_verificationBlockUserKey) as String?;
      final message = box.get(_verificationBlockMessageKey) as String?;
      final expiresRaw = box.get(_verificationBlockExpiresKey) as String?;
      final expiresAt =
          expiresRaw == null ? null : DateTime.tryParse(expiresRaw);

      if (cachedUserId != userId ||
          message == null ||
          message.trim().isEmpty ||
          expiresAt == null ||
          !expiresAt.isAfter(DateTime.now())) {
        await _clearCachedVerificationBlock();
        return;
      }

      if (!mounted) return;
      setState(() => _verificationBlockedMessage = message.trim());
    } catch (_) {}
  }

  Future<void> _setVerificationBlockedMessage(String message) async {
    final trimmed = message.trim();
    if (trimmed.isEmpty) return;

    if (mounted) {
      setState(() => _verificationBlockedMessage = trimmed);
    }

    if (!_shouldCacheVerificationBlock(trimmed)) return;

    try {
      final userId = Supabase.instance.client.auth.currentUser?.id;
      if (userId == null) return;
      final box = Hive.isBoxOpen('app_settings')
          ? Hive.box('app_settings')
          : await Hive.openBox('app_settings');
      await box.put(_verificationBlockUserKey, userId);
      await box.put(_verificationBlockMessageKey, trimmed);
      await box.put(
        _verificationBlockExpiresKey,
        DateTime.now().add(const Duration(days: 31)).toIso8601String(),
      );
    } catch (_) {}
  }

  Future<void> _clearCachedVerificationBlock() async {
    try {
      final box = Hive.isBoxOpen('app_settings')
          ? Hive.box('app_settings')
          : await Hive.openBox('app_settings');
      await box.delete(_verificationBlockUserKey);
      await box.delete(_verificationBlockMessageKey);
      await box.delete(_verificationBlockExpiresKey);
    } catch (_) {}
  }

  bool _shouldCacheVerificationBlock(String message) {
    final normalized = message.toLowerCase();
    return normalized.contains('maximum of 2 verification attempts') ||
        normalized.contains('too many verification attempts') ||
        normalized.contains('cooldown');
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
                    context.l('Choose language'),
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
                        showInfoSnack(context, context.l('Language updated.'));
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
                        context.l('Apply'),
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
    final feedStatus = adService.feedRoutineStatusText;

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
                        : 'Echoproof is free to use. Feed ads are limited to 2 per hour and spaced at least 30 minutes apart while you are actively on the feed. $feedStatus You can remove ads by going Pro, or earn 1 hour ad-free by watching a short video.',
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

                        showInfoSnack(
                            context, context.l('Coming soon! Stay tuned.'));
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
  static const Map<String, bool> _defaultNotifPrefs = {
    'echo_verified': true,
    'new_follower_echo': true,
    'echo_context': true,
    'context_like': true,
    'reply': true,
    'reply_like': true,
    'follow_request': true,
    'follow_request_accepted': true,
    'new_follower': true,
  };
  Map<String, bool> _notifPrefs = Map.of(_defaultNotifPrefs);

  Future<void> _loadNotifPrefs() async {
    final box = Hive.box('app_settings');
    final localPrefs = {
      for (final entry in _defaultNotifPrefs.entries)
        entry.key:
            box.get('notif_${entry.key}', defaultValue: entry.value) as bool,
    };

    // Migration bridge for early builds that had only this local key.
    if (box.containsKey('notif_someone_supported') &&
        !box.containsKey('notif_echo_context')) {
      localPrefs['echo_context'] =
          box.get('notif_someone_supported', defaultValue: true) as bool;
    }

    if (mounted) {
      setState(() {
        _pushEnabled = box.get('push_enabled', defaultValue: true) as bool;
        _notifPrefs = localPrefs;
      });
    }

    try {
      final client = Supabase.instance.client;
      final userId = client.auth.currentUser?.id;
      if (userId == null) return;

      final row = await client
          .from('notification_preferences')
          .select()
          .eq('user_id', userId)
          .maybeSingle();

      if (row == null) {
        await _saveServerNotifPrefs({
          'push_enabled': _pushEnabled,
          ...localPrefs,
        });
        return;
      }

      final serverPush = row['push_enabled'] as bool? ?? _pushEnabled;
      final serverPrefs = {
        for (final entry in _defaultNotifPrefs.entries)
          entry.key: row[entry.key] as bool? ?? localPrefs[entry.key]!,
      };

      await box.put('push_enabled', serverPush);
      for (final entry in serverPrefs.entries) {
        await box.put('notif_${entry.key}', entry.value);
      }

      if (!mounted) return;
      setState(() {
        _pushEnabled = serverPush;
        _notifPrefs = serverPrefs;
      });
    } catch (e) {
      AppLogger.warn('settings: notification preferences load failed $e');
    }
  }

  Future<void> _setPushEnabled(bool v) async {
    final box = Hive.box('app_settings');
    await box.put('push_enabled', v);
    setState(() => _pushEnabled = v);
    unawaited(_saveServerNotifPrefs({'push_enabled': v}));
    if (!v) {
      unawaited(PushNotificationService.instance.removeToken());
      // Revoke notification permission is not possible programmatically on Android/iOS.
      // Show guidance instead.
      if (mounted) {
        showInfoSnack(context,
            'To fully disable notifications, go to System Settings > Apps > Echoproof > Notifications.');
      }
    } else {
      unawaited(PushNotificationService.instance.initialize());
    }
  }

  Future<void> _setNotifPref(String key, bool v) async {
    final box = Hive.box('app_settings');
    await box.put('notif_$key', v);
    setState(() => _notifPrefs[key] = v);
    unawaited(_saveServerNotifPrefs({key: v}));
  }

  Future<void> _saveServerNotifPrefs(Map<String, dynamic> values) async {
    try {
      final client = Supabase.instance.client;
      final userId = client.auth.currentUser?.id;
      if (userId == null) return;
      await client.from('notification_preferences').upsert(
        {
          'user_id': userId,
          ...values,
          'updated_at': DateTime.now().toIso8601String(),
        },
        onConflict: 'user_id',
      );
    } catch (e) {
      AppLogger.warn('settings: notification preferences save failed $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final subscription = context.watch<SubscriptionService>();

    return Scaffold(
      backgroundColor: const Color(0xFFF5FAF7),
      appBar: AppBar(
        title: Text(
          context.l('Settings'),
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
          _Section(title: context.l('Language'), tiles: [
            _Tile(
              icon: Icons.language_rounded,
              label: context.l('App language'),
              subtitle: _currentLanguageLabel(context),
              onTap: () => _showLanguageSheet(context),
            ),
          ]),
          _Section(title: context.l('Account'), tiles: [
            _Tile(
              icon: Icons.person_outline_rounded,
              label: context.l('Edit profile'),
              onTap: () => context.push('/profile'),
            ),
            _Tile(
              icon: _isVerified
                  ? Icons.verified_rounded
                  : _isCheckingVerification
                      ? Icons.hourglass_top_rounded
                      : _isVerificationPending
                          ? Icons.pending_outlined
                          : Icons.verified_user_outlined,
              label: _isVerified
                  ? context.l('Identity verified')
                  : _isCheckingVerification
                      ? context.l('Checking verification...')
                      : _isVerificationPending
                          ? context.l('Verification in progress...')
                          : context.l('Verify identity'),
              subtitle: _isVerified
                  ? context.l('Your identity has been confirmed')
                  : _isCheckingVerification
                      ? context.l('Please wait')
                      : _isVerificationPending
                          ? context.l('Usually takes a few minutes')
                          : _verificationBlockedMessage,
              color: _isVerified ? AppColors.fernGreen : null,
              showChevron: !_isVerified &&
                  !_isCheckingVerification &&
                  !_isVerificationPending &&
                  _verificationBlockedMessage == null,
              onTap: _isVerified
                  ? () => showInfoSnack(
                        context,
                        context.l('Your identity has been confirmed'),
                      )
                  : _isVerificationPending
                      ? () => showInfoSnack(
                            context,
                            context.l('Verification in progress...'),
                          )
                      : _isCheckingVerification
                          ? () {}
                          : _openIdentityVerification,
            ),
            Consumer<AccountDeviceService>(
              builder: (context, devices, _) {
                final current = devices.currentDevice;
                final conflict = devices.pendingConflict;
                final activeCount =
                    devices.devices.where((device) => device.active).length;
                return _Tile(
                  icon: Icons.phone_android_rounded,
                  label: conflict == null
                      ? context.l('Active device')
                      : context.l('Device action needed'),
                  subtitle: conflict != null
                      ? '${conflict.currentDevice.deviceName} · ${context.l('active elsewhere')}'
                      : current == null
                          ? context.l('Registering this device...')
                          : '${current.deviceName} · ${context.l('This device')}',
                  trailing: _DeviceCountBadge(
                    count: activeCount,
                    alert: conflict != null,
                  ),
                  onTap: () => _showAccountDevicesSheet(context),
                );
              },
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
          _Section(title: context.l('Subscription'), tiles: [
            _Tile(
                icon: Icons.star_outline_rounded,
                label: context.l('Echoproof Pro'),
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
          _Section(title: context.l('Notifications'), tiles: [
            _SwitchTile(
              icon: Icons.notifications_outlined,
              label: context.l('Push notifications'),
              value: _pushEnabled,
              onChanged: _setPushEnabled,
            ),
            // In-app notifications are always on — shown greyed out.
            _Tile(
              icon: Icons.notifications_active_outlined,
              label: context.l('In-app notifications'),
              subtitle: context.l('Always enabled (required)'),
              color: AppColors.textTertiary,
              onTap: () => showInfoSnack(context,
                  context.l('In-app notifications cannot be disabled.')),
            ),
            if (_pushEnabled) ...[
              _SwitchTile(
                icon: Icons.verified_outlined,
                label: context.l('Echo verified'),
                value: _notifPrefs['echo_verified'] ?? true,
                onChanged: (v) => _setNotifPref('echo_verified', v),
              ),
              _SwitchTile(
                icon: Icons.people_outline,
                label: context.l('New echo from someone I follow'),
                value: _notifPrefs['new_follower_echo'] ?? true,
                onChanged: (v) => _setNotifPref('new_follower_echo', v),
              ),
              _SwitchTile(
                icon: Icons.arrow_upward_rounded,
                label: context.l('Support or challenge on my echo'),
                value: _notifPrefs['echo_context'] ?? true,
                onChanged: (v) => _setNotifPref('echo_context', v),
              ),
              _SwitchTile(
                icon: Icons.favorite_border_rounded,
                label: context.l('Likes on my context'),
                value: _notifPrefs['context_like'] ?? true,
                onChanged: (v) => _setNotifPref('context_like', v),
              ),
              _SwitchTile(
                icon: Icons.reply_outlined,
                label: context.l('Replies to my echoes or replies'),
                value: _notifPrefs['reply'] ?? true,
                onChanged: (v) => _setNotifPref('reply', v),
              ),
              _SwitchTile(
                icon: Icons.favorite_outline_rounded,
                label: context.l('Likes on my replies'),
                value: _notifPrefs['reply_like'] ?? true,
                onChanged: (v) => _setNotifPref('reply_like', v),
              ),
              _SwitchTile(
                icon: Icons.person_add_alt_1_outlined,
                label: context.l('Follow requests'),
                value: _notifPrefs['follow_request'] ?? true,
                onChanged: (v) => _setNotifPref('follow_request', v),
              ),
              _SwitchTile(
                icon: Icons.how_to_reg_outlined,
                label: context.l('Accepted follow requests'),
                value: _notifPrefs['follow_request_accepted'] ?? true,
                onChanged: (v) => _setNotifPref('follow_request_accepted', v),
              ),
              _SwitchTile(
                icon: Icons.group_add_outlined,
                label: context.l('New followers'),
                value: _notifPrefs['new_follower'] ?? true,
                onChanged: (v) => _setNotifPref('new_follower', v),
              ),
            ],
          ]),

          _Section(title: context.l('App Permissions'), tiles: [
            _PermissionTile(
              icon: Icons.notifications_outlined,
              label: context.l('Notifications'),
              permission: Permission.notification,
            ),
            _PermissionTile(
              icon: Icons.photo_library_outlined,
              label: context.l('Photo library'),
              permission: Permission.photos,
            ),
            _PermissionTile(
              icon: Icons.camera_alt_outlined,
              label: context.l('Camera'),
              permission: Permission.camera,
            ),
          ]),
          _Section(title: context.l('Privacy'), tiles: [
            _Tile(
              icon: Icons.shield_outlined,
              label: context.l('End-to-end encryption'),
              subtitle:
                  context.l('All echoes encrypted in transit and at rest'),
              showChevron: false,
              onTap: () {},
            ),
            _Tile(
              icon: Icons.delete_outline_rounded,
              label: context.l('Delete account'),
              color: AppColors.sunsetCoral,
              onTap: () => _showDeleteAccount(context),
            ),
          ]),
          if (!subscription.isPro)
            _Section(title: context.l('Ads'), tiles: [
              _AdStatusTile(onTap: () => _showAdInfoModal(context)),
            ]),
          _Section(title: context.l('About'), tiles: [
            _Tile(
              icon: Icons.info_outline_rounded,
              label: context.l('About Echoproof'),
              onTap: () => _showLinkChoiceSheet(
                url: 'https://echoproof.online/',
                title: context.l('About Echoproof'),
              ),
            ),
            _Tile(
              icon: Icons.description_outlined,
              label: context.l('Terms of service'),
              onTap: () => _showLinkChoiceSheet(
                url: 'https://echoproof.online/terms',
                title: context.l('Terms of service'),
              ),
            ),
            _Tile(
              icon: Icons.privacy_tip_outlined,
              label: context.l('Privacy policy'),
              onTap: () => _showLinkChoiceSheet(
                url: 'https://echoproof.online/privacy',
                title: context.l('Privacy policy'),
              ),
            ),
            _Tile(
              icon: Icons.support_agent_rounded,
              label: context.l('Contact support'),
              onTap: () => _showContactSheet(context),
            ),
            _Tile(
              icon: Icons.code_rounded,
              label: _version.isEmpty
                  ? context.l('Version...')
                  : '${context.l('Version')} $_version',
              showChevron: false,
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
                final auth = context.read<AuthService>();
                final signedOut = await auth.signOut();
                if (!context.mounted) return;
                if (signedOut) {
                  context.go('/login');
                } else {
                  showErrorSnack(
                    context,
                    auth.error ?? 'Could not sign out. Please try again.',
                  );
                  auth.clearError();
                }
              },
              icon: const Icon(Icons.logout_rounded, size: 18),
              label: Text(
                context.l('Sign out'),
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

  Future<void> _launchUrl(
    String url, {
    LaunchMode mode = LaunchMode.externalApplication,
  }) async {
    final uri = Uri.parse(url);
    if (!await launchUrl(uri, mode: mode)) {
      AppLogger.warn('settings: could not launch $url');
    }
  }

  void _showLinkChoiceSheet({
    required String url,
    required String title,
  }) {
    final uri = Uri.parse(url);

    showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return Padding(
          padding: EdgeInsets.fromLTRB(
            AppSpacing.xl,
            AppSpacing.lg,
            AppSpacing.xl,
            AppSpacing.xl + MediaQuery.paddingOf(ctx).bottom,
          ),
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
              TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: 1),
                duration: const Duration(milliseconds: 260),
                curve: Curves.easeOutCubic,
                builder: (_, value, child) => Opacity(
                  opacity: value,
                  child: Transform.translate(
                    offset: Offset(0, (1 - value) * 12),
                    child: child,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      context.l('Open {title}?', {'title': title}),
                      style: GoogleFonts.josefinSans(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: AppColors.charcoal,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      uri.host,
                      style: GoogleFonts.josefinSans(
                        fontSize: 13,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              _OpenLinkAction(
                icon: Icons.open_in_browser_rounded,
                title: context.l('Open in app'),
                subtitle: context.l('Use a secure in-app browser'),
                onTap: () {
                  Navigator.pop(ctx);
                  _launchUrl(url, mode: LaunchMode.inAppBrowserView);
                },
              ),
              _OpenLinkAction(
                icon: Icons.north_east_rounded,
                title: context.l('Open in browser'),
                subtitle: context.l('Switch to your default browser'),
                onTap: () {
                  Navigator.pop(ctx);
                  _launchUrl(url);
                },
              ),
            ],
          ),
        );
      },
    );
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
            Text(context.l('Contact support'),
                style: GoogleFonts.josefinSans(
                    fontSize: 18, fontWeight: FontWeight.w700)),
            const SizedBox(height: AppSpacing.md),
            Text(
              context.l('For support, bug reports, or general questions:'),
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
              context.l('This is our only support channel at this time.'),
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
          title: Text(context.l('Delete account?'),
              style: GoogleFonts.josefinSans(fontWeight: FontWeight.w700)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                context.l(
                  'This permanently deletes your account, echoes, and trust history. This cannot be undone.',
                ),
                style: GoogleFonts.josefinSans(fontSize: 14, height: 1.5),
              ),
              const SizedBox(height: 16),
              Text(
                context.l('Type your email address to confirm:'),
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
                  hintText: context.l('your email address'),
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
              child: Text(context.l('Cancel'),
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
                context.l('Delete permanently'),
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

  Future<void> _showAccountDevicesSheet(BuildContext context) async {
    final service = context.read<AccountDeviceService>();
    await service.loadDevices().catchError((_) {});
    if (!context.mounted) return;

    showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: AppColors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (sheetContext) => Consumer<AccountDeviceService>(
        builder: (context, devices, _) {
          final currentId = devices.currentDevice?.deviceId;
          final conflict = devices.pendingConflict;
          final bottom = MediaQuery.paddingOf(sheetContext).bottom;
          final activeDevices =
              devices.devices.where((device) => device.active).toList();
          return SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(
              AppSpacing.lg,
              AppSpacing.sm,
              AppSpacing.lg,
              AppSpacing.xl + bottom,
            ),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 42,
                        height: 42,
                        decoration: BoxDecoration(
                          color: AppColors.fernGreenLight,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: const Icon(
                          Icons.devices_rounded,
                          color: AppColors.fernGreenDark,
                        ),
                      ),
                      const SizedBox(width: AppSpacing.md),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              context.l('Account devices'),
                              style: GoogleFonts.josefinSans(
                                fontSize: 20,
                                fontWeight: FontWeight.w700,
                                color: AppColors.charcoal,
                              ),
                            ),
                            Text(
                              '${activeDevices.length} active',
                              style: GoogleFonts.josefinSans(
                                fontSize: 12,
                                color: AppColors.textSecondary,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    context.l(
                      'Only one device can stay active at a time. Signed-out devices are hidden from this list.',
                    ),
                    style: GoogleFonts.josefinSans(
                      fontSize: 13,
                      color: AppColors.textSecondary,
                      height: 1.35,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  if (conflict != null) ...[
                    _DeviceConflictBanner(
                      device: conflict.currentDevice,
                      registering: devices.registering,
                      onContinue: () =>
                          _continueAccountOnThisDevice(sheetContext),
                      onSignOut: () => _signOutFromDeviceConflict(sheetContext),
                    ),
                    const SizedBox(height: AppSpacing.lg),
                  ],
                  if (activeDevices.isEmpty)
                    Padding(
                      padding:
                          const EdgeInsets.symmetric(vertical: AppSpacing.xl),
                      child: Center(
                        child: Text(
                          context.l('No active devices yet.'),
                          style: GoogleFonts.josefinSans(
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ),
                    )
                  else
                    ...activeDevices.map(
                      (device) => _AccountDeviceCard(
                        device: device,
                        isThisDevice: device.deviceId == currentId,
                        lastSeenLabel: _formatDeviceSeen(device.lastSeenAt),
                        platformLabel: _devicePlatformLabel(device.platform),
                        platformIcon: _devicePlatformIcon(device.platform),
                        onTap: () => _showAccountDeviceInfoDialog(
                          context,
                          device,
                          isThisDevice: device.deviceId == currentId,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Future<void> _continueAccountOnThisDevice(BuildContext context) async {
    final devices = context.read<AccountDeviceService>();
    try {
      await devices.continueOnThisDevice();
      if (!context.mounted) return;
      showSuccessSnack(context, context.l('This device is now active.'));
    } catch (e) {
      if (!context.mounted) return;
      showErrorSnack(context, _friendlyError(e));
    }
  }

  Future<void> _signOutFromDeviceConflict(BuildContext context) async {
    final auth = context.read<AuthService>();
    final devices = context.read<AccountDeviceService>();
    devices.clearPendingConflict();
    await auth.signOut(enforceCooldown: false);
    if (!context.mounted) return;
    context.go('/login');
  }

  Future<void> _showAccountDeviceInfoDialog(
    BuildContext context,
    AccountDeviceRecord device, {
    required bool isThisDevice,
  }) {
    return showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: Text(
          isThisDevice ? context.l('This device') : device.deviceName,
          style: GoogleFonts.josefinSans(fontWeight: FontWeight.w700),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _DeviceInfoRow(
              label: context.l('Name'),
              value: device.deviceName,
            ),
            _DeviceInfoRow(
              label: context.l('Platform'),
              value: _devicePlatformLabel(device.platform),
            ),
            _DeviceInfoRow(
              label: context.l('Status'),
              value: device.active
                  ? isThisDevice
                      ? context.l('Active on this device')
                      : context.l('Active elsewhere')
                  : context.l('Logged out'),
            ),
            _DeviceInfoRow(
              label: context.l('Last seen'),
              value: _formatDeviceSeen(device.lastSeenAt),
            ),
            _DeviceInfoRow(
              label: context.l('Device id'),
              value: _shortDeviceId(device.deviceId),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(context.l('Close')),
          ),
        ],
      ),
    );
  }

  IconData _devicePlatformIcon(String platform) {
    return switch (platform) {
      'ios' => Icons.phone_iphone_rounded,
      'android' => Icons.phone_android_rounded,
      _ => Icons.devices_other_rounded,
    };
  }

  String _devicePlatformLabel(String platform) {
    return switch (platform) {
      'ios' => 'iPhone or iPad',
      'android' => 'Android',
      _ => platform.isEmpty ? 'Unknown platform' : platform,
    };
  }

  String _formatDeviceSeen(DateTime? value) {
    if (value == null) return 'Never';
    final diff = DateTime.now().difference(value.toLocal());
    if (diff.inSeconds < 30) return 'Just now';
    if (diff.inMinutes < 1) return '${diff.inSeconds}s ago';
    if (diff.inHours < 1) return '${diff.inMinutes}m ago';
    if (diff.inDays < 1) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return '${value.toLocal().year}-${value.toLocal().month.toString().padLeft(2, '0')}-${value.toLocal().day.toString().padLeft(2, '0')}';
  }

  String _shortDeviceId(String deviceId) {
    if (deviceId.length <= 12) return deviceId;
    return '${deviceId.substring(0, 6)}...${deviceId.substring(deviceId.length - 4)}';
  }

  String _friendlyError(Object error) {
    final text = error.toString().replaceFirst('Exception: ', '').trim();
    if (text.isEmpty) return context.l('Could not complete this action.');
    return text;
  }

  Future<void> _deleteAccount(BuildContext context) async {
    final auth = context.read<AuthService>();
    final client = Supabase.instance.client;
    final userId = client.auth.currentUser?.id;
    if (userId == null) return;

    AppLogger.info('settings: deleting account for $userId');

    try {
      await client.rpc('delete_own_account_data');

      AppLogger.info('settings: user data deleted, signing out');
      await auth.signOut(enforceCooldown: false);

      if (context.mounted) {
        context.go('/login');
      }
    } catch (e) {
      AppLogger.error('settings: delete account failed: $e');
      if (context.mounted) {
        showErrorSnack(
          context,
          context.l('Failed to delete account. Please try again.'),
        );
      }
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
                        ? context.l('Allowed')
                        : _status == PermissionStatus.permanentlyDenied
                            ? context.l('Denied — tap to open settings')
                            : context.l('Not granted'),
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

class _OpenLinkAction extends StatelessWidget {
  const _OpenLinkAction({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Ink(
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            color: AppColors.surfaceSecondary,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.borderSubtle),
          ),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: AppColors.fernGreenLight,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, size: 19, color: AppColors.fernGreenDark),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: GoogleFonts.josefinSans(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: AppColors.charcoal,
                      ),
                    ),
                    Text(
                      subtitle,
                      style: GoogleFonts.josefinSans(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.chevron_right_rounded,
                size: 17,
                color: AppColors.textTertiary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DeviceCountBadge extends StatelessWidget {
  const _DeviceCountBadge({required this.count, this.alert = false});

  final int count;
  final bool alert;

  @override
  Widget build(BuildContext context) {
    final value = count <= 0 ? 1 : count;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: alert ? AppColors.sunsetCoralLight : AppColors.fernGreenLight,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: (alert ? AppColors.sunsetCoral : AppColors.fernGreen)
              .withValues(alpha: 0.45),
        ),
      ),
      child: Text(
        alert ? '!' : '($value)',
        style: GoogleFonts.josefinSans(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: alert ? AppColors.sunsetCoralDark : AppColors.fernGreenDark,
        ),
      ),
    );
  }
}

class _DeviceConflictBanner extends StatelessWidget {
  const _DeviceConflictBanner({
    required this.device,
    required this.registering,
    required this.onContinue,
    required this.onSignOut,
  });

  final AccountDeviceRecord device;
  final bool registering;
  final VoidCallback onContinue;
  final VoidCallback onSignOut;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.sunsetCoralLight,
        borderRadius: BorderRadius.circular(16),
        border:
            Border.all(color: AppColors.sunsetCoral.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.phonelink_lock_rounded,
                color: AppColors.sunsetCoralDark,
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  context.l('Account active on another device'),
                  style: GoogleFonts.josefinSans(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: AppColors.sunsetCoralDark,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            '${device.deviceName} · ${device.platform}. Continue here only if this is you. The other device will be logged out.',
            style: GoogleFonts.josefinSans(
              fontSize: 13,
              height: 1.35,
              color: AppColors.sunsetCoralDark,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: registering ? null : onSignOut,
                  child: Text(context.l('Not me')),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: FilledButton(
                  onPressed: registering ? null : onContinue,
                  child: registering
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(context.l('Continue here')),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _AccountDeviceCard extends StatelessWidget {
  const _AccountDeviceCard({
    required this.device,
    required this.isThisDevice,
    required this.lastSeenLabel,
    required this.platformLabel,
    required this.platformIcon,
    required this.onTap,
  });

  final AccountDeviceRecord device;
  final bool isThisDevice;
  final String lastSeenLabel;
  final String platformLabel;
  final IconData platformIcon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final active = device.active;
    final status = active
        ? isThisDevice
            ? context.l('This device')
            : context.l('Active elsewhere')
        : context.l('Logged out');
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Material(
        color: active ? AppColors.fernGreenLight : AppColors.surfaceSecondary,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Container(
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: active
                    ? AppColors.fernGreen.withValues(alpha: 0.5)
                    : AppColors.borderSubtle,
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: AppColors.white.withValues(alpha: active ? 0.84 : 1),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(
                    platformIcon,
                    color:
                        active ? AppColors.fernGreenDark : AppColors.charcoal,
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        device.deviceName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.josefinSans(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: AppColors.charcoal,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '$status · $platformLabel · $lastSeenLabel',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.josefinSans(
                          fontSize: 12,
                          color: active
                              ? AppColors.fernGreenDark
                              : AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Icon(
                  active
                      ? Icons.check_circle_rounded
                      : Icons.info_outline_rounded,
                  color: active ? AppColors.fernGreen : AppColors.textTertiary,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DeviceInfoRow extends StatelessWidget {
  const _DeviceInfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 88,
            child: Text(
              label,
              style: GoogleFonts.josefinSans(
                fontSize: 12,
                color: AppColors.textTertiary,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: GoogleFonts.josefinSans(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppColors.charcoal,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Tile extends StatefulWidget {
  const _Tile({
    required this.icon,
    required this.label,
    required this.onTap,
    this.subtitle,
    this.trailing,
    this.color,
    this.showChevron = true,
  });
  final IconData icon;
  final String label;
  final String? subtitle;
  final Widget? trailing;
  final Color? color;
  final VoidCallback onTap;
  final bool showChevron;

  @override
  State<_Tile> createState() => _TileState();
}

class _TileState extends State<_Tile> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return AnimatedScale(
      scale: _pressed ? 0.985 : 1,
      duration: const Duration(milliseconds: 120),
      curve: Curves.easeOut,
      child: InkWell(
        onTap: widget.onTap,
        onTapDown: (_) => setState(() => _pressed = true),
        onTapCancel: () => setState(() => _pressed = false),
        onTapUp: (_) => setState(() => _pressed = false),
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.lg,
            vertical: AppSpacing.md,
          ),
          child: Row(
            children: [
              Icon(
                widget.icon,
                size: 20,
                color: widget.color ?? AppColors.charcoal,
              ),
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
                        color: widget.color ?? AppColors.charcoal,
                      ),
                    ),
                    if (widget.subtitle != null)
                      Text(
                        widget.subtitle!,
                        style: GoogleFonts.josefinSans(
                          fontSize: 12,
                          color: AppColors.textTertiary,
                        ),
                      ),
                  ],
                ),
              ),
              widget.trailing ??
                  (widget.showChevron
                      ? const Icon(
                          Icons.chevron_right_rounded,
                          size: 16,
                          color: AppColors.textTertiary,
                        )
                      : const SizedBox(width: 16)),
            ],
          ),
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
  void didUpdateWidget(covariant _SwitchTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value) {
      _value = widget.value;
    }
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
            context.l('New password'),
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
              hintText: context.l('Enter new password (min 8 chars)'),
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
                      if (!context.mounted) return;
                      Navigator.pop(context);
                    },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.charcoal,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              child: Text(
                context.l('Update password'),
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
