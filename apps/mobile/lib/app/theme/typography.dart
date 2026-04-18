// echoproof typography system
// geometric, clean, minimal — inter / sf pro feel

import 'package:flutter/material.dart';
import 'colors.dart';

abstract final class AppTypography {
  static const String fontFamily = 'Inter';

  static TextTheme get textTheme => const TextTheme(
    // display — not used often, hero moments only
    displayLarge: TextStyle(
      fontSize: 40, fontWeight: FontWeight.w300,
      color: AppColors.textPrimary, letterSpacing: -1.0, height: 1.1,
    ),
    displayMedium: TextStyle(
      fontSize: 32, fontWeight: FontWeight.w300,
      color: AppColors.textPrimary, letterSpacing: -0.8, height: 1.15,
    ),

    // headings
    headlineLarge: TextStyle(
      fontSize: 26, fontWeight: FontWeight.w600,
      color: AppColors.textPrimary, letterSpacing: -0.5, height: 1.2,
    ),
    headlineMedium: TextStyle(
      fontSize: 22, fontWeight: FontWeight.w600,
      color: AppColors.textPrimary, letterSpacing: -0.4, height: 1.25,
    ),
    headlineSmall: TextStyle(
      fontSize: 18, fontWeight: FontWeight.w600,
      color: AppColors.textPrimary, letterSpacing: -0.3, height: 1.3,
    ),

    // titles — card titles, section headers
    titleLarge: TextStyle(
      fontSize: 16, fontWeight: FontWeight.w600,
      color: AppColors.textPrimary, letterSpacing: -0.2, height: 1.35,
    ),
    titleMedium: TextStyle(
      fontSize: 14, fontWeight: FontWeight.w600,
      color: AppColors.textPrimary, letterSpacing: -0.1, height: 1.4,
    ),
    titleSmall: TextStyle(
      fontSize: 13, fontWeight: FontWeight.w600,
      color: AppColors.textPrimary, letterSpacing: 0, height: 1.4,
    ),

    // body — main content
    bodyLarge: TextStyle(
      fontSize: 16, fontWeight: FontWeight.w400,
      color: AppColors.textPrimary, letterSpacing: 0, height: 1.6,
    ),
    bodyMedium: TextStyle(
      fontSize: 14, fontWeight: FontWeight.w400,
      color: AppColors.textPrimary, letterSpacing: 0, height: 1.55,
    ),
    bodySmall: TextStyle(
      fontSize: 12, fontWeight: FontWeight.w400,
      color: AppColors.textSecondary, letterSpacing: 0, height: 1.5,
    ),

    // labels — badges, chips, metadata
    labelLarge: TextStyle(
      fontSize: 13, fontWeight: FontWeight.w500,
      color: AppColors.textSecondary, letterSpacing: 0.1,
    ),
    labelMedium: TextStyle(
      fontSize: 11, fontWeight: FontWeight.w500,
      color: AppColors.textTertiary, letterSpacing: 0.3,
    ),
    labelSmall: TextStyle(
      fontSize: 10, fontWeight: FontWeight.w600,
      color: AppColors.textTertiary, letterSpacing: 0.5,
    ),
  );
}