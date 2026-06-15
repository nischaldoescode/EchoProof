// profile screen
// @params username opens a public profile when present

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide StorageException;
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
import 'package:flutter/foundation.dart';
import '../../../../core/security/secure_screen.dart';
import '../../../../shared/widgets/app_bottom_nav.dart';
import '../../../../shared/widgets/avatar_image_provider.dart';
import '../../../../shared/widgets/rich_text_display.dart';
import '../../../../shared/widgets/image_viewer.dart';
import '../../../../shared/widgets/top_flow_loader.dart';
import '../../../../shared/widgets/verified_badges.dart';
import '../../../../app/app.dart';
import 'package:flutter/services.dart';
import '../../../../core/utils/snack.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'dart:async';
import 'dart:ui' as ui;
import '../../../../core/utils/sanitizer.dart';
import '../../../../core/utils/media_file_safety.dart';
import '../../../../core/services/storage_service.dart';
import '../widgets/profile_banner_crop_editor.dart';
import 'package:url_launcher/url_launcher.dart';

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
  bool _isIdentityVerified = false;
  bool _isPublic = true;
  bool _isOwnProfile = true;
  bool _isLoading = true;
  bool _isVerificationPending = false;
  bool userIsPro = false;
  bool _isFollowing = false;
  bool _isBlockedByMe = false;
  bool _profileUnavailable = false;
  String _followRequestStatus = 'none';
  Timer? _debounce;
  bool _isSavingBanner = false;
  TabController? _profileTabController;
  final ScrollController _profileOuterScrollController = ScrollController();
  final ValueNotifier<bool> _repliesTabIsEmpty = ValueNotifier<bool>(true);
  final ValueNotifier<bool> _mediaTabIsEmpty = ValueNotifier<bool>(true);
  bool _repliesTabLoaded = false;
  bool _mediaTabLoaded = false;
  int _lastProfileTabIndex = 0;
  final Set<int> _visitedProfileTabs = <int>{0};

  late final AnimationController _entranceCtrl;
  late final Animation<double> _fade;
  late final Animation<Offset> _slide;

  @override
  void initState() {
    super.initState();
    _isOwnProfile = widget.username == null;
    // pro users get analytics when viewing their own profile
    _entranceCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _fade = Tween<double>(
      begin: 0,
      end: 1,
    ).animate(CurvedAnimation(parent: _entranceCtrl, curve: Curves.easeOut));
    _slide = Tween<Offset>(
      begin: const Offset(0, 0.05),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _entranceCtrl, curve: Curves.easeOut));

    _loadProfile();
  }

  @override
  void dispose() {
    _entranceCtrl.dispose();
    _profileTabController?.removeListener(_handleProfileTabChange);
    _profileTabController?.dispose();
    _profileOuterScrollController.dispose();
    _repliesTabIsEmpty.dispose();
    _mediaTabIsEmpty.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  TabController _ensureProfileTabController(int length) {
    final current = _profileTabController;
    if (current != null && current.length == length) return current;

    final previousIndex = current?.index ?? 0;
    current?.removeListener(_handleProfileTabChange);
    current?.dispose();
    _lastProfileTabIndex = previousIndex.clamp(0, length - 1);
    _profileTabController = TabController(
      length: length,
      vsync: this,
      initialIndex: _lastProfileTabIndex,
    )..addListener(_handleProfileTabChange);
    _visitedProfileTabs.add(_lastProfileTabIndex);
    return _profileTabController!;
  }

  void _handleProfileTabChange() {
    final controller = _profileTabController;
    if (!mounted || controller == null) return;
    if (_lastProfileTabIndex == controller.index) return;

    // tab animations can notify more than once per tap
    // rebuild only when the selected tab changes so scroll state stays calm
    _lastProfileTabIndex = controller.index;
    _visitedProfileTabs.add(controller.index);
    setState(() {});
  }

  void _setRepliesTabEmpty(bool empty) {
    final changed = !_repliesTabLoaded || _repliesTabIsEmpty.value != empty;
    _repliesTabLoaded = true;
    _repliesTabIsEmpty.value = empty;
    if (changed && mounted) setState(() {});
  }

  void _setMediaTabEmpty(bool empty) {
    final changed = !_mediaTabLoaded || _mediaTabIsEmpty.value != empty;
    _mediaTabLoaded = true;
    _mediaTabIsEmpty.value = empty;
    if (changed && mounted) setState(() {});
  }

  bool _isSavingProfile = false;

  bool get _canViewProfileContent =>
      _isOwnProfile ||
      (!_isBlockedByMe && !_profileUnavailable && (_isPublic || _isFollowing));

  bool get _canOpenFollowLists =>
      _isOwnProfile || (!_isBlockedByMe && !_profileUnavailable && _isPublic);

  // opens the edit profile bottom sheet
  // covers display name username gender and dob
  Future<void> _showEditProfileSheet() async {
    if (_isLoading || _profile == null || _isSavingProfile) return;

    final client = Supabase.instance.client;
    final currentUsername = _profile?['username'] as String? ?? '';
    final currentDisplay = _profile?['display_name'] as String? ?? '';
    final currentBio = _profile?['bio'] as String? ?? '';
    final currentGender = _profile?['gender'] as String?;
    final currentWebsite = _profile?['website_url'] as String? ?? '';
    var showBirthdatePublic =
        _profile?['show_birthdate_public'] as bool? ?? false;

    // parse stored dob from postgres yyyy-mm-dd
    DateTime? currentDob;
    final dobRaw = _profile?['date_of_birth'] as String?;
    if (dobRaw != null) {
      currentDob = DateTime.tryParse(dobRaw);
    }

    final usernameCtrl = TextEditingController(text: currentUsername);
    final displayCtrl = TextEditingController(text: currentDisplay);
    final bioCtrl = TextEditingController(text: currentBio);
    final websiteCtrl = TextEditingController(text: currentWebsite);
    bool usernameAvailable = true;
    bool isCheckingUsername = false;
    String? usernameError;
    String? selectedGender = currentGender;
    DateTime? selectedDob = currentDob;

    bool sameDate(DateTime? a, DateTime? b) {
      if (a == null || b == null) return a == b;
      return a.year == b.year && a.month == b.month && a.day == b.day;
    }

    bool hasPendingProfileChanges() {
      return usernameCtrl.text.trim().toLowerCase() != currentUsername ||
          displayCtrl.text.trim() != currentDisplay ||
          bioCtrl.text.trim() != currentBio ||
          websiteCtrl.text.trim() != currentWebsite ||
          selectedGender != currentGender ||
          !sameDate(selectedDob, currentDob) ||
          showBirthdatePublic !=
              (_profile?['show_birthdate_public'] as bool? ?? false);
    }

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
        icon: Icons.transgender_rounded,
      ),
      (
        value: 'prefer_not_to_say',
        label: 'Prefer not to say',
        icon: Icons.person_outline_rounded,
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
            final birthdateTint = showBirthdatePublic
                ? AppColors.fernGreenDark
                : AppColors.charcoal.withValues(alpha: 0.72);
            final birthdateSurface = showBirthdatePublic
                ? AppColors.fernGreenLight.withValues(alpha: 0.45)
                : AppColors.softSand.withValues(alpha: 0.88);
            final birthdateBorder = showBirthdatePublic
                ? AppColors.fernGreen.withValues(alpha: 0.16)
                : AppColors.borderMedium;
            final canSave =
                hasPendingProfileChanges() &&
                usernameAvailable &&
                !isCheckingUsername;

            return SingleChildScrollView(
              padding: EdgeInsets.only(
                bottom:
                    MediaQuery.viewInsetsOf(ctx).bottom +
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
                    onChanged: (_) => setSheet(() {}),
                    buildCounter:
                        (
                          _, {
                          required currentLength,
                          required isFocused,
                          maxLength,
                        }) => null,
                    style: AppTypography.textTheme.bodyMedium,
                    decoration: InputDecoration(
                      hintText: context.l('Your display name'),
                      filled: true,
                      fillColor: AppColors.softSand,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                      enabledBorder: OutlineInputBorder(
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
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 12,
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),

                  // bio
                  Text(
                    context.l('Bio'),
                    style: GoogleFonts.josefinSans(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  TextField(
                    controller: bioCtrl,
                    maxLength: 160,
                    maxLines: 3,
                    onChanged: (_) => setSheet(() {}),
                    buildCounter:
                        (
                          _, {
                          required currentLength,
                          required isFocused,
                          maxLength,
                        }) => null,
                    style: AppTypography.textTheme.bodyMedium,
                    decoration: InputDecoration(
                      hintText: context.l('A short line about you'),
                      filled: true,
                      fillColor: AppColors.softSand,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                      enabledBorder: OutlineInputBorder(
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
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 12,
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.lg),

                  // website
                  Text(
                    context.l('Website'),
                    style: GoogleFonts.josefinSans(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  TextField(
                    controller: websiteCtrl,
                    keyboardType: TextInputType.url,
                    autocorrect: false,
                    maxLength: 120,
                    onChanged: (_) => setSheet(() {}),
                    buildCounter:
                        (
                          _, {
                          required currentLength,
                          required isFocused,
                          maxLength,
                        }) => null,
                    style: AppTypography.textTheme.bodyMedium,
                    decoration: InputDecoration(
                      hintText: context.l('https://your.site'),
                      filled: true,
                      fillColor: AppColors.softSand,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                      enabledBorder: OutlineInputBorder(
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
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 12,
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.lg),

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
                    buildCounter:
                        (
                          _, {
                          required currentLength,
                          required isFocused,
                          maxLength,
                        }) => null,
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
                          ? const Icon(
                              Icons.check_circle_rounded,
                              size: 18,
                              color: AppColors.fernGreen,
                            )
                          : null,
                      filled: true,
                      fillColor: AppColors.softSand,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                      enabledBorder: OutlineInputBorder(
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
                      errorBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(
                          color: AppColors.sunsetCoral,
                        ),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 12,
                      ),
                    ),
                    onChanged: (v) {
                      _debounce?.cancel();

                      setSheet(() {
                        isCheckingUsername = true;
                        usernameError = null;
                      });

                      _debounce = Timer(
                        const Duration(milliseconds: 400),
                        () async {
                          if (!ctx.mounted) return;

                          if (v.length < 3) {
                            setSheet(() {
                              isCheckingUsername = false;
                              usernameAvailable = false;
                              usernameError = context.l(
                                'At least 3 characters',
                              );
                            });
                            return;
                          }

                          final available = await checkUsernameAvailability(
                            v.toLowerCase(),
                          );

                          if (!ctx.mounted) return;

                          setSheet(() {
                            isCheckingUsername = false;
                            usernameAvailable = available;
                            usernameError = available
                                ? null
                                : context.l('Username already taken');
                          });
                        },
                      );
                    },
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  // birth date privacy stays close to identity fields
                  Container(
                    padding: const EdgeInsets.all(AppSpacing.md),
                    decoration: BoxDecoration(
                      color: birthdateSurface,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: birthdateBorder),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          showBirthdatePublic
                              ? Icons.visibility_outlined
                              : Icons.visibility_off_outlined,
                          size: 18,
                          color: birthdateTint,
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                context.l('Show birth date'),
                                style: GoogleFonts.josefinSans(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w800,
                                  color: birthdateTint,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                context.l(
                                  'Only the month and day are shown publicly.',
                                ),
                                style: GoogleFonts.josefinSans(
                                  fontSize: 12,
                                  color: showBirthdatePublic
                                      ? AppColors.textSecondary
                                      : AppColors.textTertiary,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 180),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 9,
                            vertical: 5,
                          ),
                          decoration: BoxDecoration(
                            color: showBirthdatePublic
                                ? AppColors.fernGreen.withValues(alpha: 0.12)
                                : AppColors.white.withValues(alpha: 0.86),
                            borderRadius: BorderRadius.circular(
                              AppSpacing.radiusFull,
                            ),
                            border: Border.all(
                              color: showBirthdatePublic
                                  ? AppColors.fernGreen.withValues(alpha: 0.22)
                                  : AppColors.borderSubtle,
                            ),
                          ),
                          child: Text(
                            context.l(
                              showBirthdatePublic ? 'Public' : 'Hidden',
                            ),
                            style: GoogleFonts.josefinSans(
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                              color: showBirthdatePublic
                                  ? AppColors.fernGreenDark
                                  : AppColors.textSecondary,
                            ),
                          ),
                        ),
                        Switch.adaptive(
                          value: showBirthdatePublic,
                          // keep switch contrast independent from the surrounding card tint
                          // pale green tracks disappeared on some android skins when enabled
                          activeThumbColor: AppColors.white,
                          activeTrackColor: AppColors.fernGreen,
                          inactiveThumbColor: AppColors.white,
                          inactiveTrackColor: AppColors.textTertiary,
                          onChanged: (value) {
                            HapticFeedback.selectionClick();
                            setSheet(() => showBirthdatePublic = value);
                          },
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: AppSpacing.lg),

                  // date of birth requires otp to change
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
                        initialDate:
                            selectedDob ??
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
                                  fontWeight: FontWeight.w600,
                                ),
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
                        horizontal: 14,
                        vertical: 14,
                      ),
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
                                    fontWeight: sel
                                        ? FontWeight.w600
                                        : FontWeight.w400,
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
                      onPressed: canSave
                          ? () async {
                              Navigator.pop(ctx);
                              await _saveProfileChanges(
                                newUsername: usernameCtrl.text
                                    .trim()
                                    .toLowerCase(),
                                newDisplayName: displayCtrl.text.trim(),
                                currentUsername: currentUsername,
                                newBio: bioCtrl.text.trim(),
                                newWebsite: websiteCtrl.text.trim(),
                                newGender:
                                    selectedGender ?? 'prefer_not_to_say',
                                newDob: selectedDob,
                                currentDob: currentDob,
                                showBirthdatePublic: showBirthdatePublic,
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
                          fontWeight: FontWeight.w600,
                        ),
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
  // username and dob changes require otp reverification
  // gender and display name save without otp
  Future<void> _saveProfileChanges({
    required String newUsername,
    required String newDisplayName,
    required String currentUsername,
    required String newBio,
    required String newWebsite,
    required String newGender,
    required DateTime? newDob,
    required DateTime? currentDob,
    required bool showBirthdatePublic,
  }) async {
    final sanitizedBio = Sanitizer.bio(newBio);
    final currentWebsite = _profile?['website_url'] as String? ?? '';
    final hasOptionalProfileColumns =
        (_profile?.containsKey('website_url') ?? false) &&
        (_profile?.containsKey('show_birthdate_public') ?? false);
    final trimmedWebsite = newWebsite.trim();
    final sanitizedWebsite = trimmedWebsite.isEmpty
        ? null
        : Sanitizer.url(trimmedWebsite);
    if (trimmedWebsite.isNotEmpty && sanitizedWebsite == null) {
      showErrorSnack(
        context,
        context.l('Use a valid public http or https website link.'),
      );
      return;
    }
    if (showBirthdatePublic && newDob == null && currentDob == null) {
      showInfoSnack(
        context,
        context.l('Add your birth date before making it public.'),
      );
      return;
    }
    if (!hasOptionalProfileColumns &&
        (trimmedWebsite.isNotEmpty || showBirthdatePublic)) {
      showInfoSnack(
        context,
        context.l(
          'Profile link settings will be available after the latest database update is applied.',
        ),
      );
      return;
    }
    final usernameChanged = newUsername != currentUsername;
    final displayChanged =
        newDisplayName != (_profile?['display_name'] as String? ?? '');
    final bioChanged = sanitizedBio != (_profile?['bio'] as String? ?? '');
    final websiteChanged = (sanitizedWebsite ?? '') != currentWebsite;
    final genderChanged = newGender != (_profile?['gender'] as String? ?? '');
    final birthdatePublicChanged =
        showBirthdatePublic !=
        (_profile?['show_birthdate_public'] as bool? ?? false);
    final dobChanged =
        newDob != null &&
        (currentDob == null ||
            newDob.year != currentDob.year ||
            newDob.month != currentDob.month ||
            newDob.day != currentDob.day);

    if (usernameChanged ||
        displayChanged ||
        bioChanged ||
        websiteChanged ||
        genderChanged ||
        birthdatePublicChanged ||
        dobChanged) {
      final retryAfter = await _profileCooldownRemaining();
      if (retryAfter > 0) {
        if (mounted) {
          showInfoSnack(
            context,
            context.l(
              'Profile changes are cooling down. Try again in {time}.',
              {'time': _formatCooldown(retryAfter)},
            ),
          );
        }
        return;
      }
    }

    // otp is required when username or dob changed
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

      // build a patch with only changed fields
      final patch = <String, dynamic>{
        'display_name': Sanitizer.displayName(
          newDisplayName.isNotEmpty ? newDisplayName : newUsername,
        ),
        'gender': newGender,
      };
      if (usernameChanged) patch['username'] = Sanitizer.username(newUsername);
      if (bioChanged) patch['bio'] = sanitizedBio;
      if (websiteChanged) patch['website_url'] = sanitizedWebsite;
      if (birthdatePublicChanged) {
        patch['show_birthdate_public'] = showBirthdatePublic;
      }

      if (dobChanged) {
        // calculate age from new dob
        final today = DateTime.now();
        int age = today.year - newDob.year;
        if (today.month < newDob.month ||
            (today.month == newDob.month && today.day < newDob.day)) {
          age--;
        }
        patch['date_of_birth'] =
            '${newDob.year.toString().padLeft(4, '0')}-'
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
          'bio': sanitizedBio,
          'website_url': sanitizedWebsite,
          'gender': newGender,
          'show_birthdate_public': showBirthdatePublic,
          if (dobChanged)
            'date_of_birth':
                '${newDob.year.toString().padLeft(4, '0')}-'
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
      final response = await client.rpc(
        'get_action_cooldown_status',
        params: {
          'p_action': 'profile_update',
          'p_subject': userId,
          'p_window_seconds': 20 * 60,
          'p_max_actions': 1,
          'p_include_ip': false,
        },
      );
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
      return context.l(
        'Profile changes are cooling down. Please try again later.',
      );
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
                borderRadius: BorderRadius.circular(16),
              ),
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
                    buildCounter:
                        (
                          _, {
                          required currentLength,
                          required isFocused,
                          maxLength,
                        }) => null,
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
                        borderRadius: BorderRadius.circular(10),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: const BorderSide(
                          color: AppColors.fernGreen,
                          width: 2,
                        ),
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
                  child: Text(
                    context.l('Cancel'),
                    style: GoogleFonts.josefinSans(
                      color: AppColors.textSecondary,
                    ),
                  ),
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
    setState(() {
      _isLoading = true;
      // replies and media load lazily per profile
      // reset them so an old empty tab cannot shape the next profile layout
      _repliesTabLoaded = false;
      _mediaTabLoaded = false;
      _repliesTabIsEmpty.value = true;
      _mediaTabIsEmpty.value = true;
      _visitedProfileTabs
        ..clear()
        ..add(
          (_profileTabController?.index ?? _lastProfileTabIndex).clamp(0, 2),
        );
    });
    final client = Supabase.instance.client;
    final myId = client.auth.currentUser?.id;
    const profileSelectBase =
        'id, username, display_name, avatar_url, trust_tier, trust_score, '
        'echo_count, proof_count, is_public, bio, gender, date_of_birth, '
        'is_pro, follower_count, following_count, banner_url, created_at';
    const profileSelectWithLinks =
        'id, username, display_name, avatar_url, trust_tier, trust_score, '
        'echo_count, proof_count, is_public, bio, gender, date_of_birth, '
        'website_url, show_birthdate_public, '
        'is_pro, follower_count, following_count, banner_url, created_at';

    Future<Map<String, dynamic>?> fetchProfile({
      required bool byUsername,
      required String value,
    }) async {
      try {
        final query = client
            .from('users_public')
            .select(profileSelectWithLinks);
        final result = byUsername
            ? await query.eq('username', value).maybeSingle()
            : await query.eq('id', value).maybeSingle();
        return result;
      } on PostgrestException catch (e) {
        if (e.code != '42703') rethrow;
        AppLogger.warn(
          'profile: optional profile columns missing, using legacy select',
        );
        final query = client.from('users_public').select(profileSelectBase);
        final result = byUsername
            ? await query.eq('username', value).maybeSingle()
            : await query.eq('id', value).maybeSingle();
        return result;
      }
    }

    try {
      Map<String, dynamic> profile;

      if (widget.username != null) {
        _isOwnProfile = false;
        final result = await fetchProfile(
          byUsername: true,
          value: widget.username!,
        );
        if (result == null) {
          setState(() {
            _profileUnavailable = true;
            _isLoading = false;
          });
          return;
        }
        final row = result;
        profile = row;
      } else {
        _isOwnProfile = true;
        final result = await fetchProfile(byUsername: false, value: myId!);
        if (result == null) {
          setState(() => _isLoading = false);
          return;
        }
        final row = result;
        profile = row;
        // as map<string, dynamic>
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
      _profileUnavailable = false;

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
              .from('users_private')
              .select('is_identity_verified, last_verification_request_at')
              .eq('id', targetId)
              .maybeSingle(),
        ],
      ]);

      final echoes = results[0] as List<dynamic>;
      final priv = (_isOwnProfile && results.length > 1)
          ? results[1] as Map<String, dynamic>?
          : null;

      final echoEntities = echoes.map((row) {
        final r = row as Map<String, dynamic>;
        final created =
            DateTime.tryParse(r['created_at'] as String? ?? '') ??
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
          supportCount:
              (r['context_support_count'] as num?)?.toInt() ??
              (r['support_count'] as num?)?.toInt() ??
              0,
          challengeCount:
              (r['context_challenge_count'] as num?)?.toInt() ??
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
      final displayEchoCount = storedEchoCount > loadedEchoCount
          ? storedEchoCount
          : loadedEchoCount;
      final displayProfile = {...profile, 'echo_count': displayEchoCount};

      setState(() {
        _profile = displayProfile;
        _echoes = echoEntities;
        _isIdentityVerified = priv?['is_identity_verified'] as bool? ?? false;
        // check if pending
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
        _followRequestStatus =
            requestRow?['status'] as String? ??
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
            unawaited(
              _notifySocialEvent('follow_request', {'request_id': requestId}),
            );
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
        unawaited(_notifySocialEvent('new_follower', {'target_id': targetId}));
      }
      // refresh follower count on profile
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
                style: AppTypography.textTheme.bodySmall?.copyWith(
                  color: AppColors.textSecondary,
                  height: 1.45,
                ),
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
          .update({'is_public': v})
          .eq('id', userId);
    } catch (e) {
      AppLogger.error('profile: set public failed $e');
      setState(() => _isPublic = !v);
    }
  }

  Future<void> _pickBanner() async {
    if (!_isOwnProfile || _isSavingBanner) return;
    if (showOfflineSnackIfNeeded(context)) return;

    setState(() => _isSavingBanner = true);
    try {
      final picked = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        requestFullMetadata: false,
        maxWidth: 2400,
        maxHeight: 2400,
        imageQuality: 96,
      );
      if (picked == null) return;

      final bytes = await picked.readAsBytes();
      if (bytes.length > 12 * 1024 * 1024) {
        throw const StorageException(
          'choose an image under 12 MB before cropping',
        );
      }

      final header = bytes.take(16).toList();
      final sourceName = picked.name.isNotEmpty
          ? picked.name
          : MediaFileSafety.displayName(picked.path);
      final sourceExt = _safeBannerExtension(sourceName, header);
      if (!MediaFileSafety.bytesMatchImageExtension(sourceExt, header)) {
        throw const StorageException('image file looks invalid or corrupted');
      }

      final imageSize = await _decodeBannerImageSize(bytes);
      if (imageSize.width < profileBannerMinWidth ||
          imageSize.height < profileBannerMinHeight) {
        throw StorageException(
          'banner image must be at least $profileBannerMinWidth x $profileBannerMinHeight',
        );
      }

      if (!mounted) return;
      final cropped = await showProfileBannerCropEditor(
        context: context,
        bytes: bytes,
        sourceName: sourceName,
        imageWidth: imageSize.width,
        imageHeight: imageSize.height,
      );
      if (cropped == null) return;

      final storage = StorageService(Supabase.instance.client);
      final upload = await storage.uploadProfileBanner(
        bytes: cropped.bytes,
        extension: cropped.extension,
      );
      final userId = Supabase.instance.client.auth.currentUser?.id;
      if (userId == null) {
        throw const StorageException('sign in again to update banner');
      }

      await Supabase.instance.client
          .from('users_public')
          .update({'banner_url': upload.publicUrl})
          .eq('id', userId);

      if (!mounted) return;
      setState(() {
        _profile = {...?_profile, 'banner_url': upload.publicUrl};
      });
      showSuccessSnack(context, context.l('Banner updated.'));
    } on StorageException catch (e) {
      if (mounted) showErrorSnack(context, e.message);
    } catch (e) {
      AppLogger.error('profile: banner update failed $e');
      if (mounted) {
        showErrorSnack(context, context.l('Could not update banner.'));
      }
    } finally {
      if (mounted) setState(() => _isSavingBanner = false);
    }
  }

  Future<({int width, int height})> _decodeBannerImageSize(
    Uint8List bytes,
  ) async {
    final codec = await ui.instantiateImageCodec(bytes);
    try {
      final frame = await codec.getNextFrame();
      final image = frame.image;
      try {
        return (width: image.width, height: image.height);
      } finally {
        image.dispose();
      }
    } finally {
      codec.dispose();
    }
  }

  String _safeBannerExtension(String sourceName, List<int> header) {
    final declared = MediaFileSafety.extensionOf(sourceName);
    const allowed = ['jpg', 'jpeg', 'png', 'webp'];
    if (allowed.contains(declared) &&
        MediaFileSafety.bytesMatchImageExtension(declared, header)) {
      return declared;
    }

    for (final candidate in allowed) {
      if (MediaFileSafety.bytesMatchImageExtension(candidate, header)) {
        return candidate;
      }
    }

    throw const StorageException('only jpg, png, or webp banners allowed');
  }

  void _openBannerViewer() {
    final bannerUrl = _profile?['banner_url'] as String?;
    if (bannerUrl == null || bannerUrl.isEmpty) return;
    ImageViewer.show(context, urls: [bannerUrl]);
  }

  Widget _refreshableProfileState(Widget child) {
    final minHeight =
        MediaQuery.sizeOf(context).height -
        kToolbarHeight -
        MediaQuery.paddingOf(context).top -
        MediaQuery.paddingOf(context).bottom -
        120;

    return RefreshIndicator(
      color: AppColors.fernGreen,
      onRefresh: _loadProfile,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          SizedBox(
            height: minHeight.clamp(360.0, double.infinity).toDouble(),
            child: Center(child: child),
          ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return _refreshableProfileState(
        EchoLogoLoader(label: context.l('Loading profile')),
      );
    }

    if (_profile == null) {
      return _refreshableProfileState(
        widget.username == null
            ? Text(
                context.l('Could not load profile'),
                style: AppTypography.textTheme.bodyMedium,
              )
            : _UnavailableProfileNotice(username: widget.username!),
      );
    }

    final locked = !_canViewProfileContent;
    final tabs = locked
        ? <Widget>[Tab(text: context.l('Private'))]
        : <Widget>[
            Tab(text: context.l('Echoes')),
            Tab(text: context.l('Replies')),
            Tab(text: context.l('Media')),
          ];

    final profileTabController = _ensureProfileTabController(tabs.length);
    final selectedTabIndex = _lastProfileTabIndex.clamp(0, tabs.length - 1);
    _visitedProfileTabs.add(selectedTabIndex);
    final tabBodies = locked
        ? <Widget>[_LockedProfileTab(username: _profile!['username'] as String)]
        : <Widget>[
            _EchoesTab(echoes: _echoes),
            _visitedProfileTabs.contains(1)
                ? _RepliesTab(
                    userId: _profile!['id'],
                    onEmptyChanged: _setRepliesTabEmpty,
                  )
                : const SizedBox.shrink(),
            _visitedProfileTabs.contains(2)
                ? _MediaTab(
                    userId: _profile!['id'],
                    onEmptyChanged: _setMediaTabEmpty,
                  )
                : const SizedBox.shrink(),
          ];
    List<Widget> profileHeaderSlivers() => [
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.only(bottom: AppSpacing.xl),
          child: Column(
            children: [
              _AvatarCard(
                profile: _profile!,
                isIdentityVerified: _isIdentityVerified,
                isOwnProfile: _isOwnProfile,
                isSavingBanner: _isSavingBanner,
                showStats: _canViewProfileContent,
                onOpenFollowers: _canOpenFollowLists
                    ? () => _openFollowList(mode: 'followers')
                    : null,
                onOpenFollowing: _canOpenFollowLists
                    ? () => _openFollowList(mode: 'following')
                    : null,
                onEditProfile: _showEditProfileSheet,
                onEditBanner: _pickBanner,
                onOpenBanner: _openBannerViewer,
              ),
              if (_isOwnProfile) ...[
                const SizedBox(height: AppSpacing.md),
                _ProfileOwnerControlPanel(
                  isPublic: _isPublic,
                  isIdentityVerified: _isIdentityVerified,
                  isVerificationPending: _isVerificationPending,
                  onPublicToggle: _setPublic,
                ),
              ],
              if (_isOwnProfile && userIsPro) ...[
                const SizedBox(height: AppSpacing.md),
                _AnalyticsShortcutCard(
                  onTap: () => context.push('/profile/analytics'),
                ),
              ],
              if (!_isOwnProfile) ...[
                const SizedBox(height: AppSpacing.md),
                SizedBox(
                  width: double.infinity,
                  child: _isBlockedByMe
                      ? _UnblockButton(onPressed: () => _unblockProfileUser())
                      : _ProfileFollowButton(
                          isFollowing: _isFollowing,
                          requestStatus: _followRequestStatus,
                          isPrivate: !_isPublic,
                          onPressed: _toggleFollow,
                        ),
                ),
              ],
              const SizedBox(height: AppSpacing.md),
              if (!_isOwnProfile && !_isPublic && !_isBlockedByMe)
                _PrivateProfileNotice(
                  username: _profile!['username'] as String,
                  requestStatus: _followRequestStatus,
                ),
              if (!_isOwnProfile && _isBlockedByMe)
                _BlockedProfileNotice(
                  username: _profile!['username'] as String,
                  onUnblock: () => _unblockProfileUser(),
                ),
              const SizedBox(height: AppSpacing.lg),
            ],
          ),
        ),
      ),
      SliverPersistentHeader(
        pinned: true,
        delegate: _TabBarDelegate(
          TabBar(
            controller: profileTabController,
            tabs: tabs,
            isScrollable: tabs.length > 4,
            tabAlignment: tabs.length > 4 ? TabAlignment.start : null,
          ),
        ),
      ),
    ];

    final profileScroll = CustomScrollView(
      key: const PageStorageKey<String>('profile-scroll'),
      controller: _profileOuterScrollController,
      physics: const ClampingScrollPhysics(),
      slivers: [
        ...profileHeaderSlivers(),
        SliverToBoxAdapter(
          child: _ProfileTabBodyStack(
            selectedIndex: selectedTabIndex,
            profileId: _profile!['id'] as String,
            children: tabBodies,
          ),
        ),
        const SliverToBoxAdapter(child: SizedBox(height: 96)),
      ],
    );

    return FadeTransition(
      opacity: _fade,
      child: SlideTransition(
        position: _slide,
        child: RefreshIndicator(
          color: AppColors.fernGreen,
          onRefresh: _loadProfile,
          child: profileScroll,
        ),
      ),
    );
  }

  void _openFollowList({required String mode}) {
    if (_profile == null || !_canViewProfileContent) return;
    if (!_canOpenFollowLists) return;

    final username = _profile!['username'] as String? ?? '';
    if (username.isEmpty) return;
    context.push('/profile/${Uri.encodeComponent(username)}/follows?tab=$mode');
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
                  icon: Icons.bookmark_border_rounded,
                  title: context.l('Bookmarks'),
                  subtitle: context.l('Saved echoes to revisit later'),
                  onTap: () {
                    Navigator.pop(sheetContext);
                    context.push('/profile/bookmarks');
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
                    // explicit on and off colors avoid invisible native defaults
                    // especially when the sheet background is also light
                    activeThumbColor: AppColors.white,
                    activeTrackColor: AppColors.fernGreen,
                    inactiveThumbColor: AppColors.white,
                    inactiveTrackColor: AppColors.textTertiary,
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
          {...byId[block['blocked_id']]!, 'blocked_at': block['created_at']},
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
          bottomNavigationBar: AppBottomNav(currentLocation: bottomNavLocation),
          body: Stack(
            children: [
              _isOwnProfile
                  ? _buildBody()
                  : kReleaseMode
                  ? SecureScreen(child: _buildBody())
                  : _buildBody(),
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: TopFlowLoader(
                  visible: _isLoading || _isSavingProfile || _isSavingBanner,
                ),
              ),
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
        ),
      ),
    );
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
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    return Container(color: Colors.white, child: tabBar);
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
    final background = (isFollowing || isPending)
        ? AppColors.white
        : AppColors.fernGreenLight;

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

class _AnalyticsShortcutCard extends StatelessWidget {
  const _AnalyticsShortcutCard({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 360),
      curve: Curves.easeOutCubic,
      builder: (context, value, child) {
        return Opacity(
          opacity: value,
          child: Transform.translate(
            offset: Offset(0, 10 * (1 - value)),
            child: child,
          ),
        );
      },
      child: Material(
        color: AppColors.surfaceSecondary,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.borderSubtle),
            ),
            child: Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: AppColors.fernGreenLight,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Icon(
                    Icons.insights_rounded,
                    color: AppColors.fernGreenDark,
                    size: 21,
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        context.l('Professional dashboard'),
                        style: AppTypography.textTheme.titleSmall,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        context.l('Track trust, reach, and public context'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTypography.textTheme.labelMedium,
                      ),
                    ],
                  ),
                ),
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
              style: AppTypography.textTheme.bodySmall?.copyWith(
                color: AppColors.textSecondary,
              ),
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

class _UnavailableProfileNotice extends StatelessWidget {
  const _UnavailableProfileNotice({required this.username});

  final String username;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: AppColors.surfaceSecondary,
                shape: BoxShape.circle,
                border: Border.all(color: AppColors.borderSubtle),
              ),
              child: const Icon(
                Icons.person_off_rounded,
                size: 34,
                color: AppColors.textTertiary,
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            Text(
              '@$username',
              style: AppTypography.textTheme.labelLarge?.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              context.l('This profile is unavailable'),
              style: AppTypography.textTheme.headlineSmall?.copyWith(
                color: AppColors.charcoal,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              context.l(
                'You cannot view this profile, follow list, echoes, or rooms right now.',
              ),
              style: AppTypography.textTheme.bodyMedium?.copyWith(
                color: AppColors.textSecondary,
                height: 1.35,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

Future<String?> _currentUserId(SupabaseClient client) async {
  final cached =
      client.auth.currentSession?.user.id ?? client.auth.currentUser?.id;
  if (cached != null && cached.isNotEmpty) return cached;

  try {
    return (await client.auth.getUser()).user?.id;
  } catch (e) {
    AppLogger.warn('profile: auth user lookup failed $e');
    return null;
  }
}

Future<void> _notifyProfileSocialEvent(
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

class ProfileFollowsScreen extends StatefulWidget {
  const ProfileFollowsScreen({
    super.key,
    required this.username,
    this.initialMode = 'followers',
  });

  final String username;
  final String initialMode;

  @override
  State<ProfileFollowsScreen> createState() => _ProfileFollowsScreenState();
}

class _ProfileFollowsScreenState extends State<ProfileFollowsScreen> {
  late Future<_FollowListProfileState> _future;

  @override
  void initState() {
    super.initState();
    _future = _loadProfileState();
  }

  Future<_FollowListProfileState> _loadProfileState() async {
    final client = Supabase.instance.client;
    final myId = await _currentUserId(client);
    final profile = await client
        .from('users_public')
        .select(
          'id, username, display_name, avatar_url, is_public, follower_count, following_count, trust_tier, is_pro',
        )
        .eq('username', widget.username)
        .maybeSingle();

    if (profile == null) {
      return const _FollowListProfileState.notFound();
    }

    final targetId = profile['id'] as String;
    final isOwnProfile = myId != null && myId == targetId;
    var isBlockedByMe = false;

    if (!isOwnProfile && myId != null) {
      final block = await client
          .from('user_blocks')
          .select('id')
          .eq('blocker_id', myId)
          .eq('blocked_id', targetId)
          .maybeSingle();
      isBlockedByMe = block != null;
    }

    final isPublic = profile['is_public'] as bool? ?? true;
    final canView = isOwnProfile || (!isBlockedByMe && isPublic);
    return _FollowListProfileState(
      profile: Map<String, dynamic>.from(profile),
      canView: canView,
      isOwnProfile: isOwnProfile,
      isBlockedByMe: isBlockedByMe,
      currentUserId: myId,
    );
  }

  Future<void> _refresh() async {
    setState(() => _future = _loadProfileState());
    await _future;
  }

  @override
  Widget build(BuildContext context) {
    final initialIndex = widget.initialMode == 'following' ? 1 : 0;

    return FutureBuilder<_FollowListProfileState>(
      future: _future,
      builder: (context, snapshot) {
        final state = snapshot.data;
        final profile = state?.profile;
        final username = profile?['username'] as String? ?? widget.username;
        final title = username.isEmpty ? context.l('Profile') : '@$username';

        if (snapshot.connectionState == ConnectionState.waiting) {
          return Scaffold(
            backgroundColor: AppColors.surfaceSecondary,
            appBar: _followListAppBar(context, title),
            body: EchoLogoLoader(label: context.l('Loading profile')),
          );
        }

        if (snapshot.hasError || state == null || profile == null) {
          return _FollowListMessageScaffold(
            title: title,
            icon: Icons.person_off_outlined,
            heading: context.l('Could not load profile'),
            message: context.l('Pull down and try again.'),
            onRefresh: _refresh,
          );
        }

        if (!state.canView) {
          return _FollowListMessageScaffold(
            title: title,
            icon: state.isBlockedByMe
                ? Icons.block_rounded
                : Icons.lock_outline_rounded,
            heading: state.isBlockedByMe
                ? context.l('Profile blocked')
                : context.l('Private profile'),
            message: context.l(
              'Follower lists are visible only on public profiles.',
            ),
            onRefresh: _refresh,
          );
        }

        return DefaultTabController(
          length: 2,
          initialIndex: initialIndex,
          child: Scaffold(
            backgroundColor: AppColors.surfaceSecondary,
            appBar: _followListAppBar(
              context,
              title,
              bottom: _FollowTopTabBar(profile: profile),
            ),
            body: TabBarView(
              children: [
                _FollowUsersTab(
                  mode: 'followers',
                  isOwner: state.isOwnProfile,
                  ownerId: profile['id'] as String,
                  expectedCount:
                      (profile['follower_count'] as num?)?.toInt() ?? 0,
                  loadUsers: () => _loadFollowUsers(
                    client: Supabase.instance.client,
                    username: username,
                    mode: 'followers',
                    currentUserId: state.currentUserId,
                  ),
                ),
                _FollowUsersTab(
                  mode: 'following',
                  isOwner: state.isOwnProfile,
                  ownerId: profile['id'] as String,
                  expectedCount:
                      (profile['following_count'] as num?)?.toInt() ?? 0,
                  loadUsers: () => _loadFollowUsers(
                    client: Supabase.instance.client,
                    username: username,
                    mode: 'following',
                    currentUserId: state.currentUserId,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  PreferredSizeWidget _followListAppBar(
    BuildContext context,
    String title, {
    PreferredSizeWidget? bottom,
  }) {
    return AppBar(
      backgroundColor: AppColors.white,
      foregroundColor: AppColors.charcoal,
      surfaceTintColor: AppColors.white,
      elevation: 0,
      centerTitle: true,
      bottom: bottom,
      title: Text(
        title,
        style: GoogleFonts.josefinSans(
          fontSize: 18,
          fontWeight: FontWeight.w700,
          color: AppColors.charcoal,
        ),
      ),
    );
  }
}

class _FollowListProfileState {
  const _FollowListProfileState({
    required this.profile,
    required this.canView,
    required this.isOwnProfile,
    required this.isBlockedByMe,
    required this.currentUserId,
  });

  const _FollowListProfileState.notFound()
    : profile = null,
      canView = false,
      isOwnProfile = false,
      isBlockedByMe = false,
      currentUserId = null;

  final Map<String, dynamic>? profile;
  final bool canView;
  final bool isOwnProfile;
  final bool isBlockedByMe;
  final String? currentUserId;
}

class _FollowTopTabBar extends StatelessWidget implements PreferredSizeWidget {
  const _FollowTopTabBar({required this.profile});

  final Map<String, dynamic> profile;

  @override
  Size get preferredSize => const Size.fromHeight(54);

  @override
  Widget build(BuildContext context) {
    final followerCount = (profile['follower_count'] as num?)?.toInt() ?? 0;
    final followingCount = (profile['following_count'] as num?)?.toInt() ?? 0;

    return Material(
      color: AppColors.white,
      child: DecoratedBox(
        decoration: const BoxDecoration(
          border: Border(
            top: BorderSide(color: AppColors.borderSubtle),
            bottom: BorderSide(color: AppColors.borderSubtle),
          ),
        ),
        child: TabBar(
          labelColor: AppColors.charcoal,
          unselectedLabelColor: AppColors.textSecondary,
          indicatorColor: AppColors.fernGreen,
          indicatorWeight: 2.5,
          dividerColor: Colors.transparent,
          tabs: [
            _FollowTopTab(
              label: context.l('Followers'),
              count: _compactCount(followerCount),
            ),
            _FollowTopTab(
              label: context.l('Following'),
              count: _compactCount(followingCount),
            ),
          ],
        ),
      ),
    );
  }

  String _compactCount(int value) {
    if (value >= 1000000) {
      return '${(value / 1000000).toStringAsFixed(1)}m';
    }
    if (value >= 1000) {
      return '${(value / 1000).toStringAsFixed(1)}k';
    }
    return value.toString();
  }
}

class _FollowTopTab extends StatelessWidget {
  const _FollowTopTab({required this.label, required this.count});

  final String label;
  final String count;

  @override
  Widget build(BuildContext context) {
    return Tab(
      height: 52,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.josefinSans(
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            count,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.josefinSans(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

class _FollowListMessageScaffold extends StatelessWidget {
  const _FollowListMessageScaffold({
    required this.title,
    required this.icon,
    required this.heading,
    required this.message,
    required this.onRefresh,
  });

  final String title;
  final IconData icon;
  final String heading;
  final String message;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surfaceSecondary,
      appBar: AppBar(
        backgroundColor: AppColors.white,
        foregroundColor: AppColors.charcoal,
        surfaceTintColor: AppColors.white,
        elevation: 0,
        centerTitle: true,
        title: Text(
          title,
          style: GoogleFonts.josefinSans(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: AppColors.charcoal,
          ),
        ),
      ),
      body: RefreshIndicator(
        color: AppColors.fernGreen,
        onRefresh: onRefresh,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(AppSpacing.xl),
          children: [
            SizedBox(height: MediaQuery.sizeOf(context).height * 0.18),
            _ProfileEmptyTab(icon: icon, title: heading, message: message),
          ],
        ),
      ),
    );
  }
}

Future<List<Map<String, dynamic>>> _loadFollowUsers({
  required SupabaseClient client,
  required String username,
  required String mode,
  required String? currentUserId,
}) async {
  final response = await client.rpc(
    'get_profile_follow_users',
    params: {
      'p_target_username': username,
      'p_mode': mode,
      'p_limit': 100,
      'p_offset': 0,
    },
  );
  final users = List<Map<String, dynamic>>.from(response as List);
  if (currentUserId == null || users.isEmpty) return users;

  final ids = users
      .map((user) => user['id'] as String?)
      .whereType<String>()
      .where((id) => id != currentUserId)
      .toList();
  if (ids.isEmpty) return users;

  final idFilter = '(${ids.join(',')})';
  final followingRows = await client
      .from('user_follows')
      .select('following_id')
      .eq('follower_id', currentUserId)
      .filter('following_id', 'in', idFilter);
  final publicRows = await client
      .from('users_public')
      .select('id, is_public')
      .filter('id', 'in', idFilter);

  final followingIds = Set<String>.from(
    (followingRows as List)
        .map((row) => (row as Map<String, dynamic>)['following_id'])
        .whereType<String>(),
  );
  final publicById = <String, bool>{};
  for (final row in publicRows as List) {
    final map = row as Map<String, dynamic>;
    publicById[map['id'] as String] = map['is_public'] as bool? ?? true;
  }

  return users
      .map(
        (user) => {
          ...user,
          'viewer_is_following': followingIds.contains(user['id']),
          'is_public': publicById[user['id']] ?? true,
        },
      )
      .toList();
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
                  Text(
                    context.l('Blocked users'),
                    style: AppTypography.textTheme.titleMedium,
                  ),
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
                    separatorBuilder: (context, index) =>
                        const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final user = users[index];
                      final userId = user['id'] as String? ?? '';
                      final username = user['username'] as String? ?? 'unknown';
                      final displayName =
                          (user['display_name'] as String?)
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
    required this.isSavingBanner,
    required this.showStats,
    required this.onOpenFollowers,
    required this.onOpenFollowing,
    required this.onEditProfile,
    required this.onEditBanner,
    required this.onOpenBanner,
  });

  final Map<String, dynamic> profile;
  final bool isIdentityVerified;
  final bool isOwnProfile;
  final bool isSavingBanner;
  final bool showStats;
  final VoidCallback? onOpenFollowers;
  final VoidCallback? onOpenFollowing;
  final VoidCallback onEditProfile;
  final VoidCallback onEditBanner;
  final VoidCallback onOpenBanner;

  @override
  Widget build(BuildContext context) {
    final avatarUrl = profile['avatar_url'] as String?;
    final bannerUrl = profile['banner_url'] as String?;
    final username = profile['username'] as String? ?? '';
    final displayName = profile['display_name'] as String? ?? '';
    final bio = profile['bio'] as String?;
    final websiteUrl = profile['website_url'] as String?;
    final showBirthdatePublic =
        profile['show_birthdate_public'] as bool? ?? false;
    final hasBio = bio != null && bio.isNotEmpty;
    final hasWebsite = websiteUrl != null && websiteUrl.trim().isNotEmpty;
    final echoCount = (profile['echo_count'] as num?)?.toInt() ?? 0;
    final followerCount = (profile['follower_count'] as num?)?.toInt() ?? 0;
    final followingCount = (profile['following_count'] as num?)?.toInt() ?? 0;
    final joined = _formatJoinedMonth(profile['created_at'] as String?);
    final birthdate = _formatBirthdate(
      profile['date_of_birth'] as String?,
      includeYear: isOwnProfile,
    );
    final heroTag = 'profile-avatar:${profile['id'] ?? username}';

    final maxWidth = MediaQuery.sizeOf(context).width;
    final bannerHeight = maxWidth < 380 ? 132.0 : 156.0;

    return Container(
      clipBehavior: Clip.antiAlias,
      width: double.infinity,
      decoration: const BoxDecoration(color: Colors.white),
      child: Column(
        children: [
          Stack(
            clipBehavior: Clip.none,
            children: [
              GestureDetector(
                onTap: bannerUrl != null && bannerUrl.isNotEmpty
                    ? onOpenBanner
                    : null,
                child: SizedBox(
                  height: bannerHeight,
                  width: double.infinity,
                  child: _ProfileBanner(
                    bannerUrl: bannerUrl,
                    isSaving: isSavingBanner,
                  ),
                ),
              ),
              if (isOwnProfile)
                Positioned(
                  right: AppSpacing.md,
                  top: AppSpacing.md,
                  child: _BannerEditButton(
                    isSaving: isSavingBanner,
                    onTap: onEditBanner,
                  ),
                ),
              Positioned(
                left: AppSpacing.xl,
                bottom: -42,
                child: GestureDetector(
                  onTap:
                      isOwnProfile ||
                          (avatarUrl != null && avatarUrl.isNotEmpty)
                      ? () => _showAvatarZoom(context, avatarUrl, heroTag)
                      : null,
                  child: Hero(
                    tag: heroTag,
                    child: _ProfileAvatarWithBadge(
                      avatarUrl: avatarUrl,
                      radius: 43,
                    ),
                  ),
                ),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.xl,
              54,
              AppSpacing.xl,
              AppSpacing.xl,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Flexible(
                                child: Text(
                                  displayName.isNotEmpty
                                      ? displayName
                                      : '@$username',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: GoogleFonts.josefinSans(
                                    fontSize: 24,
                                    fontWeight: FontWeight.w800,
                                    color: AppColors.charcoal,
                                    letterSpacing: 0,
                                  ),
                                ),
                              ),
                              if (isIdentityVerified) ...[
                                const SizedBox(width: 7),
                                const AccountVerifiedBadge(size: 20),
                              ],
                            ],
                          ),
                          if (displayName.isNotEmpty)
                            Text(
                              '@$username',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.josefinSans(
                                fontSize: 14,
                                color: AppColors.textSecondary,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          if (joined != null) ...[
                            const SizedBox(height: 7),
                            Row(
                              children: [
                                const Icon(
                                  Icons.calendar_month_outlined,
                                  size: 15,
                                  color: AppColors.textSecondary,
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  context.l('Joined {date}', {'date': joined}),
                                  style: GoogleFonts.josefinSans(
                                    fontSize: 13,
                                    color: AppColors.textSecondary,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                          ],
                          if ((isOwnProfile || showBirthdatePublic) &&
                              birthdate != null) ...[
                            const SizedBox(height: 7),
                            Row(
                              children: [
                                const Icon(
                                  Icons.cake_outlined,
                                  size: 15,
                                  color: AppColors.textSecondary,
                                ),
                                const SizedBox(width: 6),
                                Flexible(
                                  child: Text(
                                    isOwnProfile
                                        ? context.l('Born {date}', {
                                            'date': birthdate,
                                          })
                                        : birthdate,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: GoogleFonts.josefinSans(
                                      fontSize: 13,
                                      color: AppColors.textSecondary,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),
                    if (isOwnProfile)
                      _InlineProfileEditButton(onTap: onEditProfile),
                  ],
                ),
                if (hasBio) ...[
                  const SizedBox(height: AppSpacing.md),
                  Text(
                    bio,
                    style: GoogleFonts.josefinSans(
                      fontSize: 14,
                      height: 1.5,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
                if (hasWebsite) ...[
                  const SizedBox(height: AppSpacing.sm),
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => _openWebsiteSheet(context, websiteUrl),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.link_rounded,
                          size: 16,
                          color: AppColors.fernGreenDark,
                        ),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            _displayWebsite(websiteUrl),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.josefinSans(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: AppColors.fernGreenDark,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: AppSpacing.lg),
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
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: AppColors.borderSubtle),
                    ),
                    child: Text(
                      context.l(
                        'Follow request required to view echoes, replies, followers, and following.',
                      ),
                      textAlign: TextAlign.center,
                      style: AppTypography.textTheme.bodySmall?.copyWith(
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ),
                if (!isOwnProfile) ...[
                  const SizedBox(height: AppSpacing.lg),
                  _ProfileTrustNotice(isIdentityVerified: isIdentityVerified),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  String? _formatJoinedMonth(String? value) {
    final date = DateTime.tryParse(value ?? '');
    if (date == null) return null;
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
    return '${months[date.month - 1]} ${date.year}';
  }

  String? _formatBirthdate(String? value, {required bool includeYear}) {
    final date = DateTime.tryParse(value ?? '');
    if (date == null) return null;
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
    final base = '${months[date.month - 1]} ${date.day}';
    return includeYear ? '$base, ${date.year}' : base;
  }

  static String _displayWebsite(String value) {
    return value
        .replaceFirst(RegExp(r'^https?://', caseSensitive: false), '')
        .replaceFirst(RegExp(r'/$'), '');
  }

  static Future<void> _openWebsiteSheet(
    BuildContext context,
    String websiteUrl,
  ) async {
    final uri = Uri.tryParse(websiteUrl);
    if (uri == null) return;
    await showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.xl,
            AppSpacing.lg,
            AppSpacing.xl,
            AppSpacing.xl,
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
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              Text(
                _displayWebsite(websiteUrl),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: AppTypography.textTheme.titleSmall,
              ),
              const SizedBox(height: AppSpacing.md),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () async {
                        Navigator.pop(ctx);
                        await launchUrl(uri, mode: LaunchMode.inAppBrowserView);
                      },
                      icon: const Icon(Icons.open_in_new_rounded, size: 17),
                      label: Text(context.l('Open here')),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () async {
                        Navigator.pop(ctx);
                        await launchUrl(
                          uri,
                          mode: LaunchMode.externalApplication,
                        );
                      },
                      icon: const Icon(Icons.public_rounded, size: 17),
                      label: Text(context.l('Browser')),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
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
        pageBuilder: (context, animation, secondaryAnimation) =>
            _AvatarZoomPage(avatarUrl: avatarUrl, heroTag: heroTag),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
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

class _ProfileBanner extends StatelessWidget {
  const _ProfileBanner({required this.bannerUrl, required this.isSaving});

  final String? bannerUrl;
  final bool isSaving;

  @override
  Widget build(BuildContext context) {
    final url = bannerUrl?.trim();
    if (url != null && url.isNotEmpty) {
      return Stack(
        fit: StackFit.expand,
        children: [
          Image.network(
            url,
            fit: BoxFit.cover,
            errorBuilder: (context, error, stackTrace) =>
                const _DefaultProfileBanner(),
          ),
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.transparent,
                  Colors.black.withValues(alpha: 0.05),
                ],
              ),
            ),
          ),
          if (isSaving) const _BannerSavingScrim(),
        ],
      );
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        const _DefaultProfileBanner(),
        if (isSaving) const _BannerSavingScrim(),
      ],
    );
  }
}

class _DefaultProfileBanner extends StatelessWidget {
  const _DefaultProfileBanner();

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _DefaultBannerPainter(),
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              const Color(0xFFEAF6F0),
              const Color(0xFFF9FCFA),
              AppColors.fernGreen.withValues(alpha: 0.10),
            ],
          ),
        ),
      ),
    );
  }
}

class _DefaultBannerPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final green = Paint()
      ..color = AppColors.fernGreen.withValues(alpha: 0.20)
      ..style = PaintingStyle.fill;
    final line = Paint()
      ..color = Colors.white.withValues(alpha: 0.46)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;

    canvas.drawCircle(
      Offset(size.width * 0.78, size.height * 0.16),
      size.shortestSide * 0.36,
      green,
    );

    for (var i = 0; i < 18; i++) {
      final t = i / 17;
      final path = Path()
        ..moveTo(size.width * (0.12 + t * 0.38), size.height * 0.18)
        ..quadraticBezierTo(
          size.width * (0.32 + t * 0.16),
          size.height * (0.44 + t * 0.08),
          size.width * (0.66 + t * 0.15),
          size.height * (0.28 + t * 0.22),
        );
      canvas.drawPath(path, line);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _BannerSavingScrim extends StatelessWidget {
  const _BannerSavingScrim();

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Colors.white.withValues(alpha: 0.42),
      child: const Center(
        child: SizedBox(
          width: 22,
          height: 22,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: AppColors.fernGreen,
          ),
        ),
      ),
    );
  }
}

class _BannerEditButton extends StatelessWidget {
  const _BannerEditButton({required this.isSaving, required this.onTap});

  final bool isSaving;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white.withValues(alpha: 0.92),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: isSaving ? null : onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                isSaving ? Icons.hourglass_top_rounded : Icons.image_outlined,
                size: 16,
                color: isSaving ? AppColors.textTertiary : AppColors.charcoal,
              ),
              const SizedBox(width: 6),
              Text(
                isSaving ? context.l('Saving') : context.l('Banner'),
                style: GoogleFonts.josefinSans(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: isSaving ? AppColors.textTertiary : AppColors.charcoal,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _InlineProfileEditButton extends StatelessWidget {
  const _InlineProfileEditButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.softSand,
      borderRadius: BorderRadius.circular(13),
      child: InkWell(
        borderRadius: BorderRadius.circular(13),
        onTap: onTap,
        child: const Padding(
          padding: EdgeInsets.all(10),
          child: Icon(Icons.edit_outlined, size: 18, color: AppColors.charcoal),
        ),
      ),
    );
  }
}

class _ProfileTrustNotice extends StatelessWidget {
  const _ProfileTrustNotice({required this.isIdentityVerified});

  final bool isIdentityVerified;

  @override
  Widget build(BuildContext context) {
    final title = isIdentityVerified
        ? context.l('Verified')
        : context.l('Unverified');
    final body = isIdentityVerified
        ? context.l('This profile has completed identity verification.')
        : context.l("This user hasn't verified their identity yet.");

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.fernGreen.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.fernGreen.withValues(alpha: 0.22)),
      ),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: AppColors.fernGreen.withValues(alpha: 0.14),
              shape: BoxShape.circle,
            ),
            child: Icon(
              isIdentityVerified
                  ? Icons.verified_rounded
                  : Icons.shield_outlined,
              size: 19,
              color: AppColors.fernGreen,
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: GoogleFonts.josefinSans(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: AppColors.fernGreenDark,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  body,
                  style: GoogleFonts.josefinSans(
                    fontSize: 13,
                    height: 1.35,
                    color: AppColors.fernGreenDark,
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

class _AvatarZoomPage extends StatefulWidget {
  const _AvatarZoomPage({required this.avatarUrl, required this.heroTag});

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
      _controller.value = _zoomed
          ? Matrix4.diagonal3Values(2.35, 2.35, 1)
          : Matrix4.identity();
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
                        colors: [AppColors.fernGreen, AppColors.fernGreenDark],
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
                                  errorBuilder: (context, error, stackTrace) =>
                                      Container(
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
                    border: Border.all(color: AppColors.borderSubtle),
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
                  style: IconButton.styleFrom(backgroundColor: Colors.white),
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
    return Container(width: 1, height: 32, color: AppColors.borderSubtle);
  }
}

class _ProfileAvatarWithBadge extends StatelessWidget {
  const _ProfileAvatarWithBadge({
    required this.avatarUrl,
    required this.radius,
  });

  final String? avatarUrl;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final diameter = radius * 2;

    return CircleAvatar(
      radius: radius,
      backgroundColor: AppColors.softSand,
      child: ClipOval(
        child: (avatarUrl != null && avatarUrl!.isNotEmpty)
            ? avatarUrl!.endsWith('.svg')
                  ? SvgPicture.network(
                      avatarUrl!,
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
                      avatarUrl!,
                      width: diameter,
                      height: diameter,
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) => Icon(
                        Icons.person_outline,
                        size: radius * 0.77,
                        color: AppColors.textTertiary,
                      ),
                    )
            : Icon(
                Icons.person_outline,
                size: radius * 0.77,
                color: AppColors.textTertiary,
              ),
      ),
    );
  }
}

class _ProfileOwnerControlPanel extends StatelessWidget {
  const _ProfileOwnerControlPanel({
    required this.isPublic,
    required this.isIdentityVerified,
    required this.isVerificationPending,
    required this.onPublicToggle,
  });

  final bool isPublic;
  final bool isIdentityVerified;
  final bool isVerificationPending;
  final ValueChanged<bool> onPublicToggle;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.borderSubtle),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.025),
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              const Icon(
                Icons.tune_rounded,
                size: 18,
                color: AppColors.fernGreenDark,
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  context.l('Profile controls'),
                  style: AppTypography.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          _VisibilityToggle(isPublic: isPublic, onToggle: onPublicToggle),
          if (!isIdentityVerified) ...[
            const SizedBox(height: AppSpacing.sm),
            _VerifyPrompt(isPending: isVerificationPending),
          ] else ...[
            const SizedBox(height: AppSpacing.sm),
            _OwnerControlTile(
              icon: Icons.verified_user_rounded,
              title: context.l('Identity verified'),
              subtitle: context.l(
                'Your trust badge is visible beside your name',
              ),
              color: AppColors.fernGreenDark,
              onTap: null,
            ),
          ],
          const SizedBox(height: AppSpacing.sm),
          _OwnerControlTile(
            icon: Icons.link_rounded,
            title: context.l('Solana record layer'),
            subtitle: context.l(
              'Anchored echoes can be reviewed from proof trails',
            ),
            color: AppColors.fernGreenDark,
            onTap: () => _showSolanaRecordLayerSheet(context),
          ),
        ],
      ),
    );
  }
}

void _showSolanaRecordLayerSheet(BuildContext context) {
  showModalBottomSheet<void>(
    context: context,
    useSafeArea: true,
    backgroundColor: AppColors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
    ),
    builder: (sheetContext) => Padding(
      padding: EdgeInsets.fromLTRB(
        AppSpacing.xl,
        AppSpacing.lg,
        AppSpacing.xl,
        AppSpacing.xl + MediaQuery.paddingOf(sheetContext).bottom,
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
          const SizedBox(height: AppSpacing.lg),
          Row(
            children: [
              const Icon(Icons.link_rounded, color: AppColors.fernGreenDark),
              const SizedBox(width: AppSpacing.sm),
              Text(
                context.l('Solana record layer'),
                style: AppTypography.textTheme.titleMedium,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          _SolanaStep(
            number: '1',
            title: context.l('Claim is created'),
            body: context.l('EchoProof stores the claim and its media safely.'),
          ),
          _SolanaStep(
            number: '2',
            title: context.l('Public window closes'),
            body: context.l('The final context result becomes eligible.'),
          ),
          _SolanaStep(
            number: '3',
            title: context.l('Hash is anchored'),
            body: context.l(
              'Only the proof hash is written, not private data.',
            ),
            isLast: true,
          ),
        ],
      ),
    ),
  );
}

class _SolanaStep extends StatelessWidget {
  const _SolanaStep({
    required this.number,
    required this.title,
    required this.body,
    this.isLast = false,
  });

  final String number;
  final String title;
  final String body;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Column(
          children: [
            Container(
              width: 28,
              height: 28,
              alignment: Alignment.center,
              decoration: const BoxDecoration(
                color: AppColors.fernGreenLight,
                shape: BoxShape.circle,
              ),
              child: Text(
                number,
                style: GoogleFonts.josefinSans(
                  fontSize: 12,
                  fontWeight: FontWeight.w900,
                  color: AppColors.fernGreenDark,
                ),
              ),
            ),
            if (!isLast)
              Container(width: 1.5, height: 42, color: AppColors.borderSubtle),
          ],
        ),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: GoogleFonts.josefinSans(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: AppColors.charcoal,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  body,
                  style: AppTypography.textTheme.bodySmall?.copyWith(
                    color: AppColors.textSecondary,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _OwnerControlTile extends StatelessWidget {
  const _OwnerControlTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: color.withValues(alpha: 0.055),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Row(
            children: [
              Icon(icon, size: 18, color: color),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: GoogleFonts.josefinSans(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: color,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.josefinSans(
                        fontSize: 11.5,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              if (onTap != null)
                const Icon(
                  Icons.chevron_right_rounded,
                  color: AppColors.textTertiary,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _VisibilityToggle extends StatelessWidget {
  const _VisibilityToggle({required this.isPublic, required this.onToggle});
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
                  style: GoogleFonts.josefinSans(fontSize: 11, color: color),
                ),
              ],
            ),
          ),
          Switch.adaptive(
            value: isPublic,
            onChanged: onToggle,
            // match the profile menu switch so public/private is legible in both states
            activeThumbColor: AppColors.white,
            activeTrackColor: AppColors.fernGreen,
            inactiveThumbColor: AppColors.white,
            inactiveTrackColor: AppColors.textTertiary,
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
            context.l('@{username} has set their profile to private.', {
              'username': username,
            }),
            style: AppTypography.textTheme.bodySmall,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            statusText,
            style: AppTypography.textTheme.labelMedium?.copyWith(
              color: AppColors.textSecondary,
            ),
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
              const Icon(
                Icons.chevron_right,
                size: 16,
                color: AppColors.fernGreen,
              ),
          ],
        ),
      ),
    );
  }
}

// profile tab widgets
// placed outside the state class

class _ProfileTabBodyStack extends StatelessWidget {
  const _ProfileTabBodyStack({
    required this.selectedIndex,
    required this.profileId,
    required this.children,
  });

  final int selectedIndex;
  final String profileId;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return AnimatedSize(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      alignment: Alignment.topCenter,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          for (var i = 0; i < children.length; i++)
            Offstage(
              offstage: i != selectedIndex,
              child: TickerMode(
                enabled: i == selectedIndex,
                child: KeyedSubtree(
                  key: PageStorageKey<String>('profile-tab-$profileId-$i'),
                  // visited tabs stay alive but only the selected tab takes space
                  // this keeps replies and media from refetching on every tap
                  child: AnimatedOpacity(
                    duration: const Duration(milliseconds: 150),
                    curve: Curves.easeOutCubic,
                    opacity: i == selectedIndex ? 1 : 0,
                    child: children[i],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _EchoesTab extends StatelessWidget {
  const _EchoesTab({required this.echoes});
  final List<EchoEntity> echoes;

  @override
  Widget build(BuildContext context) {
    if (echoes.isEmpty) {
      return _ProfileEmptyStateBody(
        storageKey: 'profile-empty-echoes',
        icon: Icons.record_voice_over_outlined,
        title: context.l('No echoes yet.'),
        message: context.l('Published echoes will appear here.'),
      );
    }

    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
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
  const _RepliesTab({required this.userId, required this.onEmptyChanged});
  final String userId;
  final ValueChanged<bool> onEmptyChanged;

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
          .select(
            'id, content, created_at, '
            'echoes!inner(id, title), '
            'users_public!inner(username, avatar_url)',
          )
          .eq('user_id', widget.userId)
          .order('created_at', ascending: false)
          .limit(30);

      setState(() {
        _replies = List<Map<String, dynamic>>.from(rows as List);
        _isLoading = false;
      });
      widget.onEmptyChanged(_replies.isEmpty);
    } catch (e) {
      setState(() => _isLoading = false);
      widget.onEmptyChanged(true);
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(
          strokeWidth: 2,
          color: AppColors.fernGreen,
        ),
      );
    }

    if (_replies.isEmpty) {
      return _ProfileEmptyStateBody(
        storageKey: 'profile-empty-replies',
        icon: Icons.chat_bubble_outline_rounded,
        title: context.l('No replies yet.'),
        message: context.l('Replies to other echoes will appear here.'),
      );
    }

    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.only(top: 8, bottom: 80),
      itemCount: _replies.length,
      itemBuilder: (ctx, i) {
        final r = _replies[i];
        final echo = r['echoes'] as Map<String, dynamic>? ?? {};
        final content = r['content'] as String? ?? '';
        final created =
            DateTime.tryParse(r['created_at'] as String? ?? '') ??
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
                // context for the echo this replies to
                Row(
                  children: [
                    const Icon(
                      Icons.reply_rounded,
                      size: 12,
                      color: AppColors.textTertiary,
                    ),
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
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOutCubic,
      builder: (context, value, child) {
        return Opacity(
          opacity: value,
          child: Transform.translate(
            offset: Offset(0, (1 - value) * 10),
            child: child,
          ),
        );
      },
      child: LayoutBuilder(
        builder: (context, constraints) {
          final tightHeight =
              constraints.hasBoundedHeight && constraints.maxHeight < 180;
          final veryTight =
              constraints.hasBoundedHeight && constraints.maxHeight < 110;
          final iconSize = tightHeight ? 44.0 : 58.0;
          final iconGlyph = tightHeight ? 22.0 : 27.0;

          return Center(
            child: Padding(
              padding: EdgeInsets.symmetric(
                horizontal: AppSpacing.xl,
                vertical: tightHeight ? AppSpacing.sm : AppSpacing.xl,
              ),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 360),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (!veryTight) ...[
                        Container(
                          width: iconSize,
                          height: iconSize,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: AppColors.fernGreenLight.withValues(
                              alpha: 0.62,
                            ),
                            border: Border.all(
                              color: AppColors.fernGreen.withValues(
                                alpha: 0.14,
                              ),
                            ),
                          ),
                          child: Icon(
                            icon,
                            size: iconGlyph,
                            color: AppColors.fernGreen,
                          ),
                        ),
                        SizedBox(height: tightHeight ? 8 : AppSpacing.md),
                      ],
                      Text(
                        context.l(title),
                        textAlign: TextAlign.center,
                        style: AppTypography.textTheme.titleSmall,
                      ),
                      if (!veryTight) ...[
                        const SizedBox(height: 6),
                        Text(
                          context.l(message),
                          textAlign: TextAlign.center,
                          style: AppTypography.textTheme.bodySmall?.copyWith(
                            color: AppColors.textTertiary,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _ProfileEmptyStateBody extends StatelessWidget {
  const _ProfileEmptyStateBody({
    required this.storageKey,
    required this.icon,
    required this.title,
    required this.message,
  });

  final String storageKey;
  final IconData icon;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    final height = (MediaQuery.sizeOf(context).height * 0.30)
        .clamp(210.0, 300.0)
        .toDouble();
    return KeyedSubtree(
      key: PageStorageKey<String>(storageKey),
      child: ColoredBox(
        color: AppColors.white,
        child: Align(
          alignment: Alignment.topCenter,
          // empty profile tabs are states not feeds
          // no inner scrollable means the profile header can move but the tab cannot drift
          child: SizedBox(
            height: height,
            child: _ProfileEmptyTab(icon: icon, title: title, message: message),
          ),
        ),
      ),
    );
  }
}

class _LockedProfileTab extends StatelessWidget {
  const _LockedProfileTab({required this.username});
  final String username;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: (MediaQuery.sizeOf(context).height * 0.34)
          .clamp(240.0, 360.0)
          .toDouble(),
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
                context.l('@{username} is private', {'username': username}),
                style: AppTypography.textTheme.titleSmall,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 6),
              Text(
                context.l(
                  'Accepted followers can view echoes, replies, media, followers, and following.',
                ),
                style: AppTypography.textTheme.bodySmall?.copyWith(
                  color: AppColors.textSecondary,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MediaTab extends StatefulWidget {
  const _MediaTab({required this.userId, required this.onEmptyChanged});
  final String userId;
  final ValueChanged<bool> onEmptyChanged;

  @override
  State<_MediaTab> createState() => _MediaTabState();
}

class _MediaTabState extends State<_MediaTab>
    with AutomaticKeepAliveClientMixin {
  List<_ProfileMediaItem> _mediaItems = [];
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
      // echoes that have a non-empty media list
      final rows = await client
          .from('echoes')
          .select('id, title, media_urls, created_at')
          .eq('user_id', widget.userId)
          .not('media_urls', 'eq', '{}')
          .not('status', 'in', '("hidden","rejected")')
          .order('created_at', ascending: false)
          .limit(30);

      final echoes = List<Map<String, dynamic>>.from(rows as List);
      final items = <_ProfileMediaItem>[];
      for (final echo in echoes) {
        final echoId = echo['id'] as String? ?? '';
        if (echoId.isEmpty) continue;
        final title = echo['title'] as String? ?? '';
        for (final url in _mediaUrls(echo['media_urls'])) {
          items.add(_ProfileMediaItem(echoId: echoId, title: title, url: url));
        }
      }

      setState(() {
        _mediaItems = items;
        _isLoading = false;
      });
      widget.onEmptyChanged(_mediaItems.isEmpty);
    } catch (e) {
      setState(() => _isLoading = false);
      widget.onEmptyChanged(true);
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(
          strokeWidth: 2,
          color: AppColors.fernGreen,
        ),
      );
    }

    if (_mediaItems.isEmpty) {
      return _ProfileEmptyStateBody(
        storageKey: 'profile-empty-media',
        icon: Icons.photo_library_outlined,
        title: context.l('No media yet.'),
        message: context.l('Echoes with photos or videos will appear here.'),
      );
    }

    final imageUrls = _mediaItems
        .where((item) => !_looksLikeVideo(item.url))
        .map((item) => item.url)
        .toList();

    // three-column media grid
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(2, 2, 2, 96),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 2,
        mainAxisSpacing: 2,
      ),
      itemCount: _mediaItems.length,
      itemBuilder: (ctx, i) {
        final item = _mediaItems[i];
        final isVideo = _looksLikeVideo(item.url);
        final imageIndex = isVideo
            ? -1
            : imageUrls.indexWhere((url) => url == item.url);

        return GestureDetector(
          onTap: () {
            if (isVideo || imageIndex < 0) {
              ctx.push('/feed/echo/${item.echoId}');
              return;
            }
            ImageViewer.show(ctx, urls: imageUrls, initialIndex: imageIndex);
          },
          child: isVideo
              ? _ProfileVideoTile(title: item.title)
              : CachedNetworkImage(
                  imageUrl: item.url,
                  cacheKey: item.url,
                  fit: BoxFit.cover,
                  placeholder: (context, url) => Container(
                    color: AppColors.softSand,
                    child: const Center(
                      child: SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: AppColors.fernGreen,
                        ),
                      ),
                    ),
                  ),
                  errorWidget: (context, error, stackTrace) => Container(
                    color: AppColors.softSand,
                    child: const Icon(
                      Icons.broken_image_outlined,
                      color: AppColors.textTertiary,
                    ),
                  ),
                ),
        );
      },
    );
  }

  List<String> _mediaUrls(Object? value) {
    if (value is List) {
      return value
          .whereType<String>()
          .where((url) => url.trim().isNotEmpty)
          .toList();
    }
    if (value is String && value.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(value);
        if (decoded is List) {
          return decoded
              .whereType<String>()
              .where((url) => url.trim().isNotEmpty)
              .toList();
        }
      } catch (_) {
        return [value];
      }
    }
    return const [];
  }

  bool _looksLikeVideo(String url) {
    final lower = url.toLowerCase();
    return lower.contains('.mp4') ||
        lower.contains('.mov') ||
        lower.contains('.webm') ||
        lower.contains('.m4v');
  }
}

class _ProfileMediaItem {
  const _ProfileMediaItem({
    required this.echoId,
    required this.title,
    required this.url,
  });

  final String echoId;
  final String title;
  final String url;
}

class _ProfileVideoTile extends StatelessWidget {
  const _ProfileVideoTile({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.softSand,
      child: Stack(
        alignment: Alignment.center,
        children: [
          const Icon(
            Icons.play_circle_fill_rounded,
            color: AppColors.fernGreen,
            size: 32,
          ),
          if (title.trim().isNotEmpty)
            Positioned(
              left: 6,
              right: 6,
              bottom: 6,
              child: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTypography.textTheme.labelSmall?.copyWith(
                  color: AppColors.charcoal,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _FollowUsersTab extends StatefulWidget {
  const _FollowUsersTab({
    required this.mode,
    required this.isOwner,
    required this.ownerId,
    required this.expectedCount,
    required this.loadUsers,
  });

  final String mode;
  final bool isOwner;
  final String ownerId;
  final int expectedCount;
  final Future<List<Map<String, dynamic>>> Function() loadUsers;

  @override
  State<_FollowUsersTab> createState() => _FollowUsersTabState();
}

class _FollowUsersTabState extends State<_FollowUsersTab>
    with AutomaticKeepAliveClientMixin {
  late Future<List<Map<String, dynamic>>> _future;
  final TextEditingController _searchCtrl = TextEditingController();
  final Set<String> _busyUserIds = {};
  String _query = '';

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _future = widget.expectedCount == 0
        ? Future<List<Map<String, dynamic>>>.value(const [])
        : _loadUsers();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    final next = _loadUsers();
    setState(() => _future = next);
    try {
      await next;
    } catch (_) {}
  }

  Future<List<Map<String, dynamic>>> _loadUsers() {
    return widget.loadUsers().timeout(const Duration(seconds: 12));
  }

  Future<bool> _confirmAction({
    required String title,
    required String message,
    required String actionLabel,
  }) async {
    return await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: Text(context.l(title)),
            content: Text(context.l(message)),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: Text(context.l('Cancel')),
              ),
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: Text(context.l(actionLabel)),
              ),
            ],
          ),
        ) ??
        false;
  }

  Future<void> _removeFollower(Map<String, dynamic> user) async {
    final userId = user['id'] as String?;
    if (userId == null || _busyUserIds.contains(userId)) return;

    final confirmed = await _confirmAction(
      title: 'Remove follower?',
      message: 'They will no longer see private profile updates.',
      actionLabel: 'Remove',
    );
    if (!confirmed || !mounted) return;

    setState(() => _busyUserIds.add(userId));
    try {
      await Supabase.instance.client.rpc(
        'remove_profile_follower',
        params: {'p_follower_id': userId},
      );
      if (mounted) showInfoSnack(context, context.l('Follower removed'));
      await _refresh();
    } catch (e) {
      if (mounted) {
        showErrorSnack(context, context.l('Could not remove follower'));
      }
    } finally {
      if (mounted) setState(() => _busyUserIds.remove(userId));
    }
  }

  Future<void> _unfollow(Map<String, dynamic> user) async {
    final userId = user['id'] as String?;
    if (userId == null || _busyUserIds.contains(userId)) return;

    final confirmed = await _confirmAction(
      title: 'Unfollow account?',
      message: 'Their public echoes will no longer be prioritized for you.',
      actionLabel: 'Unfollow',
    );
    if (!confirmed || !mounted) return;

    setState(() => _busyUserIds.add(userId));
    try {
      await Supabase.instance.client
          .from('user_follows')
          .delete()
          .eq('follower_id', widget.ownerId)
          .eq('following_id', userId);
      if (mounted) showInfoSnack(context, context.l('Unfollowed'));
      await _refresh();
    } catch (e) {
      if (mounted) showErrorSnack(context, context.l('Could not unfollow'));
    } finally {
      if (mounted) setState(() => _busyUserIds.remove(userId));
    }
  }

  Future<void> _followBack(Map<String, dynamic> user) async {
    final userId = user['id'] as String?;
    if (userId == null || _busyUserIds.contains(userId)) return;

    setState(() => _busyUserIds.add(userId));
    try {
      final client = Supabase.instance.client;
      final isPublic = user['is_public'] as bool? ?? true;
      if (isPublic) {
        await client.from('user_follows').upsert({
          'follower_id': widget.ownerId,
          'following_id': userId,
        }, onConflict: 'follower_id,following_id');
        unawaited(
          _notifyProfileSocialEvent('new_follower', {'target_id': userId}),
        );
        if (mounted) showSuccessSnack(context, context.l('Followed back'));
      } else {
        final row = await client
            .from('follow_requests')
            .upsert({
              'requester_id': widget.ownerId,
              'target_id': userId,
              'status': 'pending',
            }, onConflict: 'requester_id,target_id')
            .select('id')
            .single();
        final requestId = row['id'] as String?;
        if (requestId != null) {
          unawaited(
            _notifyProfileSocialEvent('follow_request', {
              'request_id': requestId,
            }),
          );
        }
        if (mounted) showSuccessSnack(context, context.l('Request sent'));
      }
      await _refresh();
    } catch (e) {
      if (mounted) showErrorSnack(context, context.l('Could not follow back'));
    } finally {
      if (mounted) setState(() => _busyUserIds.remove(userId));
    }
  }

  bool _canManageUser(Map<String, dynamic> user) {
    final userId = user['id'] as String?;
    return widget.isOwner && userId != null && userId != widget.ownerId;
  }

  List<PopupMenuEntry<_FollowOwnerAction>> _ownerMenuItems(
    BuildContext context,
    Map<String, dynamic> user,
  ) {
    final userId = user['id'] as String?;
    final busy = _busyUserIds.contains(userId);
    final isFollowing = user['viewer_is_following'] as bool? ?? false;
    final items = <PopupMenuEntry<_FollowOwnerAction>>[];

    if (widget.mode == 'followers') {
      if (!isFollowing) {
        items.add(
          PopupMenuItem<_FollowOwnerAction>(
            value: _FollowOwnerAction.followBack,
            enabled: !busy,
            child: _FollowMenuRow(
              icon: Icons.person_add_alt_1_rounded,
              label: context.l('Follow back'),
            ),
          ),
        );
      }
      items.add(
        PopupMenuItem<_FollowOwnerAction>(
          value: _FollowOwnerAction.removeFollower,
          enabled: !busy,
          child: _FollowMenuRow(
            icon: Icons.person_remove_alt_1_outlined,
            label: context.l('Remove follower'),
            muted: true,
          ),
        ),
      );
    } else {
      items.add(
        PopupMenuItem<_FollowOwnerAction>(
          value: _FollowOwnerAction.unfollow,
          enabled: !busy,
          child: _FollowMenuRow(
            icon: Icons.person_remove_alt_1_outlined,
            label: context.l('Unfollow'),
            muted: true,
          ),
        ),
      );
    }

    return items;
  }

  Future<void> _handleOwnerAction(
    _FollowOwnerAction action,
    Map<String, dynamic> user,
  ) async {
    switch (action) {
      case _FollowOwnerAction.removeFollower:
        await _removeFollower(user);
      case _FollowOwnerAction.followBack:
        await _followBack(user);
      case _FollowOwnerAction.unfollow:
        await _unfollow(user);
    }
  }

  Widget _trailingFor(Map<String, dynamic> user) {
    final userId = user['id'] as String?;
    final busy = userId != null && _busyUserIds.contains(userId);
    if (!_canManageUser(user)) {
      return const Icon(
        Icons.chevron_right_rounded,
        color: AppColors.textTertiary,
      );
    }

    if (busy) {
      return const SizedBox(
        width: 22,
        height: 22,
        child: CircularProgressIndicator(
          strokeWidth: 2,
          color: AppColors.fernGreen,
        ),
      );
    }

    return PopupMenuButton<_FollowOwnerAction>(
      tooltip: context.l('Account actions'),
      icon: const Icon(
        Icons.more_horiz_rounded,
        color: AppColors.textSecondary,
      ),
      onSelected: (action) => unawaited(_handleOwnerAction(action, user)),
      itemBuilder: (context) => _ownerMenuItems(context, user),
    );
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
        final query = _query.trim().toLowerCase();
        final visibleUsers = query.isEmpty
            ? users
            : users.where((user) {
                final username = (user['username'] as String? ?? '')
                    .toLowerCase();
                final displayName = (user['display_name'] as String? ?? '')
                    .toLowerCase();
                return username.contains(query) || displayName.contains(query);
              }).toList();

        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: AppColors.fernGreen,
            ),
          );
        }
        if (snapshot.hasError) {
          return Center(
            child: _ProfileEmptyTab(
              icon: Icons.wifi_off_rounded,
              title: context.l('Could not load list.'),
              message: context.l(
                'Check your connection and try again from this screen.',
              ),
            ),
          );
        }
        if (users.isEmpty) {
          return Center(
            child: _ProfileEmptyTab(
              icon: Icons.people_alt_outlined,
              title: title,
              message: message,
            ),
          );
        }
        return RefreshIndicator(
          color: AppColors.fernGreen,
          onRefresh: _refresh,
          child: ListView.builder(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              AppSpacing.md,
              AppSpacing.lg,
              96,
            ),
            itemCount: visibleUsers.isEmpty ? 2 : visibleUsers.length + 1,
            itemBuilder: (context, index) {
              if (index == 0) {
                return _FollowSearchField(
                  controller: _searchCtrl,
                  onChanged: (value) => setState(() => _query = value),
                );
              }

              if (visibleUsers.isEmpty) {
                return SizedBox(
                  height: MediaQuery.sizeOf(context).height * 0.35,
                  child: _ProfileEmptyTab(
                    icon: Icons.search_off_rounded,
                    title: context.l('No matching accounts.'),
                    message: context.l('Try another name or username.'),
                  ),
                );
              }

              final user = visibleUsers[index - 1];
              final username = user['username'] as String? ?? '';
              final displayName =
                  (user['display_name'] as String?)?.trim().isNotEmpty == true
                  ? user['display_name'] as String
                  : username;
              final avatarUrl = user['avatar_url'] as String?;
              final isPro = user['is_pro'] as bool? ?? false;
              final image = avatarImageProvider(avatarUrl);

              return Container(
                decoration: const BoxDecoration(
                  border: Border(
                    bottom: BorderSide(color: AppColors.borderSubtle),
                  ),
                ),
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: CircleAvatar(
                    backgroundColor: AppColors.softSand,
                    backgroundImage: image,
                    child: image == null
                        ? const Icon(
                            Icons.person_outline,
                            color: AppColors.textTertiary,
                          )
                        : null,
                  ),
                  title: Row(
                    children: [
                      Flexible(
                        child: Text(
                          displayName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTypography.textTheme.titleSmall,
                        ),
                      ),
                      if (isPro) ...[
                        const SizedBox(width: 5),
                        const AccountVerifiedBadge(size: 14),
                      ],
                    ],
                  ),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '@$username',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.josefinSans(
                          fontSize: 12,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                  trailing: _trailingFor(user),
                  onTap: username.isEmpty
                      ? null
                      : () => context.push(
                          '/profile/${Uri.encodeComponent(username)}',
                        ),
                ),
              );
            },
          ),
        );
      },
    );
  }
}

enum _FollowOwnerAction { removeFollower, followBack, unfollow }

class _FollowMenuRow extends StatelessWidget {
  const _FollowMenuRow({
    required this.icon,
    required this.label,
    this.muted = false,
  });

  final IconData icon;
  final String label;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    final color = muted ? AppColors.textSecondary : AppColors.fernGreenDark;

    return Row(
      children: [
        Icon(icon, size: 18, color: color),
        const SizedBox(width: AppSpacing.sm),
        Text(
          label,
          style: AppTypography.textTheme.bodyMedium?.copyWith(color: color),
        ),
      ],
    );
  }
}

class _FollowSearchField extends StatelessWidget {
  const _FollowSearchField({required this.controller, required this.onChanged});

  final TextEditingController controller;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: TextField(
        controller: controller,
        onChanged: onChanged,
        textInputAction: TextInputAction.search,
        decoration: InputDecoration(
          hintText: context.l('Search'),
          prefixIcon: const Icon(Icons.search_rounded),
          filled: true,
          fillColor: AppColors.white,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: 12,
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: AppColors.borderSubtle),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: AppColors.borderSubtle),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: AppColors.fernGreen),
          ),
        ),
      ),
    );
  }
}
