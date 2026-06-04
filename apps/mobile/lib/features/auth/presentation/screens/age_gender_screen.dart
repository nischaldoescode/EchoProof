// age and gender collection screen
// shown after otp verification, before /permissions
// collects date of birth (not raw age) and optional gender
// calculates age from dob to enforce 13+ gate

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../../../app/theme/colors.dart';
import '../../../../app/theme/spacing.dart';
import '../../../../core/localization/app_copy.dart';
import '../../../../core/utils/logger.dart';
import '../../../../core/utils/snack.dart';
import '../services/auth_service.dart';

class AgeGenderScreen extends StatefulWidget {
  const AgeGenderScreen({super.key, this.email = ''});
  final String email;

  @override
  State<AgeGenderScreen> createState() => _AgeGenderScreenState();
}

class _AgeGenderScreenState extends State<AgeGenderScreen>
    with SingleTickerProviderStateMixin {
  // dob replaces raw age input
  DateTime? _dob;
  String? _gender;
  bool _isSubmitting = false;

  late final AnimationController _entranceController;
  late final Animation<double> _fade;
  late final Animation<Offset> _slide;

  static const _genders = [
    (value: 'male', label: 'Male', icon: Icons.male_rounded),
    (value: 'female', label: 'Female', icon: Icons.female_rounded),
    (value: 'non_binary', label: 'Non-binary', icon: Icons.transgender_rounded),
    (
      value: 'prefer_not_to_say',
      label: 'Prefer not to say',
      icon: Icons.person_outline_rounded
    ),
  ];

  @override
  void initState() {
    super.initState();
    _entranceController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _fade = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _entranceController, curve: Curves.easeOut),
    );
    _slide = Tween<Offset>(
      begin: const Offset(0, 0.1),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(parent: _entranceController, curve: Curves.easeOutCubic),
    );
    _entranceController.forward();
  }

  @override
  void dispose() {
    _entranceController.dispose();
    super.dispose();
  }

  // calculates age in whole years from dob to today
  int? get _calculatedAge {
    if (_dob == null) return null;
    final today = DateTime.now();
    int age = today.year - _dob!.year;
    if (today.month < _dob!.month ||
        (today.month == _dob!.month && today.day < _dob!.day)) {
      age--;
    }
    return age;
  }

  Future<bool> _onWillPop() async {
    final keyboardOpen =
        (MediaQuery.maybeOf(context)?.viewInsets.bottom ?? 0) > 0;
    AppLogger.info(
        'age-gender: system back received keyboardOpen=$keyboardOpen');
    if (keyboardOpen) {
      FocusManager.instance.primaryFocus?.unfocus();
      AppLogger.info('age-gender: keyboard dismissed by back');
      return false;
    }

    AppLogger.info('age-gender: opening cancel setup dialog');
    final shouldLeave = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          context.l('Cancel account setup?'),
          style: GoogleFonts.josefinSans(fontWeight: FontWeight.w700),
        ),
        content: Text(
          context.l(
            'If you leave now, your account setup will not be complete. You will need to start again next time.',
          ),
          style: GoogleFonts.josefinSans(fontSize: 14, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(
              context.l('Stay'),
              style: GoogleFonts.josefinSans(color: AppColors.fernGreen),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(
              foregroundColor: AppColors.sunsetCoral,
            ),
            child: Text(
              context.l('Leave'),
              style: GoogleFonts.josefinSans(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );

    AppLogger.info('age-gender: cancel setup dialog result=$shouldLeave');
    if (shouldLeave == true && mounted) {
      await context.read<AuthService>().deleteIncompleteAccount();
      if (mounted) context.go('/login');
    }
    return false;
  }

  // opens the platform date picker restricts to valid birth date range
  Future<void> _pickDob() async {
    AppLogger.info('age-gender: dob tap received submitting=$_isSubmitting');
    if (_isSubmitting) {
      AppLogger.info('age-gender: dob tap ignored while submitting');
      return;
    }

    HapticFeedback.selectionClick();
    final now = DateTime.now();
    // oldest allowed: 120 years ago; youngest allowed: 13 years ago
    final firstDate = DateTime(now.year - 120, now.month, now.day);
    final lastDate = DateTime(now.year - 13, now.month, now.day);

    try {
      final initialDate = _dob ?? DateTime(now.year - 18, now.month, now.day);
      AppLogger.info(
        'age-gender: opening dob picker initial=$initialDate first=$firstDate last=$lastDate',
      );

      final picked = await _showDobPickerSheet(
        context: context,
        initialDate: initialDate,
        firstDate: firstDate,
        lastDate: lastDate,
      );

      if (picked != null) {
        AppLogger.info('age-gender: dob selected $picked');
        setState(() => _dob = picked);
      } else {
        AppLogger.info('age-gender: dob picker dismissed without selection');
      }
    } catch (e, stack) {
      AppLogger.error('age-gender: dob picker failed', e, stack);
      if (!mounted) return;
      showInfoSnack(
        context,
        context.l('Could not open date picker. Try again.'),
      );
    }
  }

  Future<DateTime?> _showDobPickerSheet({
    required BuildContext context,
    required DateTime initialDate,
    required DateTime firstDate,
    required DateTime lastDate,
  }) {
    var selected = initialDate;

    return showModalBottomSheet<DateTime>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return SafeArea(
              top: false,
              child: Container(
                margin: const EdgeInsets.all(AppSpacing.md),
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.lg,
                  AppSpacing.lg,
                  AppSpacing.lg,
                  AppSpacing.md,
                ),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.charcoal.withValues(alpha: 0.14),
                      blurRadius: 24,
                      offset: const Offset(0, 12),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Text(
                          context.l('Date of birth'),
                          style: GoogleFonts.josefinSans(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            color: AppColors.charcoal,
                          ),
                        ),
                        const Spacer(),
                        IconButton(
                          tooltip: context.l('Close'),
                          onPressed: () {
                            AppLogger.info(
                              'age-gender: dob picker close tapped',
                            );
                            Navigator.pop(sheetContext);
                          },
                          icon: const Icon(Icons.close_rounded),
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Theme(
                      data: Theme.of(context).copyWith(
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
                      child: CalendarDatePicker(
                        initialDate: selected,
                        firstDate: firstDate,
                        lastDate: lastDate,
                        onDateChanged: (value) {
                          AppLogger.info(
                              'age-gender: dob calendar changed $value');
                          setSheetState(() => selected = value);
                        },
                      ),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Row(
                      children: [
                        Expanded(
                          child: TextButton(
                            onPressed: () {
                              AppLogger.info(
                                'age-gender: dob picker cancel tapped',
                              );
                              Navigator.pop(sheetContext);
                            },
                            child: Text(
                              context.l('Cancel'),
                              style: GoogleFonts.josefinSans(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        Expanded(
                          child: ElevatedButton(
                            onPressed: () {
                              AppLogger.info(
                                'age-gender: dob picker done tapped selected=$selected',
                              );
                              Navigator.pop(sheetContext, selected);
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.charcoal,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                            ),
                            child: Text(
                              context.l('Done'),
                              style: GoogleFonts.josefinSans(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _continue() async {
    if (_dob == null) return;

    final age = _calculatedAge!;

    // redundant safety check date picker enforces lastdate already,
    // but we guard here in case of edge case clock skew
    if (age < 13) {
      _showUnderageDialog();
      return;
    }

    setState(() => _isSubmitting = true);

    await context.read<AuthService>().saveAgeAndGender(
          age: age,
          gender: _gender ?? 'prefer_not_to_say',
          dateOfBirth: _dob!,
        );

    if (!mounted) return;
    context.go('/permissions');
  }

  void _showUnderageDialog() {
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        title: Text(
          context.l('Age requirement'),
          style: GoogleFonts.josefinSans(fontWeight: FontWeight.w700),
        ),
        content: Text(
          context.l(
            'Echoproof requires users to be at least 13 years old. We cannot create an account for you at this time.',
          ),
          style: GoogleFonts.josefinSans(fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              await context.read<AuthService>().deleteIncompleteAccount();
              if (mounted) context.go('/login');
            },
            child: Text(
              context.l('Understood'),
              style: GoogleFonts.josefinSans(color: AppColors.fernGreen),
            ),
          ),
        ],
      ),
    );
  }

  // formats the selected dob for display
  String _formatDob(DateTime dob) {
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
    return '${dob.day} ${months[dob.month - 1]} ${dob.year}';
  }

  @override
  Widget build(BuildContext context) {
    final age = _calculatedAge;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (!didPop) await _onWillPop();
      },
      child: Scaffold(
        backgroundColor: const Color(0xFFF5FAF7),
        body: SafeArea(
          child: FadeTransition(
            opacity: _fade,
            child: SlideTransition(
              position: _slide,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final minHeight = constraints.maxHeight > AppSpacing.xl * 2
                      ? constraints.maxHeight - AppSpacing.xl * 2
                      : 0.0;

                  return SingleChildScrollView(
                    keyboardDismissBehavior:
                        ScrollViewKeyboardDismissBehavior.onDrag,
                    padding: const EdgeInsets.all(AppSpacing.xl),
                    child: ConstrainedBox(
                      constraints: BoxConstraints(minHeight: minHeight),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const SizedBox(height: AppSpacing.xl),

                          // step progress dots step 1 of 3
                          Row(
                            children: List.generate(3, (i) {
                              return AnimatedContainer(
                                duration: const Duration(milliseconds: 300),
                                margin: const EdgeInsets.only(right: 6),
                                width: i == 0 ? 24 : 8,
                                height: 8,
                                decoration: BoxDecoration(
                                  color: i == 0
                                      ? AppColors.charcoal
                                      : AppColors.borderMedium,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                              );
                            }),
                          ),

                          const SizedBox(height: AppSpacing.xxl),

                          // icon badge
                          TweenAnimationBuilder<double>(
                            tween: Tween(begin: 0, end: 1),
                            duration: const Duration(milliseconds: 500),
                            curve: Curves.easeOutBack,
                            builder: (_, v, __) => Transform.scale(
                              scale: v,
                              child: Container(
                                width: 64,
                                height: 64,
                                decoration: BoxDecoration(
                                  color: AppColors.fernGreenLight,
                                  borderRadius: BorderRadius.circular(18),
                                ),
                                child: const Icon(
                                  Icons.person_outline_rounded,
                                  size: 32,
                                  color: AppColors.fernGreen,
                                ),
                              ),
                            ),
                          ),

                          const SizedBox(height: AppSpacing.xl),

                          Text(
                            context.l('Quick profile setup'),
                            style: GoogleFonts.josefinSans(
                              fontSize: 26,
                              fontWeight: FontWeight.w700,
                              color: AppColors.charcoal,
                              letterSpacing: -0.3,
                            ),
                          ),

                          const SizedBox(height: AppSpacing.sm),

                          Text(
                            context.l(
                              'This helps us keep Echoproof safe and relevant. None of this is public.',
                            ),
                            style: GoogleFonts.josefinSans(
                              fontSize: 14,
                              color: AppColors.textSecondary,
                              height: 1.5,
                            ),
                          ),

                          const SizedBox(height: AppSpacing.xxl),

                          // date of birth label
                          Text(
                            context.l('Date of birth'),
                            style: GoogleFonts.josefinSans(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: AppColors.charcoal,
                            ),
                          ),

                          const SizedBox(height: AppSpacing.sm),

                          // dob picker tap target
                          Semantics(
                            button: true,
                            label: context.l('Select your date of birth'),
                            child: Material(
                              color: Colors.transparent,
                              borderRadius: BorderRadius.circular(14),
                              child: InkWell(
                                onTap: _isSubmitting ? null : _pickDob,
                                borderRadius: BorderRadius.circular(14),
                                child: AnimatedContainer(
                                  duration: const Duration(milliseconds: 200),
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(14),
                                    border: Border.all(
                                      color: _dob != null
                                          ? AppColors.fernGreen
                                          : AppColors.borderSubtle,
                                      width: _dob != null ? 2 : 1,
                                    ),
                                    boxShadow: [
                                      BoxShadow(
                                        color: (_dob != null
                                                ? AppColors.fernGreen
                                                : AppColors.charcoal)
                                            .withValues(
                                                alpha:
                                                    _dob != null ? 0.1 : 0.04),
                                        blurRadius: _dob != null ? 12 : 8,
                                        offset: const Offset(0, 3),
                                      ),
                                    ],
                                  ),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                    vertical: 14,
                                  ),
                                  child: Row(
                                    children: [
                                      Icon(
                                        Icons.calendar_month_rounded,
                                        size: 19,
                                        color: _dob != null
                                            ? AppColors.fernGreen
                                            : AppColors.textSecondary,
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Text(
                                          _dob != null
                                              ? _formatDob(_dob!)
                                              : context.l(
                                                  'Select your date of birth'),
                                          style: GoogleFonts.josefinSans(
                                            fontSize: _dob != null ? 15 : 14,
                                            fontWeight: _dob != null
                                                ? FontWeight.w600
                                                : FontWeight.w500,
                                            color: _dob != null
                                                ? AppColors.charcoal
                                                : AppColors.textSecondary,
                                          ),
                                        ),
                                      ),
                                      // show calculated age as a soft badge once dob is selected
                                      if (age != null)
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 10,
                                            vertical: 4,
                                          ),
                                          decoration: BoxDecoration(
                                            color: AppColors.fernGreenLight,
                                            borderRadius:
                                                BorderRadius.circular(20),
                                          ),
                                          child: Text(
                                            context
                                                .l('{age} yrs', {'age': age}),
                                            style: GoogleFonts.josefinSans(
                                              fontSize: 12,
                                              fontWeight: FontWeight.w600,
                                              color: AppColors.fernGreenDark,
                                            ),
                                          ),
                                        ),
                                      const SizedBox(width: 4),
                                      const Icon(
                                        Icons.chevron_right_rounded,
                                        size: 18,
                                        color: AppColors.textTertiary,
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),

                          const SizedBox(height: AppSpacing.xl),

                          // gender label
                          Text(
                            context.l('Gender'),
                            style: GoogleFonts.josefinSans(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: AppColors.charcoal,
                            ),
                          ),

                          const SizedBox(height: AppSpacing.sm),

                          GridView.count(
                            crossAxisCount: 2,
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            crossAxisSpacing: AppSpacing.sm,
                            mainAxisSpacing: AppSpacing.sm,
                            childAspectRatio: 2.8,
                            children: _genders.map((g) {
                              final selected = _gender == g.value;
                              return GestureDetector(
                                onTap: () {
                                  HapticFeedback.selectionClick();
                                  setState(() => _gender = g.value);
                                },
                                child: AnimatedContainer(
                                  duration: const Duration(milliseconds: 200),
                                  decoration: BoxDecoration(
                                    color: selected
                                        ? AppColors.charcoal
                                        : Colors.white,
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                      color: selected
                                          ? AppColors.charcoal
                                          : AppColors.borderSubtle,
                                      width: selected ? 2 : 1,
                                    ),
                                  ),
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(
                                        g.icon,
                                        size: 16,
                                        color: selected
                                            ? Colors.white
                                            : AppColors.textSecondary,
                                      ),
                                      const SizedBox(width: 6),
                                      Flexible(
                                        child: Text(
                                          context.l(g.label),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: GoogleFonts.josefinSans(
                                            fontSize: 13,
                                            fontWeight: selected
                                                ? FontWeight.w600
                                                : FontWeight.w400,
                                            color: selected
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

                          const SizedBox(height: AppSpacing.xxl),

                          AnimatedOpacity(
                            opacity: _dob != null ? 1.0 : 0.4,
                            duration: const Duration(milliseconds: 200),
                            child: SizedBox(
                              width: double.infinity,
                              child: ElevatedButton(
                                onPressed: (_dob != null && !_isSubmitting)
                                    ? _continue
                                    : null,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: AppColors.charcoal,
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 16),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                ),
                                child: _isSubmitting
                                    ? const SizedBox(
                                        width: 20,
                                        height: 20,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: Colors.white,
                                        ),
                                      )
                                    : Text(
                                        context.l('Continue'),
                                        style: GoogleFonts.josefinSans(
                                          fontSize: 15,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                              ),
                            ),
                          ),

                          const SizedBox(height: AppSpacing.xl),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}
