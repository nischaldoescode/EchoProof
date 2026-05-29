import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../app/theme/colors.dart';
import '../../../../app/theme/spacing.dart';
import '../../../../app/theme/typography.dart';
import '../../../echo/domain/entities/echo_entity.dart';
import '../../../echo/domain/entities/echo_status.dart';
import '../../../echo/presentation/widgets/echo_card.dart';
import '../../../../shared/widgets/shimmer_loader.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/utils/logger.dart';
import '../../../../core/localization/app_copy.dart';
import '../widgets/reputation_card.dart';
import '../../../settings/presentation/widgets/solana_info_card.dart';
import 'package:flutter/foundation.dart';
import '../../../../core/security/secure_screen.dart';
import '../../../../shared/widgets/app_bottom_nav.dart';
import '../../../../shared/widgets/avatar_image_provider.dart';
import '../../../../shared/widgets/rich_text_display.dart';
import '../../../../app/app.dart';
import 'package:flutter/services.dart';
import '../../../../core/utils/snack.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'analytics_tab.dart';
import 'dart:async';
import '../../../../core/utils/sanitizer.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key, this.username});

  final String? username;

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen>
    with TickerProviderStateMixin {
  Map<String, dynamic>? _profile;
  List<EchoEntity> _echoes = [];
  int _settledBonds = 0;
  int _contestedBonds = 0;
  int _activeBonds = 0;
  bool _isIdentityVerified = false;
  bool _isPublic = true;
  bool _isOwnProfile = true;
  bool _isLoading = true;
  bool _isVerificationPending = false;
  bool userIsPro = false;
  bool _isFollowing = false;
  bool _isBlockedByMe = false;
  String _followRequestStatus = 'none';
  Timer? _debounce;

  late final AnimationController _entranceCtrl;
  late final Animation<double> _fade;
  late final Animation<Offset> _slide;

  @override
  void initState() {
    super.initState();
    _isOwnProfile = widget.username == null;
    // Pro users get analytics tab; length depends on isPro and isOwnProfile.
    _entranceCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _fade = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _entranceCtrl, curve: Curves.easeOut),
    );
    _slide = Tween<Offset>(
      begin: const Offset(0, 0.05),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _entranceCtrl, curve: Curves.easeOut));

    _loadProfile();
  }

  @override
  void dispose() {
    _entranceCtrl.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  bool _isSavingProfile = false;

  bool get _canViewProfileContent =>
      _isOwnProfile || (!_isBlockedByMe && (_isPublic || _isFollowing));

// opens the edit profile bottom sheet
// covers display name, username (requires otp), gender, and dob (requires otp)
  Future<void> _showEditProfileSheet() async {
    if (_isLoading || _profile == null || _isSavingProfile) return;

    final client = Supabase.instance.client;
    final currentUsername = _profile?['username'] as String? ?? '';
    final currentDisplay = _profile?['display_name'] as String? ?? '';
    final currentGender = _profile?['gender'] as String?;

    // parse stored dob — format is yyyy-mm-dd from postgres
    DateTime? currentDob;
    final dobRaw = _profile?['date_of_birth'] as String?;
    if (dobRaw != null) {
      currentDob = DateTime.tryParse(dobRaw);
    }

    final usernameCtrl = TextEditingController(text: currentUsername);
    final displayCtrl = TextEditingController(text: currentDisplay);
    bool usernameAvailable = true;
    bool isCheckingUsername = false;
    String? usernameError;
    String? selectedGender = currentGender;
    DateTime? selectedDob = currentDob;

    // month labels for display
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];

    String formatDob(DateTime d) => '${d.day} ${months[d.month - 1]} ${d.year}';

    Future<bool> checkUsernameAvailability(String value) async {
      if (value == currentUsername) return true;
      if (value.length < 3) return false;
      try {
        final myId = client.auth.currentUser?.id;
        final row = await client
            .from('users_public')
            .select('id')
            .eq('username', value)
            .neq('id', myId ?? '')
            .maybeSingle();
        return row == null;
      } catch (_) {
        return false;
      }
    }

    const genderOptions = [
      (value: 'male', label: 'Male', icon: Icons.male_rounded),
      (value: 'female', label: 'Female', icon: Icons.female_rounded),
      (
        value: 'non_binary',
        label: 'Non-binary',
        icon: Icons.transgender_rounded
      ),
      (
        value: 'prefer_not_to_say',
        label: 'Prefer not to say',
        icon: Icons.person_outline_rounded
      ),
    ];

    await showModalBottomSheet<void>(
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
            return SingleChildScrollView(
              padding: EdgeInsets.only(
                bottom: MediaQuery.viewInsetsOf(ctx).bottom +
                    MediaQuery.paddingOf(ctx).bottom +
                    AppSpacing.xl,
                left: AppSpacing.xl,
                right: AppSpacing.xl,
                top: AppSpacing.xl,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // drag handle
                  Center(
                    child: Container(
                      width: 36,
                      height: 4,
                      decoration: BoxDecoration(
                        color: AppColors.borderMedium,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  Text(
                    context.l('Edit profile'),
                    style: AppTypography.textTheme.titleMedium,
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    context.l(
                      'Username and date of birth changes require email verification.',
                    ),
                    style: AppTypography.textTheme.bodySmall,
                  ),
                  const SizedBox(height: AppSpacing.lg),

                  // display name
                  Text(
                    context.l('Display name'),
                    style: GoogleFonts.josefinSans(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  TextField(
                    controller: displayCtrl,
                    maxLength: 50,
                    buildCounter: (_,
                            {required currentLength,
                            required isFocused,
                            maxLength}) =>
                        null,
                    style: AppTypography.textTheme.bodyMedium,
                    decoration: InputDecoration(
                      hintText: context.l('Your display name'),
                      filled: true,
                      fillColor: AppColors.softSand,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(
                            color: AppColors.fernGreen, width: 1.5),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 12),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),

                  // username
                  Text(
                    context.l('Username'),
                    style: GoogleFonts.josefinSans(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  TextField(
                      controller: usernameCtrl,
                      maxLength: 20,
                      buildCounter: (_,
                              {required currentLength,
                              required isFocused,
                              maxLength}) =>
                          null,
                      autocorrect: false,
                      style: AppTypography.textTheme.bodyMedium,
                      decoration: InputDecoration(
                        prefixText: '@',
                        hintText: context.l('username'),
                        errorText: usernameError,
                        suffixIcon: isCheckingUsername
                            ? const Padding(
                                padding: EdgeInsets.all(12),
                                child: SizedBox(
                                  width: 14,
                                  height: 14,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: AppColors.fernGreen,
                                  ),
                                ),
                              )
                            : usernameAvailable && usernameCtrl.text.length >= 3
                                ? const Icon(Icons.check_circle_rounded,
                                    size: 18, color: AppColors.fernGreen)
                                : null,
                        filled: true,
                        fillColor: AppColors.softSand,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide.none,
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(
                              color: AppColors.fernGreen, width: 1.5),
                        ),
                        errorBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide:
                              const BorderSide(color: AppColors.sunsetCoral),
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 12),
                      ),
                      onChanged: (v) {
                        _debounce?.cancel();

                        setSheet(() {
                          isCheckingUsername = true;
                          usernameError = null;
                        });

                        _debounce =
                            Timer(const Duration(milliseconds: 400), () async {
                          if (!ctx.mounted) return;

                          if (v.length < 3) {
                            setSheet(() {
                              isCheckingUsername = false;
                              usernameAvailable = false;
                              usernameError =
                                  context.l('At least 3 characters');
                            });
                            return;
                          }

                          final available =
                              await checkUsernameAvailability(v.toLowerCase());

                          if (!ctx.mounted) return;

                          setSheet(() {
                            isCheckingUsername = false;
                            usernameAvailable = available;
                            usernameError = available
                                ? null
                                : context.l('Username already taken');
                          });
                        });
                      }),
                  const SizedBox(height: AppSpacing.lg),

                  // date of birth — requires otp to change
                  Text(
                    context.l('Date of birth'),
                    style: GoogleFonts.josefinSans(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  GestureDetector(
                    onTap: () async {
                      final now = DateTime.now();
                      final picked = await showDatePicker(
                        context: ctx,
                        initialDate: selectedDob ??
                            DateTime(now.year - 18, now.month, now.day),
                        firstDate: DateTime(now.year - 120, now.month, now.day),
                        lastDate: DateTime(now.year - 13, now.month, now.day),
                        helpText: context.l('select your date of birth'),
                        builder: (dateCtx, child) => Theme(
                          data: Theme.of(dateCtx).copyWith(
                            colorScheme: ColorScheme.light(
                              primary: AppColors.fernGreen,
                              onPrimary: Colors.white,
                              surface: Colors.white,
                              onSurface: AppColors.charcoal,
                            ),
                            textButtonTheme: TextButtonThemeData(
                              style: TextButton.styleFrom(
                                foregroundColor: AppColors.fernGreen,
                                textStyle: GoogleFonts.josefinSans(
                                    fontWeight: FontWeight.w600),
                              ),
                            ),
                          ),
                          child: child!,
                        ),
                      );
                      if (picked != null) {
                        setSheet(() => selectedDob = picked);
                      }
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 14),
                      decoration: BoxDecoration(
                        color: AppColors.softSand,
                        borderRadius: BorderRadius.circular(12),
                        border: selectedDob != currentDob
                            ? Border.all(color: AppColors.fernGreen, width: 1.5)
                            : null,
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.cake_outlined,
                            size: 16,
                            color: selectedDob != null
                                ? AppColors.fernGreen
                                : AppColors.textTertiary,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              selectedDob != null
                                  ? formatDob(selectedDob!)
                                  : context.l('Not set'),
                              style: GoogleFonts.josefinSans(
                                fontSize: 14,
                                color: selectedDob != null
                                    ? AppColors.charcoal
                                    : AppColors.textTertiary,
                              ),
                            ),
                          ),
                          const Icon(
                            Icons.edit_outlined,
                            size: 14,
                            color: AppColors.textTertiary,
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.lg),

                  // gender selector
                  Text(
                    context.l('Gender'),
                    style: GoogleFonts.josefinSans(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  GridView.count(
                    crossAxisCount: 2,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    crossAxisSpacing: AppSpacing.sm,
                    mainAxisSpacing: AppSpacing.sm,
                    childAspectRatio: 2.8,
                    children: genderOptions.map((g) {
                      final sel = selectedGender == g.value;
                      return GestureDetector(
                        onTap: () {
                          HapticFeedback.selectionClick();
                          setSheet(() => selectedGender = g.value);
                        },
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          decoration: BoxDecoration(
                            color: sel ? AppColors.charcoal : Colors.white,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: sel
                                  ? AppColors.charcoal
                                  : AppColors.borderSubtle,
                              width: sel ? 2 : 1,
                            ),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                g.icon,
                                size: 14,
                                color: sel
                                    ? Colors.white
                                    : AppColors.textSecondary,
                              ),
                              const SizedBox(width: 5),
                              Flexible(
                                child: Text(
                                  context.l(g.label),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: GoogleFonts.josefinSans(
                                    fontSize: 12,
                                    fontWeight:
                                        sel ? FontWeight.w600 : FontWeight.w400,
                                    color: sel
                                        ? Colors.white
                                        : AppColors.textSecondary,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: AppSpacing.xl),

                  // save button
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: (usernameAvailable && !isCheckingUsername)
                          ? () async {
                              Navigator.pop(ctx);
                              await _saveProfileChanges(
                                newUsername:
                                    usernameCtrl.text.trim().toLowerCase(),
                                newDisplayName: displayCtrl.text.trim(),
                                currentUsername: currentUsername,
                                newGender:
                                    selectedGender ?? 'prefer_not_to_say',
                                newDob: selectedDob,
                                currentDob: currentDob,
                              );
                            }
                          : null,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.charcoal,
                        disabledBackgroundColor: AppColors.borderMedium,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        elevation: 0,
                      ),
                      child: Text(
                        context.l('Save changes'),
                        style: GoogleFonts.josefinSans(
                            fontWeight: FontWeight.w600),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

// saves profile changes
// username changes and dob changes both require otp re-verification
// gender and display name save silently without otp
  Future<void> _saveProfileChanges({
    required String newUsername,
    required String newDisplayName,
    required String currentUsername,
    required String newGender,
    required DateTime? newDob,
    required DateTime? currentDob,
  }) async {
    final usernameChanged = newUsername != currentUsername;
    final displayChanged =
        newDisplayName != (_profile?['display_name'] as String? ?? '');
    final genderChanged = newGender != (_profile?['gender'] as String? ?? '');
    final dobChanged = newDob != null &&
        (currentDob == null ||
            newDob.year != currentDob.year ||
            newDob.month != currentDob.month ||
            newDob.day != currentDob.day);

    if (usernameChanged || displayChanged || genderChanged || dobChanged) {
      final retryAfter = await _profileCooldownRemaining();
      if (retryAfter > 0) {
        if (mounted) {
          showInfoSnack(
            context,
            context.l('Profile changes are cooling down. Try again in {time}.',
                {'time': _formatCooldown(retryAfter)}),
          );
        }
        return;
      }
    }

    // otp required if username or dob changed
    final needsOtp = usernameChanged || dobChanged;

    if (needsOtp) {
      final email = Supabase.instance.client.auth.currentUser?.email;
      if (email == null) return;

      setState(() => _isSavingProfile = true);

      try {
        await Supabase.instance.client.auth.signInWithOtp(
          email: email,
          shouldCreateUser: false,
          emailRedirectTo: 'echoproof://auth-callback',
        );
      } catch (e) {
        AppLogger.error('profile: otp send failed $e');
        setState(() => _isSavingProfile = false);
        return;
      }

      if (!mounted) return;

      final otpVerified = await _showOtpVerificationDialog(email);
      if (!mounted) return;

      if (!otpVerified) {
        setState(() => _isSavingProfile = false);
        return;
      }
    }

    setState(() => _isSavingProfile = true);

    try {
      final client = Supabase.instance.client;
      final userId = client.auth.currentUser?.id;
      if (userId == null) return;

      // build patch — only include changed fields
      final patch = <String, dynamic>{
        'display_name': Sanitizer.displayName(
            newDisplayName.isNotEmpty ? newDisplayName : newUsername),
        'gender': newGender,
      };
      if (usernameChanged) patch['username'] = Sanitizer.username(newUsername);

      if (dobChanged) {
        // calculate age from new dob
        final today = DateTime.now();
        int age = today.year - newDob.year;
        if (today.month < newDob.month ||
            (today.month == newDob.month && today.day < newDob.day)) {
          age--;
        }
        patch['date_of_birth'] = '${newDob.year.toString().padLeft(4, '0')}-'
            '${newDob.month.toString().padLeft(2, '0')}-'
            '${newDob.day.toString().padLeft(2, '0')}';
        patch['age'] = age;
      }

      await client.from('users_public').update(patch).eq('id', userId);

      setState(() {
        _profile = {
          ..._profile!,
          'username': newUsername,
          'display_name': newDisplayName,
          'gender': newGender,
          if (dobChanged)
            'date_of_birth': '${newDob.year.toString().padLeft(4, '0')}-'
                '${newDob.month.toString().padLeft(2, '0')}-'
                '${newDob.day.toString().padLeft(2, '0')}',
        };
      });

      if (mounted) {
        showSuccessSnack(context, context.l('Profile updated.'));
      }
    } catch (e) {
      AppLogger.error('profile: save changes failed $e');
      if (mounted) {
        showErrorSnack(context, _profileUpdateErrorMessage(e));
      }
    }

    setState(() => _isSavingProfile = false);
  }

  Future<int> _profileCooldownRemaining() async {
    try {
      final client = Supabase.instance.client;
      final userId = client.auth.currentUser?.id;
      if (userId == null) return 0;
      final response = await client.rpc('get_action_cooldown_status', params: {
        'p_action': 'profile_update',
        'p_subject': userId,
        'p_window_seconds': 20 * 60,
        'p_max_actions': 1,
        'p_include_ip': false,
      });
      final map = Map<String, dynamic>.from(response as Map);
      return (map['retry_after_seconds'] as num?)?.toInt() ?? 0;
    } catch (e) {
      AppLogger.warn('profile: cooldown check failed $e');
      return 0;
    }
  }

  String _profileUpdateErrorMessage(Object error) {
    if (error is PostgrestException &&
        error.message.toLowerCase().contains('profile_update_cooldown')) {
      final detail = error.details?.toString() ?? '';
      final seconds = int.tryParse(RegExp(r'\d+').stringMatch(detail) ?? '');
      if (seconds != null && seconds > 0) {
        return context.l(
          'Profile changes are cooling down. Try again in {time}.',
          {'time': _formatCooldown(seconds)},
        );
      }
      return context
          .l('Profile changes are cooling down. Please try again later.');
    }
    return context.l('Failed to save changes. Please try again.');
  }

  String _formatCooldown(int seconds) {
    final minutes = (seconds / 60).ceil();
    if (minutes <= 1) return '$seconds seconds';
    return '$minutes minutes';
  }

  Future<bool> _showOtpVerificationDialog(String email) async {
    final otpCtrl = TextEditingController();
    bool isVerifying = false;
    bool? result;

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setDialog) {
            return AlertDialog(
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16)),
              title: Text(
                context.l('Verify your email'),
                style: GoogleFonts.josefinSans(fontWeight: FontWeight.w700),
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    context.l(
                      'A verification code was sent to {email}. Enter it to confirm the username change.',
                      {'email': email},
                    ),
                    style: GoogleFonts.josefinSans(fontSize: 13, height: 1.5),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: otpCtrl,
                    keyboardType: TextInputType.number,
                    maxLength: 6,
                    buildCounter: (_,
                            {required currentLength,
                            required isFocused,
                            maxLength}) =>
                        null,
                    autofocus: true,
                    textAlign: TextAlign.center,
                    style: GoogleFonts.josefinSans(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 8,
                    ),
                    decoration: InputDecoration(
                      hintText: '000000',
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10)),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: const BorderSide(
                            color: AppColors.fernGreen, width: 2),
                      ),
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    result = false;
                    Navigator.pop(ctx);
                  },
                  child: Text(context.l('Cancel'),
                      style: GoogleFonts.josefinSans(
                          color: AppColors.textSecondary)),
                ),
                TextButton(
                  onPressed: isVerifying
                      ? null
                      : () async {
                          if (otpCtrl.text.length != 6) return;
                          setDialog(() => isVerifying = true);
                          try {
                            await Supabase.instance.client.auth.verifyOTP(
                              email: email,
                              token: otpCtrl.text,
                              type: OtpType.email,
                            );
                            result = true;
                          } catch (_) {
                            result = false;
                          }
                          if (ctx.mounted) Navigator.pop(ctx);
                        },
                  child: isVerifying
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: AppColors.fernGreen,
                          ),
                        )
                      : Text(
                          context.l('Verify'),
                          style: GoogleFonts.josefinSans(
                            color: AppColors.fernGreen,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                ),
              ],
            );
          },
        );
      },
    );

    return result == true;
  }

  Future<void> _loadProfile() async {
    setState(() => _isLoading = true);
    final client = Supabase.instance.client;
    final myId = client.auth.currentUser?.id;

    try {
      Map<String, dynamic> profile;

      if (widget.username != null) {
        _isOwnProfile = false;
        final result = await client
            .from('users_public')
            .select(
              'id, username, display_name, avatar_url, trust_tier, trust_score, '
              'echo_count, proof_count, is_public, bio, gender, date_of_birth, is_pro, follower_count, following_count',
            )
            .eq('username', widget.username!)
            .maybeSingle();
        if (result == null) {
          setState(() => _isLoading = false);
          return;
        }
        final row = result;
        profile = row;
      } else {
        _isOwnProfile = true;
        final result = await client
            .from('users_public')
            .select(
              'id, username, display_name, avatar_url, trust_tier, trust_score, '
              'echo_count, proof_count, is_public, bio, gender, date_of_birth, is_pro, follower_count, following_count',
            )
            .eq('id', myId!)
            .maybeSingle();
        if (result == null) {
          setState(() => _isLoading = false);
          return;
        }
        final row = result;
        profile = row;
        // as Map<String, dynamic>
      }

      final targetId = profile['id'] as String;
      final resolvedOwnProfile = myId != null && targetId == myId;
      if (resolvedOwnProfile && widget.username != null && mounted) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) context.go('/profile');
        });
      }
      _isOwnProfile = resolvedOwnProfile;
      _isPublic = profile['is_public'] as bool? ?? true;
      userIsPro = profile['is_pro'] as bool? ?? false;

      if (!_isOwnProfile) {
        await _loadRelationshipState(targetId);
      } else {
        _isFollowing = false;
        _isBlockedByMe = false;
        _followRequestStatus = 'none';
      }

      if (!_canViewProfileContent) {
        setState(() {
          _profile = profile;
          _echoes = [];
          _isLoading = false;
        });
        _entranceCtrl.forward();
        return;
      }

      final results = await Future.wait<dynamic>([
        client
            .from('echoes')
            .select(
              'id, title, content, category, category_detail, status, trust_score, '
              'confidence_score, controversy_score, support_count, '
              'challenge_count, context_support_count, context_challenge_count, '
              'public_verdict, reply_count, created_at, media_urls, '
              'created_record_tx, created_record_at, solana_status, solana_error, '
              'verified_record_tx, verified_record_at, '
              'verified_record_status, verified_record_error, bond_count',
            )
            .eq('user_id', targetId)
            .not('status', 'in', '("hidden","rejected")')
            .order('created_at', ascending: false)
            .limit(20),
        if (_isOwnProfile) ...[
          client
              .from('truth_bonds')
              .select('bond_status')
              .eq('user_id', targetId),
          client
              .from('users_private')
              .select('is_identity_verified, last_verification_request_at')
              .eq('id', targetId)
              .maybeSingle(),
        ],
      ]);

      final echoes = results[0] as List<dynamic>;
      final bonds = _isOwnProfile ? results[1] as List<dynamic> : [];
      final priv = (_isOwnProfile && results.length > 2)
          ? results[2] as Map<String, dynamic>?
          : null;

      final echoEntities = echoes.map((row) {
        final r = row as Map<String, dynamic>;
        final created = DateTime.tryParse(r['created_at'] as String? ?? '') ??
            DateTime.now();
        return EchoEntity(
          id: r['id'] as String,
          title: r['title'] as String? ?? '',
          content: r['content'] as String,
          username: profile['username'] as String,
          userDisplayName:
              (profile['display_name'] as String?)?.trim().isNotEmpty == true
                  ? profile['display_name'] as String
                  : profile['username'] as String,
          userTrustTier: profile['trust_tier'] as String? ?? 'unverified',
          userIsVerified: priv?['is_identity_verified'] as bool? ?? false,
          userAvatarUrl: profile['avatar_url'] as String?,
          category: EchoCategory.fromString(r['category'] as String),
          categoryDetail: r['category_detail'] as String?,
          status: _parseStatus(r['status'] as String),
          confidenceScore: (r['confidence_score'] as num?)?.toDouble() ?? 0,
          trustScore: (r['trust_score'] as num?)?.toInt() ?? 0,
          controversyScore: (r['controversy_score'] as num?)?.toDouble() ?? 0,
          supportCount: (r['context_support_count'] as num?)?.toInt() ??
              (r['support_count'] as num?)?.toInt() ??
              0,
          challengeCount: (r['context_challenge_count'] as num?)?.toInt() ??
              (r['challenge_count'] as num?)?.toInt() ??
              0,
          contextSupportCount:
              (r['context_support_count'] as num?)?.toInt() ?? 0,
          contextChallengeCount:
              (r['context_challenge_count'] as num?)?.toInt() ?? 0,
          publicVerdict: r['public_verdict'] as String? ?? 'open',
          timeAgo: Formatters.timeAgo(created),
          userIsPro: profile['is_pro'] as bool? ?? false,
          mediaUrls: (r['media_urls'] as List?)?.cast<String>() ?? const [],
          replyCount: (r['reply_count'] as num?)?.toInt() ?? 0,
          userId: targetId,
          createdRecordTx: r['created_record_tx'] as String?,
          createdRecordAt: _parseDate(r['created_record_at']),
          solanaStatus: r['solana_status'] as String? ?? 'pending',
          solanaError: r['solana_error'] as String?,
          verifiedRecordTx: r['verified_record_tx'] as String?,
          verifiedRecordAt: _parseDate(r['verified_record_at']),
          verifiedRecordStatus:
              r['verified_record_status'] as String? ?? 'pending',
          verifiedRecordError: r['verified_record_error'] as String?,
          bondCount: (r['bond_count'] as num?)?.toInt() ?? 0,
        );
      }).toList();

      final storedEchoCount = (profile['echo_count'] as num?)?.toInt() ?? 0;
      final loadedEchoCount = echoEntities.length;
      final displayEchoCount =
          storedEchoCount > loadedEchoCount ? storedEchoCount : loadedEchoCount;
      final displayProfile = {
        ...profile,
        'echo_count': displayEchoCount,
      };

      setState(() {
        _profile = displayProfile;
        _echoes = echoEntities;
        _settledBonds =
            bonds.where((b) => b['bond_status'] == 'settled').length;
        _contestedBonds =
            bonds.where((b) => b['bond_status'] == 'contested').length;
        _activeBonds = bonds.where((b) => b['bond_status'] == 'active').length;
        _isIdentityVerified = priv?['is_identity_verified'] as bool? ?? false;
        // Check if pending
        final lastReqStr = priv?['last_verification_request_at'] as String?;
        if (lastReqStr != null && !_isIdentityVerified) {
          final reqTime = DateTime.tryParse(lastReqStr);
          if (reqTime != null) {
            _isVerificationPending =
                DateTime.now().difference(reqTime).inMinutes < 60;
          }
        }
        _isLoading = false;
      });
      _entranceCtrl.forward();
    } catch (e) {
      AppLogger.error('profile: load failed $e');
      setState(() => _isLoading = false);
    }
  }

  Future<void> _loadRelationshipState(String targetId) async {
    final client = Supabase.instance.client;
    final myId = client.auth.currentUser?.id;
    if (myId == null) return;

    try {
      final followRow = await client
          .from('user_follows')
          .select('id')
          .eq('follower_id', myId)
          .eq('following_id', targetId)
          .maybeSingle();

      final blockRow = await client
          .from('user_blocks')
          .select('id')
          .eq('blocker_id', myId)
          .eq('blocked_id', targetId)
          .maybeSingle();

      Map<String, dynamic>? requestRow;
      try {
        requestRow = await client
            .from('follow_requests')
            .select('id, status')
            .eq('requester_id', myId)
            .eq('target_id', targetId)
            .maybeSingle();
      } catch (_) {
        requestRow = null;
      }

      if (!mounted) return;
      setState(() {
        _isFollowing = followRow != null;
        _isBlockedByMe = blockRow != null;
        _followRequestStatus = requestRow?['status'] as String? ??
            (_isFollowing ? 'accepted' : 'none');
      });
    } catch (e) {
      AppLogger.warn('profile: relationship load failed $e');
    }
  }

  Future<void> _toggleFollow() async {
    if (_isBlockedByMe) {
      showInfoSnack(context, context.l('Unblock this user before following.'));
      return;
    }

    final client = Supabase.instance.client;
    final myId = client.auth.currentUser?.id;
    if (myId == null || _profile == null) return;
    final targetId = _profile!['id'] as String;
    final wasFollowing = _isFollowing;
    final previousRequestStatus = _followRequestStatus;

    try {
      if (_isFollowing) {
        setState(() {
          _isFollowing = false;
          _followRequestStatus = 'none';
        });
        await client
            .from('user_follows')
            .delete()
            .eq('follower_id', myId)
            .eq('following_id', targetId);
      } else if (!_isPublic) {
        if (_followRequestStatus == 'pending') {
          setState(() => _followRequestStatus = 'none');
          await client
              .from('follow_requests')
              .delete()
              .eq('requester_id', myId)
              .eq('target_id', targetId)
              .eq('status', 'pending');
          if (mounted) {
            showInfoSnack(context, context.l('Follow request canceled'));
          }
        } else {
          setState(() => _followRequestStatus = 'pending');
          final row = await client
              .from('follow_requests')
              .upsert({
                'requester_id': myId,
                'target_id': targetId,
                'status': 'pending',
              }, onConflict: 'requester_id,target_id')
              .select('id')
              .single();
          final requestId = row['id'] as String?;
          if (requestId != null) {
            unawaited(_notifySocialEvent('follow_request', {
              'request_id': requestId,
            }));
          }
          if (mounted) {
            showSuccessSnack(context, context.l('Follow request sent'));
          }
        }
      } else {
        setState(() {
          _isFollowing = true;
          _followRequestStatus = 'accepted';
        });
        await client.from('user_follows').upsert({
          'follower_id': myId,
          'following_id': targetId,
        }, onConflict: 'follower_id,following_id');
        unawaited(_notifySocialEvent('new_follower', {
          'target_id': targetId,
        }));
      }
      // Refresh follower count on profile.
      await _loadProfile();
    } catch (e) {
      setState(() {
        _isFollowing = wasFollowing;
        _followRequestStatus = previousRequestStatus;
      });
      if (mounted) {
        showErrorSnack(context, context.l('Could not update follow status.'));
      }
    }
  }

  Future<void> _notifySocialEvent(
    String event,
    Map<String, dynamic> body,
  ) async {
    try {
      await Supabase.instance.client.functions.invoke(
        'notify-social-event',
        body: {'event': event, ...body},
      );
    } catch (e) {
      AppLogger.warn('profile: social event notify failed $e');
    }
  }

  Future<void> _confirmBlockProfileUser() async {
    if (_profile == null || _isOwnProfile) return;
    final username = _profile!['username'] as String? ?? 'this user';

    final shouldBlock = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.borderMedium,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              Row(
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: AppColors.sunsetCoral.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Icon(
                      Icons.block_rounded,
                      color: AppColors.sunsetCoral,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Text(
                      context.l('Block @{username}?', {'username': username}),
                      style: AppTypography.textTheme.titleMedium,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              Text(
                context.l(
                  'You will stop seeing each other in profiles, feeds, replies, and interactions. Existing follow links are removed.',
                ),
                style: AppTypography.textTheme.bodySmall
                    ?.copyWith(color: AppColors.textSecondary, height: 1.45),
              ),
              const SizedBox(height: AppSpacing.lg),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(sheetContext, false),
                      child: Text(context.l('Cancel')),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () => Navigator.pop(sheetContext, true),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.sunsetCoral,
                        foregroundColor: Colors.white,
                      ),
                      child: Text(context.l('Block')),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );

    if (shouldBlock == true) {
      await _blockProfileUser();
    }
  }

  Future<void> _blockProfileUser() async {
    final client = Supabase.instance.client;
    final myId = client.auth.currentUser?.id;
    final targetId = _profile?['id'] as String?;
    if (myId == null || targetId == null || targetId == myId) return;

    try {
      await client.from('user_blocks').upsert({
        'blocker_id': myId,
        'blocked_id': targetId,
      }, onConflict: 'blocker_id,blocked_id');

      setState(() {
        _isBlockedByMe = true;
        _isFollowing = false;
        _followRequestStatus = 'none';
        _echoes = [];
      });

      if (mounted) showSuccessSnack(context, context.l('User blocked'));
      await _loadProfile();
    } catch (e) {
      AppLogger.error('profile: block failed $e');
      if (mounted) showErrorSnack(context, context.l('Could not block user.'));
    }
  }

  Future<void> _unblockProfileUser({String? userId}) async {
    final client = Supabase.instance.client;
    final myId = client.auth.currentUser?.id;
    final targetId = userId ?? (_profile?['id'] as String?);
    if (myId == null || targetId == null) return;

    try {
      await client
          .from('user_blocks')
          .delete()
          .eq('blocker_id', myId)
          .eq('blocked_id', targetId);

      if (targetId == _profile?['id']) {
        setState(() => _isBlockedByMe = false);
        await _loadProfile();
      }

      if (mounted) showSuccessSnack(context, context.l('User unblocked'));
    } catch (e) {
      AppLogger.error('profile: unblock failed $e');
      if (mounted) {
        showErrorSnack(context, context.l('Could not unblock user.'));
      }
    }
  }

  Future<void> _setPublic(bool v) async {
    setState(() => _isPublic = v);
    final client = Supabase.instance.client;
    final userId = client.auth.currentUser?.id;
    if (userId == null) return;
    try {
      await client
          .from('users_public')
          .update({'is_public': v}).eq('id', userId);
    } catch (e) {
      AppLogger.error('profile: set public failed $e');
      setState(() => _isPublic = !v);
    }
  }

  Future<void> _updateBio(String newBio) async {
    final client = Supabase.instance.client;
    final userId = client.auth.currentUser?.id;
    if (userId == null) return;
    if (newBio == (_profile?['bio'] as String? ?? '')) return;
    final retryAfter = await _profileCooldownRemaining();
    if (retryAfter > 0) {
      if (mounted) {
        showInfoSnack(
          context,
          context.l('Profile changes are cooling down. Try again in {time}.',
              {'time': _formatCooldown(retryAfter)}),
        );
      }
      return;
    }
    try {
      await client
          .from('users_public')
          .update({'bio': newBio}).eq('id', userId);
      setState(() {
        _profile = {
          ..._profile!,
          'bio': newBio,
        };
      });
    } catch (e) {
      AppLogger.error('profile: bio update failed $e');
      if (mounted) {
        showErrorSnack(context, _profileUpdateErrorMessage(e));
      }
    }
  }

  Future<void> _showEditBioSheet() async {
    final currentBio = _profile?['bio'] as String? ?? '';
    final ctrl = TextEditingController(text: currentBio);

    final result = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: AppColors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(ctx).bottom,
          left: AppSpacing.xl,
          right: AppSpacing.xl,
          top: AppSpacing.xl,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.borderMedium,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            Text(context.l('Edit bio'),
                style: AppTypography.textTheme.titleMedium),
            const SizedBox(height: AppSpacing.xs),
            Text(
              context.l('Visible on your public profile.'),
              style: AppTypography.textTheme.bodySmall,
            ),
            const SizedBox(height: AppSpacing.lg),
            TextField(
              controller: ctrl,
              maxLines: 4,
              maxLength: 160,
              autofocus: true,
              style: AppTypography.textTheme.bodyMedium,
              decoration: InputDecoration(
                hintText: context.l('Write something about yourself...'),
                hintStyle: GoogleFonts.josefinSans(
                  fontSize: 14,
                  color: AppColors.textTertiary,
                ),
                filled: true,
                fillColor: AppColors.softSand,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(
                    color: AppColors.fernGreen,
                    width: 1.5,
                  ),
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.charcoal,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  elevation: 0,
                ),
                child: Text(
                  context.l('Save bio'),
                  style: GoogleFonts.josefinSans(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.xl),
          ],
        ),
      ),
    );

    if (result != null) {
      await _updateBio(result);
    }
  }

  Widget _buildBody() {
    if (_isLoading) {
      return EchoLogoLoader(label: context.l('Loading profile'));
    }

    if (_profile == null) {
      return Center(
        child: Text(
          context.l('Could not load profile'),
          style: AppTypography.textTheme.bodyMedium,
        ),
      );
    }

    final locked = !_canViewProfileContent;
    final tabs = locked
        ? <Widget>[Tab(text: context.l('Private'))]
        : <Widget>[
            Tab(text: context.l('Echoes')),
            Tab(text: context.l('Replies')),
            Tab(text: context.l('Media')),
            Tab(text: context.l('Followers')),
            Tab(text: context.l('Following')),
            if (_isOwnProfile && userIsPro) Tab(text: context.l('Analytics')),
          ];

    final tabViews = locked
        ? <Widget>[
            _LockedProfileTab(username: _profile!['username'] as String),
          ]
        : <Widget>[
            _EchoesTab(echoes: _echoes),
            _RepliesTab(userId: _profile!['id']),
            _MediaTab(userId: _profile!['id']),
            _FollowUsersTab(
              mode: 'followers',
              loadUsers: () => _loadFollowUsers(
                client: Supabase.instance.client,
                targetId: _profile!['id'] as String,
                mode: 'followers',
              ),
            ),
            _FollowUsersTab(
              mode: 'following',
              loadUsers: () => _loadFollowUsers(
                client: Supabase.instance.client,
                targetId: _profile!['id'] as String,
                mode: 'following',
              ),
            ),
            if (_isOwnProfile && userIsPro)
              AnalyticsTab(userId: _profile!['id']),
          ];

    return DefaultTabController(
      length: tabs.length,
      child: FadeTransition(
        opacity: _fade,
        child: SlideTransition(
          position: _slide,
          child: SlideTransition(
            position: _slide,
            child: RefreshIndicator(
              color: AppColors.fernGreen,
              onRefresh: _loadProfile,
              child: NestedScrollView(
                  headerSliverBuilder: (context, innerBoxIsScrolled) => [
                        SliverToBoxAdapter(
                          child: Padding(
                            padding: const EdgeInsets.all(AppSpacing.xl),
                            child: Column(
                              children: [
                                _AvatarCard(
                                  profile: _profile!,
                                  isIdentityVerified: _isIdentityVerified,
                                  isOwnProfile: _isOwnProfile,
                                  showStats: _canViewProfileContent,
                                  onOpenFollowers: () =>
                                      _showFollowList(mode: 'followers'),
                                  onOpenFollowing: () =>
                                      _showFollowList(mode: 'following'),
                                  onEditBio: _showEditBioSheet,
                                ),
                                if (!_isOwnProfile) ...[
                                  const SizedBox(height: AppSpacing.md),
                                  SizedBox(
                                    width: double.infinity,
                                    child: _isBlockedByMe
                                        ? _UnblockButton(
                                            onPressed: () =>
                                                _unblockProfileUser(),
                                          )
                                        : _ProfileFollowButton(
                                            isFollowing: _isFollowing,
                                            requestStatus: _followRequestStatus,
                                            isPrivate: !_isPublic,
                                            onPressed: _toggleFollow,
                                          ),
                                  ),
                                ],
                                const SizedBox(height: AppSpacing.md),
                                if (_isOwnProfile)
                                  _VisibilityToggle(
                                    isPublic: _isPublic,
                                    onToggle: _setPublic,
                                  ),
                                if (!_isOwnProfile &&
                                    !_isPublic &&
                                    !_isBlockedByMe)
                                  _PrivateProfileNotice(
                                    username: _profile!['username'] as String,
                                    requestStatus: _followRequestStatus,
                                  ),
                                if (!_isOwnProfile && _isBlockedByMe)
                                  _BlockedProfileNotice(
                                    username: _profile!['username'] as String,
                                    onUnblock: () => _unblockProfileUser(),
                                  ),
                                const SizedBox(height: AppSpacing.md),
                                if (_canViewProfileContent)
                                  ReputationCard(
                                    username:
                                        _profile!['username'] as String? ?? '',
                                    trustTier:
                                        _profile!['trust_tier'] as String? ??
                                            'unverified',
                                    trustScore:
                                        (_profile!['trust_score'] as num?)
                                                ?.toInt() ??
                                            0,
                                    echoCount: (_profile!['echo_count'] as num?)
                                            ?.toInt() ??
                                        0,
                                    proofCount:
                                        (_profile!['proof_count'] as num?)
                                                ?.toInt() ??
                                            0,
                                    isIdentityVerified: _isIdentityVerified,
                                    settledBonds: _settledBonds,
                                    contestedBonds: _contestedBonds,
                                    activeBonds: _activeBonds,
                                    avatarUrl:
                                        _profile!['avatar_url'] as String?,
                                    walletAddress:
                                        _profile!['wallet_address'] as String?,
                                  ),
                                const SizedBox(height: AppSpacing.lg),
                                if (_isOwnProfile && !_isIdentityVerified)
                                  _VerifyPrompt(
                                      isPending: _isVerificationPending),
                                const SizedBox(height: AppSpacing.lg),
                                if (_isOwnProfile) ...[
                                  const SolanaInfoCard(),
                                  const SizedBox(height: AppSpacing.lg),
                                ],
                              ],
                            ),
                          ),
                        ),
                        SliverPersistentHeader(
                          pinned: true,
                          delegate: _TabBarDelegate(
                            TabBar(
                              tabs: tabs,
                              isScrollable: tabs.length > 4,
                              tabAlignment:
                                  tabs.length > 4 ? TabAlignment.start : null,
                            ),
                          ),
                        ),
                      ],
                  body: TabBarView(children: tabViews)),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _showFollowList({required String mode}) async {
    if (_profile == null || !_canViewProfileContent) return;

    final title =
        mode == 'followers' ? context.l('Followers') : context.l('Following');
    final client = Supabase.instance.client;
    final targetId = _profile!['id'] as String;

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) => FutureBuilder<List<Map<String, dynamic>>>(
        future:
            _loadFollowUsers(client: client, targetId: targetId, mode: mode),
        builder: (context, snapshot) {
          final users = snapshot.data ?? const <Map<String, dynamic>>[];
          return DraggableScrollableSheet(
            expand: false,
            initialChildSize: 0.55,
            minChildSize: 0.35,
            maxChildSize: 0.9,
            builder: (context, controller) => Column(
              children: [
                const SizedBox(height: AppSpacing.sm),
                Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.borderMedium,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(AppSpacing.lg),
                  child: Row(
                    children: [
                      Text(title, style: AppTypography.textTheme.titleMedium),
                      const Spacer(),
                      IconButton(
                        icon: const Icon(Icons.close_rounded),
                        onPressed: () => Navigator.pop(sheetContext),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: snapshot.connectionState == ConnectionState.waiting
                      ? const Center(
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: AppColors.fernGreen,
                          ),
                        )
                      : users.isEmpty
                          ? Center(
                              child: Text(
                                context.l('No {kind} yet.', {
                                  'kind': mode == 'followers'
                                      ? context.l('followers')
                                      : context.l('following'),
                                }),
                                style: AppTypography.textTheme.bodySmall
                                    ?.copyWith(color: AppColors.textSecondary),
                              ),
                            )
                          : ListView.separated(
                              controller: controller,
                              physics: const AlwaysScrollableScrollPhysics(),
                              itemCount: users.length,
                              separatorBuilder: (_, __) =>
                                  const Divider(height: 1),
                              itemBuilder: (context, index) {
                                final user = users[index];
                                final username =
                                    user['username'] as String? ?? '';
                                final displayName =
                                    (user['display_name'] as String?)
                                                ?.trim()
                                                .isNotEmpty ==
                                            true
                                        ? user['display_name'] as String
                                        : username;
                                final avatarUrl = user['avatar_url'] as String?;

                                return ListTile(
                                  leading: CircleAvatar(
                                    backgroundColor: AppColors.softSand,
                                    backgroundImage:
                                        avatarImageProvider(avatarUrl),
                                    child:
                                        avatarImageProvider(avatarUrl) == null
                                            ? const Icon(Icons.person_outline,
                                                color: AppColors.textTertiary)
                                            : null,
                                  ),
                                  title: Text(
                                    displayName,
                                    style: AppTypography.textTheme.titleSmall,
                                  ),
                                  subtitle: Text(
                                    '@$username',
                                    style: AppTypography.textTheme.labelMedium,
                                  ),
                                  onTap: username.isEmpty
                                      ? null
                                      : () {
                                          Navigator.pop(sheetContext);
                                          if (username ==
                                              _profile?['username']) {
                                            return;
                                          }
                                          context.push(
                                            '/profile/${Uri.encodeComponent(username)}',
                                          );
                                        },
                                );
                              },
                            ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Future<List<Map<String, dynamic>>> _loadFollowUsers({
    required SupabaseClient client,
    required String targetId,
    required String mode,
  }) async {
    final idColumn = mode == 'followers' ? 'follower_id' : 'following_id';
    final matchColumn = mode == 'followers' ? 'following_id' : 'follower_id';
    final rows = await client
        .from('user_follows')
        .select(idColumn)
        .eq(matchColumn, targetId)
        .limit(100);

    final ids = (rows as List)
        .map((row) => (row as Map<String, dynamic>)[idColumn] as String?)
        .whereType<String>()
        .toList();
    if (ids.isEmpty) return const [];

    final idList = ids.join(',');
    final users = await client
        .from('users_public')
        .select('id, username, display_name, avatar_url, trust_tier, is_pro')
        .filter('id', 'in', '($idList)')
        .order('username');

    return List<Map<String, dynamic>>.from(users as List);
  }

  void _showBlockedUsersSheet() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _BlockedUsersSheet(
        loadBlockedUsers: _loadBlockedUsers,
        onUnblock: (userId) => _unblockProfileUser(userId: userId),
      ),
    );
  }

  void _showOwnProfileMenu() {
    if (_isLoading || _profile == null) return;

    showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      backgroundColor: AppColors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (ctx, setSheetState) => Padding(
            padding: EdgeInsets.fromLTRB(
              AppSpacing.xl,
              AppSpacing.lg,
              AppSpacing.xl,
              AppSpacing.xl + MediaQuery.paddingOf(ctx).bottom,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.borderMedium,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: AppSpacing.xl),
                _ProfileMenuTile(
                  icon: Icons.edit_outlined,
                  title: context.l('Edit profile'),
                  subtitle: context.l('Name, username, birthday, and gender'),
                  onTap: () {
                    Navigator.pop(sheetContext);
                    _showEditProfileSheet();
                  },
                ),
                _ProfileMenuTile(
                  icon: _isPublic
                      ? Icons.public_rounded
                      : Icons.lock_outline_rounded,
                  title: _isPublic
                      ? context.l('Public profile')
                      : context.l('Private profile'),
                  subtitle: _isPublic
                      ? context.l('Anyone can view your profile')
                      : context.l('Only accepted followers can view it'),
                  trailing: Switch.adaptive(
                    value: _isPublic,
                    activeThumbColor: AppColors.fernGreen,
                    activeTrackColor:
                        AppColors.fernGreen.withValues(alpha: 0.35),
                    onChanged: (value) {
                      setSheetState(() => _isPublic = value);
                      _setPublic(value);
                    },
                  ),
                ),
                _ProfileMenuTile(
                  icon: Icons.block_rounded,
                  title: context.l('Blocked users'),
                  subtitle: context.l('Review and unblock accounts'),
                  onTap: () {
                    Navigator.pop(sheetContext);
                    _showBlockedUsersSheet();
                  },
                ),
                _ProfileMenuTile(
                  icon: Icons.settings_outlined,
                  title: context.l('Settings'),
                  subtitle: context.l('Account, ads, privacy, and support'),
                  onTap: () {
                    Navigator.pop(sheetContext);
                    context.push('/settings');
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<List<Map<String, dynamic>>> _loadBlockedUsers() async {
    final client = Supabase.instance.client;
    final myId = client.auth.currentUser?.id;
    if (myId == null) return const [];

    final rows = await client
        .from('user_blocks')
        .select('blocked_id, created_at')
        .eq('blocker_id', myId)
        .order('created_at', ascending: false);

    final blockRows = List<Map<String, dynamic>>.from(rows as List);
    final ids = blockRows
        .map((row) => row['blocked_id'] as String?)
        .whereType<String>()
        .toList();
    if (ids.isEmpty) return const [];

    final users = await client
        .from('users_public')
        .select('id, username, display_name, avatar_url, trust_tier, is_pro')
        .filter('id', 'in', '(${ids.join(',')})');
    final userRows = List<Map<String, dynamic>>.from(users as List);
    final byId = {for (final user in userRows) user['id'] as String: user};

    return [
      for (final block in blockRows)
        if (byId[block['blocked_id']] != null)
          {
            ...byId[block['blocked_id']]!,
            'blocked_at': block['created_at'],
          },
    ];
  }

  DateTime? _parseDate(dynamic value) {
    if (value is String) return DateTime.tryParse(value);
    return null;
  }

  EchoStatus _parseStatus(String v) => switch (v) {
        'verified' => EchoStatus.verified,
        'disputed' => EchoStatus.disputed,
        'controversial' => EchoStatus.controversial,
        'active' => EchoStatus.active,
        'under_review' => EchoStatus.underReview,
        'hidden' => EchoStatus.hidden,
        'rejected' => EchoStatus.rejected,
        _ => EchoStatus.pendingVerification,
      };

  @override
  Widget build(BuildContext context) {
    final profileReady = !_isLoading && _profile != null;
    final swipeLocation = _isOwnProfile ? '/profile' : '/feed';
    final bottomNavLocation = _isOwnProfile
        ? '/profile'
        : '/profile/${Uri.encodeComponent(widget.username ?? '')}';

    return SwipeNavigationWrapper(
        currentLocation: swipeLocation,
        child: ExitConfirmWrapper(
            enabled: _isOwnProfile,
            child: Scaffold(
              backgroundColor: const Color(0xFFF5FAF7),
              appBar: AppBar(
                backgroundColor: Colors.white,
                elevation: 0,
                scrolledUnderElevation: 0.5,
                shadowColor: AppColors.borderSubtle,
                title: Text(
                  _profile != null
                      ? '@${_profile!['username']}'
                      : context.l('Profile'),
                  style: AppTypography.textTheme.titleLarge,
                ),
                actions: [
                  if (_isOwnProfile) ...[
                    IconButton(
                      icon: const Icon(Icons.edit_outlined, size: 20),
                      onPressed: profileReady ? _showEditProfileSheet : null,
                      color: profileReady
                          ? AppColors.charcoal
                          : AppColors.textTertiary,
                      disabledColor: AppColors.textTertiary,
                      tooltip: context.l('Edit profile'),
                    ),
                    IconButton(
                      icon: const Icon(Icons.more_horiz_rounded, size: 24),
                      onPressed: profileReady ? _showOwnProfileMenu : null,
                      color: profileReady
                          ? AppColors.charcoal
                          : AppColors.textTertiary,
                      disabledColor: AppColors.textTertiary,
                      tooltip: context.l('Profile menu'),
                    ),
                  ] else if (_profile != null) ...[
                    IconButton(
                      icon: Icon(
                        _isBlockedByMe
                            ? Icons.lock_open_rounded
                            : Icons.block_rounded,
                        size: 21,
                      ),
                      onPressed: _isBlockedByMe
                          ? () => _unblockProfileUser()
                          : _confirmBlockProfileUser,
                      color: _isBlockedByMe
                          ? AppColors.fernGreen
                          : AppColors.sunsetCoral,
                      tooltip: _isBlockedByMe
                          ? context.l('Unblock user')
                          : context.l('Block user'),
                    ),
                  ],
                  const SizedBox(width: 4),
                ],
              ),
              bottomNavigationBar:
                  AppBottomNav(currentLocation: bottomNavLocation),
              body: Stack(
                children: [
                  _isOwnProfile
                      ? _buildBody()
                      : kReleaseMode
                          ? SecureScreen(child: _buildBody())
                          : _buildBody(),
                  if (_isSavingProfile)
                    Positioned.fill(
                      child: AnimatedOpacity(
                        opacity: _isSavingProfile ? 1.0 : 0.0,
                        duration: const Duration(milliseconds: 200),
                        child: Container(
                          color: Colors.black.withValues(alpha: 0.25),
                          child: const Center(
                            child: CircularProgressIndicator(
                              color: AppColors.fernGreen,
                              strokeWidth: 2.5,
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            )));
  }
}

class _TabBarDelegate extends SliverPersistentHeaderDelegate {
  final TabBar tabBar;

  _TabBarDelegate(this.tabBar);

  @override
  double get minExtent => tabBar.preferredSize.height;

  @override
  double get maxExtent => tabBar.preferredSize.height;

  @override
  Widget build(
      BuildContext context, double shrinkOffset, bool overlapsContent) {
    return Container(
      color: Colors.white,
      child: tabBar,
    );
  }

  @override
  bool shouldRebuild(_TabBarDelegate oldDelegate) {
    return false;
  }
}

class _ProfileFollowButton extends StatelessWidget {
  const _ProfileFollowButton({
    required this.isFollowing,
    required this.requestStatus,
    required this.isPrivate,
    required this.onPressed,
  });

  final bool isFollowing;
  final String requestStatus;
  final bool isPrivate;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final isPending = requestStatus == 'pending';
    final label = isFollowing
        ? 'Following'
        : isPending
            ? 'Requested'
            : isPrivate
                ? 'Request follow'
                : 'Follow';
    final icon = isFollowing
        ? Icons.check_rounded
        : isPending
            ? Icons.hourglass_top_rounded
            : Icons.person_add_alt_1_rounded;
    final foreground = (isFollowing || isPending)
        ? AppColors.textSecondary
        : AppColors.fernGreen;
    final border = (isFollowing || isPending)
        ? AppColors.borderMedium
        : AppColors.fernGreen;
    final background =
        (isFollowing || isPending) ? AppColors.white : AppColors.fernGreenLight;

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 200),
      child: TextButton.icon(
        key: ValueKey('$isFollowing-$requestStatus-$isPrivate'),
        onPressed: onPressed,
        icon: Icon(icon, size: 16),
        label: Text(
          context.l(label),
          style: GoogleFonts.josefinSans(
            fontWeight: FontWeight.w600,
            fontSize: 13,
          ),
        ),
        style: TextButton.styleFrom(
          foregroundColor: foreground,
          side: BorderSide(color: border),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          minimumSize: const Size(double.infinity, 44),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          backgroundColor: background,
        ),
      ),
    );
  }
}

class _UnblockButton extends StatelessWidget {
  const _UnblockButton({required this.onPressed});
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.96, end: 1),
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutBack,
      builder: (context, value, child) =>
          Transform.scale(scale: value, child: child),
      child: TextButton.icon(
        onPressed: onPressed,
        icon: const Icon(Icons.lock_open_rounded, size: 16),
        label: Text(
          context.l('Unblock'),
          style: GoogleFonts.josefinSans(
            fontWeight: FontWeight.w700,
            fontSize: 13,
          ),
        ),
        style: TextButton.styleFrom(
          foregroundColor: AppColors.fernGreen,
          side: const BorderSide(color: AppColors.fernGreen),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          minimumSize: const Size(double.infinity, 44),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          backgroundColor: AppColors.fernGreenLight,
        ),
      ),
    );
  }
}

class _ProfileMenuTile extends StatelessWidget {
  const _ProfileMenuTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.onTap,
    this.trailing,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Material(
        color: AppColors.surfaceSecondary,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: AppColors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.borderSubtle),
                  ),
                  child: Icon(icon, size: 19, color: AppColors.charcoal),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: AppTypography.textTheme.titleSmall),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: AppTypography.textTheme.labelMedium,
                      ),
                    ],
                  ),
                ),
                trailing ??
                    const Icon(
                      Icons.chevron_right_rounded,
                      color: AppColors.textTertiary,
                    ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _BlockedProfileNotice extends StatelessWidget {
  const _BlockedProfileNotice({
    required this.username,
    required this.onUnblock,
  });

  final String username;
  final VoidCallback onUnblock;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
      builder: (context, value, child) => Opacity(
        opacity: value,
        child: Transform.translate(
          offset: Offset(0, (1 - value) * 10),
          child: child,
        ),
      ),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(AppSpacing.xl),
        decoration: BoxDecoration(
          color: AppColors.softSand,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.borderSubtle),
        ),
        child: Column(
          children: [
            const Icon(
              Icons.block_rounded,
              size: 40,
              color: AppColors.sunsetCoral,
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              context.l('You blocked @{username}', {'username': username}),
              style: AppTypography.textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 4),
            Text(
              context.l(
                'You cannot view their echoes, replies, followers, or interact until you unblock them.',
              ),
              style: AppTypography.textTheme.bodySmall
                  ?.copyWith(color: AppColors.textSecondary),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.md),
            _UnblockButton(onPressed: onUnblock),
          ],
        ),
      ),
    );
  }
}

class _BlockedUsersSheet extends StatefulWidget {
  const _BlockedUsersSheet({
    required this.loadBlockedUsers,
    required this.onUnblock,
  });

  final Future<List<Map<String, dynamic>>> Function() loadBlockedUsers;
  final Future<void> Function(String userId) onUnblock;

  @override
  State<_BlockedUsersSheet> createState() => _BlockedUsersSheetState();
}

class _BlockedUsersSheetState extends State<_BlockedUsersSheet> {
  late Future<List<Map<String, dynamic>>> _future;
  final Set<String> _unblocking = {};

  @override
  void initState() {
    super.initState();
    _future = widget.loadBlockedUsers();
  }

  void _reload() {
    setState(() => _future = widget.loadBlockedUsers());
  }

  Future<void> _unblock(String userId) async {
    if (_unblocking.contains(userId)) return;
    setState(() => _unblocking.add(userId));
    await widget.onUnblock(userId);
    if (!mounted) return;
    setState(() => _unblocking.remove(userId));
    _reload();
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.62,
      minChildSize: 0.38,
      maxChildSize: 0.92,
      builder: (context, controller) {
        return Column(
          children: [
            const SizedBox(height: AppSpacing.sm),
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.borderMedium,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.xl,
                AppSpacing.lg,
                AppSpacing.sm,
                AppSpacing.sm,
              ),
              child: Row(
                children: [
                  Text(context.l('Blocked users'),
                      style: AppTypography.textTheme.titleMedium),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close_rounded),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            Expanded(
              child: FutureBuilder<List<Map<String, dynamic>>>(
                future: _future,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppColors.fernGreen,
                      ),
                    );
                  }

                  final users = snapshot.data ?? const <Map<String, dynamic>>[];
                  if (users.isEmpty) {
                    return _ProfileEmptyTab(
                      icon: Icons.block_rounded,
                      title: context.l('No blocked users'),
                      message: context.l('Blocked accounts will appear here.'),
                    );
                  }

                  return ListView.separated(
                    controller: controller,
                    physics: const AlwaysScrollableScrollPhysics(),
                    itemCount: users.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final user = users[index];
                      final userId = user['id'] as String? ?? '';
                      final username = user['username'] as String? ?? 'unknown';
                      final displayName = (user['display_name'] as String?)
                                  ?.trim()
                                  .isNotEmpty ==
                              true
                          ? user['display_name'] as String
                          : username;
                      final avatarUrl = user['avatar_url'] as String?;
                      final isLoading = _unblocking.contains(userId);

                      return TweenAnimationBuilder<double>(
                        tween: Tween(begin: 0, end: 1),
                        duration: Duration(milliseconds: 180 + index * 25),
                        curve: Curves.easeOutCubic,
                        builder: (context, value, child) => Opacity(
                          opacity: value,
                          child: Transform.translate(
                            offset: Offset(0, (1 - value) * 8),
                            child: child,
                          ),
                        ),
                        child: ListTile(
                          leading: CircleAvatar(
                            backgroundColor: AppColors.softSand,
                            backgroundImage: avatarImageProvider(avatarUrl),
                            child: avatarImageProvider(avatarUrl) == null
                                ? const Icon(
                                    Icons.person_outline,
                                    color: AppColors.textTertiary,
                                  )
                                : null,
                          ),
                          title: Text(
                            displayName,
                            style: AppTypography.textTheme.titleSmall,
                          ),
                          subtitle: Text(
                            '@$username',
                            style: AppTypography.textTheme.labelMedium,
                          ),
                          trailing: TextButton(
                            onPressed: userId.isEmpty || isLoading
                                ? null
                                : () => _unblock(userId),
                            child: isLoading
                                ? const SizedBox(
                                    width: 14,
                                    height: 14,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: AppColors.fernGreen,
                                    ),
                                  )
                                : Text(context.l('Unblock')),
                          ),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }
}

class _AvatarCard extends StatelessWidget {
  const _AvatarCard({
    required this.profile,
    required this.isIdentityVerified,
    required this.isOwnProfile,
    required this.showStats,
    required this.onOpenFollowers,
    required this.onOpenFollowing,
    required this.onEditBio,
  });

  final Map<String, dynamic> profile;
  final bool isIdentityVerified;
  final bool isOwnProfile;
  final bool showStats;
  final VoidCallback onOpenFollowers;
  final VoidCallback onOpenFollowing;
  final VoidCallback onEditBio;

  @override
  Widget build(BuildContext context) {
    final avatarUrl = profile['avatar_url'] as String?;
    final username = profile['username'] as String? ?? '';
    final displayName = profile['display_name'] as String? ?? '';
    final bio = profile['bio'] as String?;
    final hasBio = bio != null && bio.isNotEmpty;
    final echoCount = (profile['echo_count'] as num?)?.toInt() ?? 0;
    final followerCount = (profile['follower_count'] as num?)?.toInt() ?? 0;
    final followingCount = (profile['following_count'] as num?)?.toInt() ?? 0;
    final heroTag = 'profile-avatar:${profile['id'] ?? username}';

    return Container(
      padding: const EdgeInsets.all(AppSpacing.xl),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.borderSubtle),
      ),
      child: Column(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              GestureDetector(
                onTap:
                    isOwnProfile || (avatarUrl != null && avatarUrl.isNotEmpty)
                        ? () => _showAvatarZoom(context, avatarUrl, heroTag)
                        : null,
                child: Hero(
                  tag: heroTag,
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      _ProfileAvatarWithBadge(
                        avatarUrl: avatarUrl,
                        isIdentityVerified: isIdentityVerified,
                        radius: 36,
                      ),
                      if (avatarUrl != null && avatarUrl.isNotEmpty)
                        Positioned(
                          right: -2,
                          top: -2,
                          child: Container(
                            width: 22,
                            height: 22,
                            decoration: BoxDecoration(
                              color: Colors.white,
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.08),
                                  blurRadius: 8,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),
                            child: const Icon(
                              Icons.zoom_in_rounded,
                              size: 14,
                              color: AppColors.charcoal,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (displayName.isNotEmpty) ...[
                      Text(
                        displayName,
                        style: AppTypography.textTheme.titleMedium,
                      ),
                      Text(
                        '@$username',
                        style: GoogleFonts.josefinSans(
                          fontSize: 13,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ] else
                      Text(
                        '@$username',
                        style: AppTypography.textTheme.titleMedium,
                      ),
                    if (hasBio) ...[
                      const SizedBox(height: 6),
                      Text(
                        bio,
                        style: GoogleFonts.josefinSans(
                          fontSize: 13,
                          color: AppColors.textSecondary,
                          height: 1.5,
                        ),
                      ),
                    ] else if (isOwnProfile) ...[
                      const SizedBox(height: 6),
                      Text(
                        context.l('No bio yet.'),
                        style: GoogleFonts.josefinSans(
                          fontSize: 13,
                          color: AppColors.textTertiary,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ],
                    if (isOwnProfile) ...[
                      const SizedBox(height: 10),
                      GestureDetector(
                        onTap: onEditBio,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.edit_outlined,
                              size: 13,
                              color: AppColors.fernGreen,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              hasBio
                                  ? context.l('Edit bio')
                                  : context.l('Add bio'),
                              style: GoogleFonts.josefinSans(
                                fontSize: 12,
                                color: AppColors.fernGreen,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          // Stats row: echoes | followers | following
          if (showStats)
            Row(
              children: [
                _StatItem(label: context.l('Echoes'), value: echoCount),
                _StatDivider(),
                _StatItem(
                  label: context.l('Followers'),
                  value: followerCount,
                  onTap: onOpenFollowers,
                ),
                _StatDivider(),
                _StatItem(
                  label: context.l('Following'),
                  value: followingCount,
                  onTap: onOpenFollowing,
                ),
              ],
            )
          else
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(AppSpacing.md),
              decoration: BoxDecoration(
                color: AppColors.softSand,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.borderSubtle),
              ),
              child: Text(
                context.l(
                  'Follow request required to view echoes, replies, followers, and following.',
                ),
                textAlign: TextAlign.center,
                style: AppTypography.textTheme.bodySmall
                    ?.copyWith(color: AppColors.textSecondary),
              ),
            ),
        ],
      ),
    );
  }

  static void _showAvatarZoom(
    BuildContext context,
    String? avatarUrl,
    String heroTag,
  ) {
    if (avatarUrl == null || avatarUrl.isEmpty) return;
    Navigator.of(context).push(
      PageRouteBuilder<void>(
        opaque: false,
        barrierColor: const Color(0xEEF5FAF7),
        barrierDismissible: true,
        pageBuilder: (_, __, ___) =>
            _AvatarZoomPage(avatarUrl: avatarUrl, heroTag: heroTag),
        transitionsBuilder: (_, animation, __, child) {
          final curved = CurvedAnimation(
            parent: animation,
            curve: Curves.easeOutCubic,
            reverseCurve: Curves.easeInCubic,
          );
          return FadeTransition(
            opacity: curved,
            child: ScaleTransition(
              scale: Tween<double>(begin: 0.96, end: 1).animate(curved),
              child: child,
            ),
          );
        },
        transitionDuration: const Duration(milliseconds: 260),
        reverseTransitionDuration: const Duration(milliseconds: 180),
      ),
    );
  }
}

class _AvatarZoomPage extends StatefulWidget {
  const _AvatarZoomPage({
    required this.avatarUrl,
    required this.heroTag,
  });

  final String avatarUrl;
  final String heroTag;

  @override
  State<_AvatarZoomPage> createState() => _AvatarZoomPageState();
}

class _AvatarZoomPageState extends State<_AvatarZoomPage> {
  final _controller = TransformationController();
  bool _zoomed = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _toggleZoom() {
    setState(() {
      _zoomed = !_zoomed;
      _controller.value =
          _zoomed ? Matrix4.diagonal3Values(2.35, 2.35, 1) : Matrix4.identity();
    });
  }

  void _resetZoom() {
    setState(() {
      _zoomed = false;
      _controller.value = Matrix4.identity();
    });
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final avatarSize = (size.width * 0.78).clamp(220.0, 360.0).toDouble();

    return Scaffold(
      backgroundColor: const Color(0xFFF5FAF7),
      body: Stack(
        children: [
          Center(
            child: GestureDetector(
              onDoubleTap: _toggleZoom,
              child: InteractiveViewer(
                transformationController: _controller,
                minScale: 1,
                maxScale: 4,
                boundaryMargin: const EdgeInsets.all(120),
                panEnabled: true,
                scaleEnabled: true,
                clipBehavior: Clip.none,
                child: Hero(
                  tag: widget.heroTag,
                  child: Container(
                    width: avatarSize,
                    height: avatarSize,
                    padding: const EdgeInsets.all(5),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: const LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          AppColors.fernGreen,
                          AppColors.fernGreenDark,
                        ],
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.fernGreen.withValues(alpha: 0.18),
                          blurRadius: 30,
                          offset: const Offset(0, 12),
                        ),
                      ],
                    ),
                    child: SizedBox(
                      width: avatarSize,
                      height: avatarSize,
                      child: ClipOval(
                        child: ColoredBox(
                          color: AppColors.softSand,
                          child: widget.avatarUrl.endsWith('.svg')
                              ? SvgPicture.network(
                                  widget.avatarUrl,
                                  fit: BoxFit.cover,
                                )
                              : Image.network(
                                  widget.avatarUrl,
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, __, ___) => Container(
                                    color: AppColors.softSand,
                                    child: const Icon(
                                      Icons.person_outline,
                                      color: AppColors.textTertiary,
                                      size: 72,
                                    ),
                                  ),
                                ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          SafeArea(
            child: Align(
              alignment: Alignment.bottomCenter,
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.lg),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(22),
                    border: Border.all(
                      color: AppColors.borderSubtle,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.08),
                        blurRadius: 20,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.sm,
                      vertical: AppSpacing.xs,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          onPressed: _toggleZoom,
                          icon: Icon(
                            _zoomed
                                ? Icons.zoom_out_map_rounded
                                : Icons.zoom_in_rounded,
                          ),
                          color: AppColors.charcoal,
                          tooltip: _zoomed
                              ? context.l('Reset zoom')
                              : context.l('Zoom in'),
                        ),
                        const SizedBox(width: AppSpacing.xs),
                        IconButton(
                          onPressed: _resetZoom,
                          icon: const Icon(Icons.center_focus_strong_rounded),
                          color: AppColors.charcoal,
                          tooltip: context.l('Center image'),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          SafeArea(
            child: Align(
              alignment: Alignment.topRight,
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.lg),
                child: IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close_rounded),
                  color: AppColors.charcoal,
                  style: IconButton.styleFrom(
                    backgroundColor: Colors.white,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatItem extends StatelessWidget {
  const _StatItem({required this.label, required this.value, this.onTap});
  final String label;
  final int value;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Column(
            children: [
              Text(
                _format(value),
                style: GoogleFonts.josefinSans(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: AppColors.charcoal,
                ),
              ),
              Text(
                label,
                style: GoogleFonts.josefinSans(
                  fontSize: 11,
                  color: AppColors.textTertiary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _format(int n) {
    if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(1)}M';
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)}K';
    return '$n';
  }
}

class _StatDivider extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1,
      height: 32,
      color: AppColors.borderSubtle,
    );
  }
}

class _ProfileAvatarWithBadge extends StatefulWidget {
  const _ProfileAvatarWithBadge({
    required this.avatarUrl,
    required this.isIdentityVerified,
    required this.radius,
  });

  final String? avatarUrl;
  final bool isIdentityVerified;
  final double radius;

  @override
  State<_ProfileAvatarWithBadge> createState() =>
      _ProfileAvatarWithBadgeState();
}

class _ProfileAvatarWithBadgeState extends State<_ProfileAvatarWithBadge>
    with SingleTickerProviderStateMixin {
  late final AnimationController _badgeCtrl;
  late final Animation<double> _badgeScale;

  @override
  void initState() {
    super.initState();
    _badgeCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _badgeScale = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _badgeCtrl, curve: Curves.easeOutBack),
    );
    if (widget.isIdentityVerified) {
      // Small delay so it pops in after the avatar loads.
      Future.delayed(const Duration(milliseconds: 300), () {
        if (mounted) _badgeCtrl.forward();
      });
    }
  }

  @override
  void didUpdateWidget(_ProfileAvatarWithBadge old) {
    super.didUpdateWidget(old);
    if (!old.isIdentityVerified && widget.isIdentityVerified) {
      _badgeCtrl.forward();
    }
  }

  @override
  void dispose() {
    _badgeCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final diameter = widget.radius * 2;
    // Ring thickness: 2.5px for profile (larger avatar).
    const ringWidth = 2.5;
    // Total container size = diameter + ring on each side + gap.
    final containerSize = diameter + (ringWidth + 2) * 2;

    return SizedBox(
      width: containerSize,
      height: containerSize,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // Animated verified ring.
          if (widget.isIdentityVerified)
            ScaleTransition(
              scale: _badgeScale,
              child: Container(
                width: containerSize,
                height: containerSize,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: const LinearGradient(
                    colors: [AppColors.fernGreen, AppColors.fernGreenDark],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
              ),
            ),

          // Avatar, inset from the ring.
          Positioned(
            left: widget.isIdentityVerified ? ringWidth + 2 : 0,
            top: widget.isIdentityVerified ? ringWidth + 2 : 0,
            child: CircleAvatar(
              radius: widget.radius,
              backgroundColor: AppColors.softSand,
              child: ClipOval(
                child:
                    (widget.avatarUrl != null && widget.avatarUrl!.isNotEmpty)
                        ? widget.avatarUrl!.endsWith('.svg')
                            ? SvgPicture.network(
                                widget.avatarUrl!,
                                width: diameter,
                                height: diameter,
                                fit: BoxFit.cover,
                                placeholderBuilder: (_) => const Icon(
                                  Icons.person_outline,
                                  size: 28,
                                  color: AppColors.textTertiary,
                                ),
                              )
                            : Image.network(
                                widget.avatarUrl!,
                                width: diameter,
                                height: diameter,
                                fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) => Icon(
                                  Icons.person_outline,
                                  size: widget.radius * 0.77,
                                  color: AppColors.textTertiary,
                                ),
                              )
                        : Icon(
                            Icons.person_outline,
                            size: widget.radius * 0.77,
                            color: AppColors.textTertiary,
                          ),
              ),
            ),
          ),

          // Verified checkmark dot — animated pop-in.
          if (widget.isIdentityVerified)
            Positioned(
              right: 2,
              bottom: 2,
              child: ScaleTransition(
                scale: _badgeScale,
                child: Container(
                  width: 22,
                  height: 22,
                  decoration: const BoxDecoration(
                    color: AppColors.fernGreen,
                    shape: BoxShape.circle,
                    // White border separates the dot from the ring.
                  ),
                  child: const Icon(
                    Icons.verified_rounded,
                    size: 14,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _VisibilityToggle extends StatelessWidget {
  const _VisibilityToggle({
    required this.isPublic,
    required this.onToggle,
  });
  final bool isPublic;
  final void Function(bool) onToggle;

  @override
  Widget build(BuildContext context) {
    final color = isPublic ? AppColors.fernGreenDark : const Color(0xFFE65100);

    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.md),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: isPublic ? AppColors.fernGreenLight : const Color(0xFFFFF3E0),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isPublic
              ? AppColors.fernGreen.withValues(alpha: 0.3)
              : const Color(0xFFFFB74D).withValues(alpha: 0.4),
        ),
      ),
      child: Row(
        children: [
          Icon(
            isPublic ? Icons.public_rounded : Icons.lock_outline_rounded,
            size: 16,
            color: color,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isPublic
                      ? context.l('Public profile')
                      : context.l('Private profile'),
                  style: GoogleFonts.josefinSans(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: color,
                  ),
                ),
                Text(
                  isPublic
                      ? context.l('Anyone can see your echoes')
                      : context.l('Only you can see your echoes'),
                  style: GoogleFonts.josefinSans(
                    fontSize: 11,
                    color: color,
                  ),
                ),
              ],
            ),
          ),
          Switch.adaptive(
            value: isPublic,
            onChanged: onToggle,
            activeThumbColor: AppColors.fernGreen,
            activeTrackColor: AppColors.fernGreen.withValues(alpha: 0.35),
          ),
        ],
      ),
    );
  }
}

class _PrivateProfileNotice extends StatelessWidget {
  const _PrivateProfileNotice({
    required this.username,
    required this.requestStatus,
  });
  final String username;
  final String requestStatus;

  @override
  Widget build(BuildContext context) {
    final statusText = requestStatus == 'pending'
        ? context.l('Your follow request is pending.')
        : context.l(
            'Send a follow request to view their echoes and social graph.',
          );

    return Container(
      padding: const EdgeInsets.all(AppSpacing.xl),
      decoration: BoxDecoration(
        color: AppColors.softSand,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.borderSubtle),
      ),
      child: Column(
        children: [
          const Icon(
            Icons.lock_outline_rounded,
            size: 40,
            color: AppColors.textTertiary,
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            context.l('This account is private'),
            style: AppTypography.textTheme.titleMedium,
          ),
          const SizedBox(height: 4),
          Text(
            context.l(
              '@{username} has set their profile to private.',
              {'username': username},
            ),
            style: AppTypography.textTheme.bodySmall,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            statusText,
            style: AppTypography.textTheme.labelMedium
                ?.copyWith(color: AppColors.textSecondary),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class _VerifyPrompt extends StatelessWidget {
  const _VerifyPrompt({this.isPending = false});
  final bool isPending;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: isPending ? null : () => context.push('/settings'),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: isPending ? const Color(0xFFFFF8E1) : AppColors.fernGreenLight,
          borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
          border: Border.all(
            color: isPending
                ? AppColors.statusControversial.withValues(alpha: 0.4)
                : AppColors.fernGreen.withValues(alpha: 0.3),
          ),
        ),
        child: Row(
          children: [
            Icon(
              isPending ? Icons.pending_outlined : Icons.shield_outlined,
              size: 18,
              color: isPending
                  ? AppColors.statusControversial
                  : AppColors.fernGreen,
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text(
                isPending
                    ? context.l(
                        'Verification in progress — usually takes a few minutes',
                      )
                    : context.l(
                        'Verify your identity to increase your trust weight',
                      ),
                style: GoogleFonts.josefinSans(
                  fontSize: 13,
                  color: isPending
                      ? const Color(0xFF7A5200)
                      : AppColors.fernGreenDark,
                ),
              ),
            ),
            if (!isPending)
              const Icon(Icons.chevron_right,
                  size: 16, color: AppColors.fernGreen),
          ],
        ),
      ),
    );
  }
}

// add these at the bottom of profile_screen.dart
// outside _ProfileScreenState, as top-level widget classes

class _EchoesTab extends StatelessWidget {
  const _EchoesTab({required this.echoes});
  final List<EchoEntity> echoes;

  @override
  Widget build(BuildContext context) {
    if (echoes.isEmpty) {
      return _ProfileEmptyTab(
        icon: Icons.record_voice_over_outlined,
        title: context.l('No echoes yet.'),
        message: context.l('Published echoes will appear here.'),
      );
    }

    return ListView.builder(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.only(top: 8, bottom: 80),
      itemCount: echoes.length,
      itemBuilder: (ctx, i) => Padding(
        padding: const EdgeInsets.only(bottom: AppSpacing.sm),
        child: EchoCard(
          echo: echoes[i],
          onTap: () => ctx.push('/feed/echo/${echoes[i].id}'),
        ),
      ),
    );
  }
}

class _RepliesTab extends StatefulWidget {
  const _RepliesTab({required this.userId});
  final String userId;

  @override
  State<_RepliesTab> createState() => _RepliesTabState();
}

class _RepliesTabState extends State<_RepliesTab>
    with AutomaticKeepAliveClientMixin {
  List<Map<String, dynamic>> _replies = [];
  bool _isLoading = true;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final client = Supabase.instance.client;
      final rows = await client
          .from('echo_replies')
          .select('id, content, created_at, '
              'echoes!inner(id, title), '
              'users_public!inner(username, avatar_url)')
          .eq('user_id', widget.userId)
          .order('created_at', ascending: false)
          .limit(30);

      setState(() {
        _replies = List<Map<String, dynamic>>.from(rows as List);
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(
            strokeWidth: 2, color: AppColors.fernGreen),
      );
    }

    if (_replies.isEmpty) {
      return _ProfileEmptyTab(
        icon: Icons.chat_bubble_outline_rounded,
        title: context.l('No replies yet.'),
        message: context.l('Replies to other echoes will appear here.'),
      );
    }

    return ListView.builder(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.only(top: 8, bottom: 80),
      itemCount: _replies.length,
      itemBuilder: (ctx, i) {
        final r = _replies[i];
        final echo = r['echoes'] as Map<String, dynamic>? ?? {};
        final content = r['content'] as String? ?? '';
        final created = DateTime.tryParse(r['created_at'] as String? ?? '') ??
            DateTime.now();
        final echoTitle = echo['title'] as String? ?? 'Echo';
        final echoId = echo['id'] as String? ?? '';

        return GestureDetector(
          onTap: () => ctx.push('/feed/echo/$echoId'),
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.borderSubtle),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // context — which echo this is a reply to
                Row(
                  children: [
                    const Icon(Icons.reply_rounded,
                        size: 12, color: AppColors.textTertiary),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        context.l('Replying to "{title}"', {
                          'title': echoTitle,
                        }),
                        style: GoogleFonts.josefinSans(
                          fontSize: 11,
                          color: AppColors.textTertiary,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                RichTextDisplay(
                  text: content,
                  style: AppTypography.textTheme.bodyMedium,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Text(
                  Formatters.timeAgo(created),
                  style: AppTypography.textTheme.labelMedium,
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _ProfileEmptyTab extends StatelessWidget {
  const _ProfileEmptyTab({
    required this.icon,
    required this.title,
    required this.message,
  });

  final IconData icon;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return CustomScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      slivers: [
        SliverFillRemaining(
          hasScrollBody: false,
          child: SafeArea(
            top: false,
            minimum: const EdgeInsets.only(bottom: 96),
            child: Center(
              child: TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: 1),
                duration: const Duration(milliseconds: 320),
                curve: Curves.easeOutCubic,
                builder: (context, value, child) {
                  return Opacity(
                    opacity: value,
                    child: Transform.translate(
                      offset: Offset(0, (1 - value) * 12),
                      child: Transform.scale(
                        scale: 0.97 + (value * 0.03),
                        child: child,
                      ),
                    ),
                  );
                },
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.xxl),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 68,
                        height: 68,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color:
                              AppColors.fernGreenLight.withValues(alpha: 0.7),
                          border: Border.all(
                            color: AppColors.fernGreen.withValues(alpha: 0.16),
                          ),
                        ),
                        child: Icon(
                          icon,
                          size: 32,
                          color: AppColors.fernGreen,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.md),
                      Text(
                        context.l(title),
                        textAlign: TextAlign.center,
                        style: AppTypography.textTheme.titleSmall,
                      ),
                      const SizedBox(height: 6),
                      Text(
                        context.l(message),
                        textAlign: TextAlign.center,
                        style: AppTypography.textTheme.bodySmall
                            ?.copyWith(color: AppColors.textTertiary),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _LockedProfileTab extends StatelessWidget {
  const _LockedProfileTab({required this.username});
  final String username;

  @override
  Widget build(BuildContext context) {
    return CustomScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      slivers: [
        SliverFillRemaining(
          hasScrollBody: false,
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.xxl),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 68,
                    height: 68,
                    decoration: BoxDecoration(
                      color: AppColors.softSand,
                      shape: BoxShape.circle,
                      border: Border.all(color: AppColors.borderSubtle),
                    ),
                    child: const Icon(
                      Icons.lock_outline_rounded,
                      size: 32,
                      color: AppColors.textTertiary,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Text(
                    context.l('@{username} is private', {
                      'username': username,
                    }),
                    style: AppTypography.textTheme.titleSmall,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    context.l(
                      'Accepted followers can view echoes, replies, media, followers, and following.',
                    ),
                    style: AppTypography.textTheme.bodySmall
                        ?.copyWith(color: AppColors.textSecondary),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _MediaTab extends StatefulWidget {
  const _MediaTab({required this.userId});
  final String userId;

  @override
  State<_MediaTab> createState() => _MediaTabState();
}

class _MediaTabState extends State<_MediaTab>
    with AutomaticKeepAliveClientMixin {
  List<Map<String, dynamic>> _mediaEchoes = [];
  bool _isLoading = true;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final client = Supabase.instance.client;
      // echoes that have media_urls array — not empty
      final rows = await client
          .from('echoes')
          .select('id, title, media_urls, created_at')
          .eq('user_id', widget.userId)
          .not('media_urls', 'eq', '{}')
          .not('status', 'in', '("hidden","rejected")')
          .order('created_at', ascending: false)
          .limit(30);

      setState(() {
        _mediaEchoes = List<Map<String, dynamic>>.from(rows as List);
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(
            strokeWidth: 2, color: AppColors.fernGreen),
      );
    }

    if (_mediaEchoes.isEmpty) {
      return _ProfileEmptyTab(
        icon: Icons.photo_library_outlined,
        title: context.l('No media yet.'),
        message: context.l('Echoes with photos or videos will appear here.'),
      );
    }

    // Twitter-style 3-column grid
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(2, 2, 2, 96),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 2,
        mainAxisSpacing: 2,
      ),
      itemCount: _mediaEchoes.length,
      itemBuilder: (ctx, i) {
        final e = _mediaEchoes[i];
        final echoId = e['id'] as String;
        final urls = (e['media_urls'] as List?)?.cast<String>() ?? [];
        final firstUrl = urls.isNotEmpty ? urls.first : '';

        return GestureDetector(
          onTap: () => ctx.push('/feed/echo/$echoId'),
          child: firstUrl.isNotEmpty
              ? Image.network(
                  firstUrl,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Container(
                    color: AppColors.softSand,
                    child: const Icon(Icons.broken_image_outlined,
                        color: AppColors.textTertiary),
                  ),
                )
              : Container(
                  color: AppColors.softSand,
                  child: const Icon(Icons.image_outlined,
                      color: AppColors.textTertiary),
                ),
        );
      },
    );
  }
}

class _FollowUsersTab extends StatefulWidget {
  const _FollowUsersTab({
    required this.mode,
    required this.loadUsers,
  });

  final String mode;
  final Future<List<Map<String, dynamic>>> Function() loadUsers;

  @override
  State<_FollowUsersTab> createState() => _FollowUsersTabState();
}

class _FollowUsersTabState extends State<_FollowUsersTab>
    with AutomaticKeepAliveClientMixin {
  late Future<List<Map<String, dynamic>>> _future;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _future = widget.loadUsers();
  }

  Future<void> _refresh() async {
    setState(() => _future = widget.loadUsers());
    await _future;
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final title = widget.mode == 'followers'
        ? context.l('No followers yet.')
        : context.l('Not following anyone yet.');
    final message = widget.mode == 'followers'
        ? context.l('Accepted followers will appear here.')
        : context.l('Accounts this profile follows will appear here.');

    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _future,
      builder: (context, snapshot) {
        final users = snapshot.data ?? const <Map<String, dynamic>>[];
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: AppColors.fernGreen,
            ),
          );
        }
        if (users.isEmpty) {
          return RefreshIndicator(
            color: AppColors.fernGreen,
            onRefresh: _refresh,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              children: [
                SizedBox(
                  height: MediaQuery.sizeOf(context).height * 0.45,
                  child: _ProfileEmptyTab(
                    icon: Icons.people_alt_outlined,
                    title: title,
                    message: message,
                  ),
                ),
              ],
            ),
          );
        }
        return RefreshIndicator(
          color: AppColors.fernGreen,
          onRefresh: _refresh,
          child: ListView.separated(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              AppSpacing.md,
              AppSpacing.lg,
              96,
            ),
            itemCount: users.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final user = users[index];
              final username = user['username'] as String? ?? '';
              final displayName =
                  (user['display_name'] as String?)?.trim().isNotEmpty == true
                      ? user['display_name'] as String
                      : username;
              final avatarUrl = user['avatar_url'] as String?;
              return ListTile(
                contentPadding: EdgeInsets.zero,
                leading: CircleAvatar(
                  backgroundColor: AppColors.softSand,
                  backgroundImage: avatarImageProvider(avatarUrl),
                  child: avatarImageProvider(avatarUrl) == null
                      ? const Icon(
                          Icons.person_outline,
                          color: AppColors.textTertiary,
                        )
                      : null,
                ),
                title: Text(
                  displayName,
                  style: AppTypography.textTheme.titleSmall,
                ),
                subtitle: Text('@$username'),
                trailing: const Icon(
                  Icons.chevron_right_rounded,
                  color: AppColors.textTertiary,
                ),
                onTap: username.isEmpty
                    ? null
                    : () => context.push(
                          '/profile/${Uri.encodeComponent(username)}',
                        ),
              );
            },
          ),
        );
      },
    );
  }
}
