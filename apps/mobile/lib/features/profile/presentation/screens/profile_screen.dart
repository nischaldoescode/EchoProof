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
import '../widgets/reputation_card.dart';
import '../../../settings/presentation/widgets/solana_info_card.dart';
import 'package:flutter/foundation.dart';
import '../../../../core/security/secure_screen.dart';
import '../../../../shared/widgets/app_bottom_nav.dart';
import '../../../../app/app.dart';

import 'package:flutter_svg/flutter_svg.dart';

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

  late final AnimationController _entranceCtrl;
  late final Animation<double> _fade;
  late final Animation<Offset> _slide;
  late final TabController _tabCtrl;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 3, vsync: this);
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
    _tabCtrl.dispose();
    _entranceCtrl.dispose();
    super.dispose();
  }

  bool _isSavingProfile = false;

  Future<void> _showEditProfileSheet() async {
    final client = Supabase.instance.client;
    final currentUsername = _profile?['username'] as String? ?? '';
    final currentDisplay = _profile?['display_name'] as String? ?? '';

    final usernameCtrl = TextEditingController(text: currentUsername);
    final displayCtrl = TextEditingController(text: currentDisplay);
    bool usernameAvailable = true;
    bool isCheckingUsername = false;
    String? usernameError;

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
            return Padding(
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
                  Text(
                    'Edit profile',
                    style: AppTypography.textTheme.titleMedium,
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    'Username changes require email verification.',
                    style: AppTypography.textTheme.bodySmall,
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  Text(
                    'Display name',
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
                      hintText: 'Your display name',
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
                  Text(
                    'Username',
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
                      hintText: 'username',
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
                    onChanged: (v) async {
                      setSheet(() {
                        isCheckingUsername = true;
                        usernameError = null;
                      });
                      await Future.delayed(const Duration(milliseconds: 500));
                      if (!ctx.mounted) return;
                      if (v.length < 3) {
                        setSheet(() {
                          isCheckingUsername = false;
                          usernameAvailable = false;
                          usernameError = 'At least 3 characters';
                        });
                        return;
                      }
                      final available =
                          await checkUsernameAvailability(v.toLowerCase());
                      setSheet(() {
                        isCheckingUsername = false;
                        usernameAvailable = available;
                        usernameError =
                            available ? null : 'Username already taken';
                      });
                    },
                  ),
                  const SizedBox(height: AppSpacing.xl),
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
                        'Save changes',
                        style: GoogleFonts.josefinSans(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xl),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _saveProfileChanges({
    required String newUsername,
    required String newDisplayName,
    required String currentUsername,
  }) async {
    // Username changed — require OTP re-verification before saving.
    final usernameChanged = newUsername != currentUsername;

    if (usernameChanged) {
      final email = Supabase.instance.client.auth.currentUser?.email;
      if (email == null) return;

      setState(() => _isSavingProfile = true);

      try {
        await Supabase.instance.client.auth.signInWithOtp(
          email: email,
          shouldCreateUser: false,
        );
      } catch (e) {
        AppLogger.error('profile: OTP send failed $e');
        setState(() => _isSavingProfile = false);
        return;
      }

      if (!mounted) return;

      // Show OTP dialog inline.
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

      await client.from('users_public').update({
        'username': newUsername,
        'display_name':
            newDisplayName.isNotEmpty ? newDisplayName : newUsername,
      }).eq('id', userId);

      setState(() {
        _profile = {
          ..._profile!,
          'username': newUsername,
          'display_name': newDisplayName,
        };
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Profile updated.',
              style: GoogleFonts.josefinSans(fontSize: 13),
            ),
            backgroundColor: AppColors.fernGreen,
            behavior: SnackBarBehavior.floating,
            margin: const EdgeInsets.only(bottom: 88, left: 16, right: 16),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        );
      }
    } catch (e) {
      AppLogger.error('profile: save changes failed $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Failed to save changes. Please try again.',
              style: GoogleFonts.josefinSans(fontSize: 13),
            ),
            backgroundColor: AppColors.sunsetCoral,
            behavior: SnackBarBehavior.floating,
            margin: const EdgeInsets.only(bottom: 88, left: 16, right: 16),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        );
      }
    }

    setState(() => _isSavingProfile = false);
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
                'Verify your email',
                style: GoogleFonts.josefinSans(fontWeight: FontWeight.w700),
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'A verification code was sent to $email. Enter it to confirm the username change.',
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
                  child: Text('Cancel',
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
                          'Verify',
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
              'echo_count, proof_count, is_public, bio',
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
              'echo_count, proof_count, is_public, bio',
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
      _isPublic = profile['is_public'] as bool? ?? true;

      if (!_isOwnProfile && !_isPublic) {
        setState(() {
          _profile = profile;
          _isLoading = false;
        });
        _entranceCtrl.forward();
        return;
      }

      final results = await Future.wait<dynamic>([
        client
            .from('echoes')
            .select(
              'id, title, content, category, status, trust_score, '
              'confidence_score, controversy_score, support_count, '
              'challenge_count, created_at',
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
              .select('is_identity_verified')
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
          userTrustTier: profile['trust_tier'] as String? ?? 'unverified',
          userIsVerified: priv?['is_identity_verified'] as bool? ?? false,
          userAvatarUrl: profile['avatar_url'] as String?,
          category: EchoCategory.fromString(r['category'] as String),
          status: _parseStatus(r['status'] as String),
          confidenceScore: (r['confidence_score'] as num?)?.toDouble() ?? 0,
          trustScore: (r['trust_score'] as num?)?.toInt() ?? 0,
          controversyScore: (r['controversy_score'] as num?)?.toDouble() ?? 0,
          supportCount: (r['support_count'] as num?)?.toInt() ?? 0,
          challengeCount: (r['challenge_count'] as num?)?.toInt() ?? 0,
          timeAgo: Formatters.timeAgo(created),
        );
      }).toList();

      setState(() {
        _profile = profile;
        _echoes = echoEntities;
        _settledBonds =
            bonds.where((b) => b['bond_status'] == 'settled').length;
        _contestedBonds =
            bonds.where((b) => b['bond_status'] == 'contested').length;
        _activeBonds = bonds.where((b) => b['bond_status'] == 'active').length;
        _isIdentityVerified = priv?['is_identity_verified'] as bool? ?? false;
        _isLoading = false;
      });
      _entranceCtrl.forward();
    } catch (e) {
      AppLogger.error('profile: load failed $e');
      setState(() => _isLoading = false);
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Failed to update bio',
              style: GoogleFonts.josefinSans(fontSize: 13),
            ),
            backgroundColor: AppColors.sunsetCoral,
            behavior: SnackBarBehavior.floating,
            margin: const EdgeInsets.only(bottom: 88, left: 16, right: 16),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        );
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
            Text('Edit bio', style: AppTypography.textTheme.titleMedium),
            const SizedBox(height: AppSpacing.xs),
            Text(
              'Visible on your public profile.',
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
                hintText: 'Write something about yourself...',
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
                  'Save bio',
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
      return const Padding(
        padding: EdgeInsets.all(AppSpacing.xl),
        child: EchoCardShimmer(),
      );
    }

    if (_profile == null) {
      return Center(
        child: Text(
          'Could not load profile',
          style: AppTypography.textTheme.bodyMedium,
        ),
      );
    }

    return FadeTransition(
      opacity: _fade,
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
                        onEditBio: _showEditBioSheet,
                      ),
                      const SizedBox(height: AppSpacing.md),
                      if (_isOwnProfile)
                        _VisibilityToggle(
                          isPublic: _isPublic,
                          onToggle: _setPublic,
                        ),
                      if (!_isOwnProfile && !_isPublic)
                        _PrivateProfileNotice(
                          username: _profile!['username'] as String,
                        ),
                      const SizedBox(height: AppSpacing.md),
                      ReputationCard(
                        username: _profile!['username'] as String? ?? '',
                        trustTier:
                            _profile!['trust_tier'] as String? ?? 'unverified',
                        trustScore:
                            (_profile!['trust_score'] as num?)?.toInt() ?? 0,
                        echoCount:
                            (_profile!['echo_count'] as num?)?.toInt() ?? 0,
                        proofCount:
                            (_profile!['proof_count'] as num?)?.toInt() ?? 0,
                        isIdentityVerified: _isIdentityVerified,
                        settledBonds: _settledBonds,
                        contestedBonds: _contestedBonds,
                        activeBonds: _activeBonds,
                        avatarUrl: _profile!['avatar_url'] as String?,
                        walletAddress: _profile!['wallet_address'] as String?,
                      ),
                      const SizedBox(height: AppSpacing.lg),
                      if (_isOwnProfile && !_isIdentityVerified)
                        _VerifyPrompt(),
                      const SizedBox(height: AppSpacing.lg),
                      const SolanaInfoCard(),
                      const SizedBox(height: AppSpacing.lg),
                    ],
                  ),
                ),
              ),
              SliverPersistentHeader(
                pinned: true,
                delegate: _TabBarDelegate(
                  TabBar(
                    controller: _tabCtrl,
                    tabs: const [
                      Tab(text: 'Echoes'),
                      Tab(text: 'Replies'),
                      Tab(text: 'Media'),
                    ],
                  ),
                ),
              ),
            ],
            body: TabBarView(
              controller: _tabCtrl,
              children: [
                _EchoesTab(echoes: _echoes),
                _RepliesTab(userId: _profile!['id']),
                _MediaTab(userId: _profile!['id']),
              ],
            ),
          ),
        ),
      ),
    );
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
    return SwipeNavigationWrapper(
        currentLocation: '/profile',
        child: ExitConfirmWrapper(
            child: Scaffold(
          backgroundColor: const Color(0xFFF5FAF7),
          appBar: AppBar(
            backgroundColor: Colors.white,
            elevation: 0,
            scrolledUnderElevation: 0.5,
            shadowColor: AppColors.borderSubtle,
            title: Text(
              _profile != null ? '@${_profile!['username']}' : 'Profile',
              style: AppTypography.textTheme.titleLarge,
            ),
            actions: [
              if (_isOwnProfile) ...[
                IconButton(
                  icon: const Icon(Icons.edit_outlined, size: 20),
                  onPressed: () => _showEditProfileSheet(),
                  color: AppColors.charcoal,
                  tooltip: 'Edit profile',
                ),
                IconButton(
                  icon: const Icon(Icons.settings_outlined, size: 22),
                  onPressed: () => context.push('/settings'),
                  color: AppColors.charcoal,
                  tooltip: 'Settings',
                ),
              ],
              const SizedBox(width: 4),
            ],
          ),
          bottomNavigationBar: const AppBottomNav(currentLocation: '/profile'),
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

class _AvatarCard extends StatelessWidget {
  const _AvatarCard({
    required this.profile,
    required this.isIdentityVerified,
    required this.isOwnProfile,
    required this.onEditBio,
  });

  final Map<String, dynamic> profile;
  final bool isIdentityVerified;
  final bool isOwnProfile;
  final VoidCallback onEditBio;

  @override
  Widget build(BuildContext context) {
    final avatarUrl = profile['avatar_url'] as String?;
    final username = profile['username'] as String? ?? '';
    final displayName = profile['display_name'] as String? ?? '';
    final bio = profile['bio'] as String?;
    final hasBio = bio != null && bio.isNotEmpty;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.xl),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.borderSubtle),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // avatar with verified badge
          Stack(
            children: [
              GestureDetector(
                onTap:
                    isOwnProfile || (avatarUrl != null && avatarUrl.isNotEmpty)
                        ? () => _showAvatarZoom(context, avatarUrl)
                        : null,
                child: CircleAvatar(
                  radius: 36,
                  backgroundColor: AppColors.softSand,
                  child: ClipOval(
                    child: (avatarUrl != null && avatarUrl.isNotEmpty)
                        ? avatarUrl.endsWith('.svg')
                            ? SvgPicture.network(
                                avatarUrl,
                                width: 72,
                                height: 72,
                                fit: BoxFit.cover,
                                placeholderBuilder: (_) => const Icon(
                                  Icons.person_outline,
                                  size: 28,
                                  color: AppColors.textTertiary,
                                ),
                              )
                            : Image.network(
                                avatarUrl,
                                width: 72,
                                height: 72,
                                fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) => const Icon(
                                  Icons.person_outline,
                                  size: 28,
                                  color: AppColors.textTertiary,
                                ),
                              )
                        : const Icon(
                            Icons.person_outline,
                            size: 28,
                            color: AppColors.textTertiary,
                          ),
                  ),
                ),
              ),
              if (isIdentityVerified)
                Positioned(
                  right: 0,
                  bottom: 0,
                  child: Container(
                    width: 20,
                    height: 20,
                    decoration: const BoxDecoration(
                      color: AppColors.fernGreen,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.verified,
                      size: 13,
                      color: Colors.white,
                    ),
                  ),
                ),
            ],
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
                // bio text or placeholder
                if (hasBio) ...[
                  const SizedBox(height: 6),
                  Text(
                    bio!,
                    style: GoogleFonts.josefinSans(
                      fontSize: 13,
                      color: AppColors.textSecondary,
                      height: 1.5,
                    ),
                  ),
                ] else if (isOwnProfile) ...[
                  const SizedBox(height: 6),
                  Text(
                    'No bio yet.',
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
                          hasBio ? 'Edit bio' : 'Add bio',
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
    );
  }

  static void _showAvatarZoom(BuildContext context, String? avatarUrl) {
    if (avatarUrl == null || avatarUrl.isEmpty) return;
    showDialog(
      context: context,
      barrierColor: Colors.black87,
      builder: (_) => GestureDetector(
        onTap: () => Navigator.pop(context),
        child: Dialog(
          backgroundColor: Colors.transparent,
          elevation: 0,
          insetPadding: const EdgeInsets.all(24),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: avatarUrl.endsWith('.svg')
                ? SvgPicture.network(
                    avatarUrl,
                    fit: BoxFit.contain,
                  )
                : Image.network(
                    avatarUrl,
                    fit: BoxFit.contain,
                  ),
          ),
        ),
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
                  isPublic ? 'Public profile' : 'Private profile',
                  style: GoogleFonts.josefinSans(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: color,
                  ),
                ),
                Text(
                  isPublic
                      ? 'Anyone can see your echoes'
                      : 'Only you can see your echoes',
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
            activeColor: AppColors.fernGreen,
          ),
        ],
      ),
    );
  }
}

