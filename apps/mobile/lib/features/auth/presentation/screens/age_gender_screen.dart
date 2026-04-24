// age and gender collection screen
// shown after OTP verification, before permissions
// age used for content moderation — under 13 blocked
// gender used for personalization — optional

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../../../app/theme/colors.dart';
import '../../../../app/theme/spacing.dart';
import '../services/auth_service.dart';

class AgeGenderScreen extends StatefulWidget {
  const AgeGenderScreen({super.key, this.email = ''});
  final String email;

  @override
  State<AgeGenderScreen> createState() => _AgeGenderScreenState();
}

class _AgeGenderScreenState extends State<AgeGenderScreen>
    with SingleTickerProviderStateMixin {
  int? _age;
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

  Future<void> _continue() async {
    if (_age == null) return;

    // under 13 — block access
    if (_age! < 13) {
      _showUnderageDialog();
      return;
    }

    setState(() => _isSubmitting = true);

    await context.read<AuthService>().saveAgeAndGender(
          age: _age!,
          gender: _gender ?? 'prefer_not_to_say',
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
          'Age requirement',
          style: GoogleFonts.josefinSans(fontWeight: FontWeight.w700),
        ),
        content: Text(
          'Echoproof requires users to be at least 13 years old. We cannot create an account for you at this time.',
          style: GoogleFonts.josefinSans(fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              context.go('/login');
            },
            child: Text(
              'Understood',
              style: GoogleFonts.josefinSans(color: AppColors.fernGreen),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5FAF7),
      body: SafeArea(
        child: FadeTransition(
          opacity: _fade,
          child: SlideTransition(
            position: _slide,
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.xl),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: AppSpacing.xl),

                  // step indicator
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

                  // icon
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
                    'Quick profile setup',
                    style: GoogleFonts.josefinSans(
                      fontSize: 26,
                      fontWeight: FontWeight.w700,
                      color: AppColors.charcoal,
                      letterSpacing: -0.3,
                    ),
                  ),

                  const SizedBox(height: AppSpacing.sm),

                  Text(
                    'This helps us keep Echoproof safe and relevant. None of this is public.',
                    style: GoogleFonts.josefinSans(
                      fontSize: 14,
                      color: AppColors.textSecondary,
                      height: 1.5,
                    ),
                  ),

                  const SizedBox(height: AppSpacing.xxl),

                  // age input
                  Text(
                    'Your age',
                    style: GoogleFonts.josefinSans(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: AppColors.charcoal,
                    ),
                  ),

                  const SizedBox(height: AppSpacing.sm),

                  _AgeInput(
                    onChanged: (v) => setState(() => _age = v),
                  ),

                  if (_age != null && _age! < 13)
                    Padding(
                      padding: const EdgeInsets.only(top: AppSpacing.sm),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.warning_amber_rounded,
                            size: 14,
                            color: AppColors.sunsetCoral,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            'Must be at least 13 to use Echoproof',
                            style: GoogleFonts.josefinSans(
                              fontSize: 12,
                              color: AppColors.sunsetCoral,
                            ),
                          ),
                        ],
                      ),
                    ),

                  const SizedBox(height: AppSpacing.xl),

                  // gender selection
                  Text(
                    'Gender',
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
                            color: selected ? AppColors.charcoal : Colors.white,
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
                              Text(
                                g.label,
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
                            ],
                          ),
                        ),
                      );
                    }).toList(),
                  ),

                  const Spacer(),

                  // continue button
                  AnimatedOpacity(
                    opacity: _age != null ? 1.0 : 0.4,
                    duration: const Duration(milliseconds: 200),
                    child: SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed:
                            (_age != null && !_isSubmitting) ? _continue : null,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.charcoal,
                          padding: const EdgeInsets.symmetric(vertical: 16),
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
                                'Continue',
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
          ),
        ),
      ),
    );
  }
}

class _AgeInput extends StatefulWidget {
  const _AgeInput({required this.onChanged});
  final void Function(int?) onChanged;

  @override
  State<_AgeInput> createState() => _AgeInputState();
}

class _AgeInputState extends State<_AgeInput> {
  final _controller = TextEditingController();
  bool _focused = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      onFocusChange: (v) => setState(() => _focused = v),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        decoration: BoxDecoration(
          color: _focused ? Colors.white : const Color(0xFFF0F4F2),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: _focused ? AppColors.fernGreen : AppColors.borderSubtle,
            width: _focused ? 2 : 1,
          ),
          boxShadow: _focused
              ? [
                  BoxShadow(
                    color: AppColors.fernGreen.withValues(alpha: 0.1),
                    blurRadius: 12,
                    offset: const Offset(0, 3),
                  ),
                ]
              : [],
        ),
        child: TextField(
          controller: _controller,
          keyboardType: TextInputType.number,
          inputFormatters: [
            FilteringTextInputFormatter.digitsOnly,
            LengthLimitingTextInputFormatter(3),
          ],
          onChanged: (v) {
            final age = int.tryParse(v);
            widget.onChanged(age);
          },
          decoration: InputDecoration(
            hintText: 'Enter your age',
            hintStyle: GoogleFonts.josefinSans(
              fontSize: 14,
              color: AppColors.textTertiary,
            ),
            prefixIcon: Icon(
              Icons.cake_outlined,
              size: 18,
              color: _focused ? AppColors.fernGreen : AppColors.textTertiary,
            ),
            border: InputBorder.none,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 14,
            ),
          ),
          style: GoogleFonts.josefinSans(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            color: AppColors.charcoal,
          ),
        ),
      ),
    );
  }
}
