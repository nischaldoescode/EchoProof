// reusable auth button — used on login screen for email and google options

import 'package:flutter/material.dart';
import '../../../../app/theme/colors.dart';
import '../../../../app/theme/spacing.dart';
import '../../../../app/theme/typography.dart';

class AuthButton extends StatelessWidget {
  const AuthButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.isLoading = false,
    this.isPrimary = true,
    this.icon,
  });

  final String    label;
  final VoidCallback onPressed;
  final bool      isLoading;
  final bool      isPrimary;
  final Widget?   icon;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: AnimatedOpacity(
        opacity: isLoading ? 0.7 : 1.0,
        duration: const Duration(milliseconds: 200),
        child: isPrimary
            ? ElevatedButton(
                onPressed: isLoading ? null : onPressed,
                child: isLoading
                    ? const SizedBox(
                        width: 18, height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2, color: AppColors.white,
                        ),
                      )
                    : Text(label),
              )
            : OutlinedButton.icon(
                onPressed: isLoading ? null : onPressed,
                icon: icon ?? const SizedBox.shrink(),
                label: Text(label),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.charcoal,
                  side: const BorderSide(color: AppColors.borderMedium),
                  padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                  ),
                  textStyle: TextStyle(
                    fontFamily: AppTypography.fontFamily,
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
      ),
    );
  }
}