class _PrivateProfileNotice extends StatelessWidget {
  const _PrivateProfileNotice({required this.username});
  final String username;

  @override
  Widget build(BuildContext context) {
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
            'This account is private',
            style: AppTypography.textTheme.titleMedium,
          ),
          const SizedBox(height: 4),
          Text(
            '@$username has set their profile to private.',
            style: AppTypography.textTheme.bodySmall,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class _VerifyPrompt extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => context.push('/verify-identity'),
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: AppColors.fernGreenLight,
          borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
          border: Border.all(
            color: AppColors.fernGreen.withValues(alpha: 0.3),
          ),
        ),
        child: Row(
          children: [
            const Icon(
              Icons.shield_outlined,
              size: 18,
              color: AppColors.fernGreen,
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text(
                'Verify your identity to increase your trust weight',
                style: GoogleFonts.josefinSans(
                  fontSize: 13,
                  color: AppColors.fernGreenDark,
                ),
              ),
            ),
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

// add these at the bottom of profile_screen.dart
// outside _ProfileScreenState, as top-level widget classes

class _EchoesTab extends StatelessWidget {
  const _EchoesTab({required this.echoes});
  final List<EchoEntity> echoes;

  @override
  Widget build(BuildContext context) {
    if (echoes.isEmpty) {
      return SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: SizedBox(
          height: 300,
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.record_voice_over_outlined,
                    size: 48, color: AppColors.textTertiary),
                const SizedBox(height: AppSpacing.md),
                Text('No echoes yet.',
                    style: AppTypography.textTheme.bodyMedium
                        ?.copyWith(color: AppColors.textSecondary)),
              ],
            ),
          ),
        ),
      );
    }

    return ListView.builder(
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
      return SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xxl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.chat_bubble_outline_rounded,
                  size: 48, color: AppColors.textTertiary),
              const SizedBox(height: AppSpacing.md),
              Text('No replies yet.',
                  style: AppTypography.textTheme.bodyMedium
                      ?.copyWith(color: AppColors.textSecondary)),
            ],
          ),
        ),
      );
    }

    return ListView.builder(
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
                        'Replying to "$echoTitle"',
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
                Text(content,
                    style: AppTypography.textTheme.bodyMedium,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis),
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
      return SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xxl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.photo_library_outlined,
                  size: 48, color: AppColors.textTertiary),
              const SizedBox(height: AppSpacing.md),
              Text('No media yet.',
                  style: AppTypography.textTheme.bodyMedium
                      ?.copyWith(color: AppColors.textSecondary)),
            ],
          ),
        ),
      );
    }

    // Twitter-style 3-column grid
    return GridView.builder(
      padding: const EdgeInsets.all(2),
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
