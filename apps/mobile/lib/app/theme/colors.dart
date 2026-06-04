// echoproof color system
// matches the brand design blueprint exactly
// all colors defined as static constants never use raw hex anywhere else in the app

import 'package:flutter/material.dart';

/// primary brand colors for echoproof
/// use these constants exclusively never hardcode hex values in widgets
abstract final class AppColors {
  // primary

  /// pure white primary surface, trust signal
  static const Color white = Color(0xFFFFFFFF);

  /// rich charcoal not pure black, warmer
  static const Color charcoal = Color(0xFF1A1A1A);

  // accent

  /// fern green trust, verified, authentic
  static const Color fernGreen = Color(0xFF4CAF6E);

  /// fern green light used for verified badge backgrounds
  static const Color fernGreenLight = Color(0xFFE8F5EE);

  /// fern green dark used for text on light green backgrounds
  static const Color fernGreenDark = Color(0xFF2D7A4A);

  // supporting

  /// soft sand card backgrounds, proof containers
  static const Color softSand = Color(0xFFEAE7DF);

  /// soft sand dark border on sand backgrounds
  static const Color softSandBorder = Color(0xFFD4CFC4);

  // highlight

  /// sunset coral warnings, disputed claims, conflict
  static const Color sunsetCoral = Color(0xFFFF7759);

  /// sunset coral light background for disputed badges
  static const Color sunsetCoralLight = Color(0xFFFFF0ED);

  /// sunset coral dark text on coral backgrounds
  static const Color sunsetCoralDark = Color(0xFFB03E28);

  // neutrals

  /// border color thin strokes on cards
  static const Color borderSubtle = Color(0xFFE6E6E6);

  /// border medium slightly more visible separators
  static const Color borderMedium = Color(0xFFD0D0D0);

  /// text primary main content text
  static const Color textPrimary = Color(0xFF1A1A1A);

  /// text secondary secondary labels, captions
  static const Color textSecondary = Color(0xFF5A5A5A);

  /// text tertiary placeholder, hints
  static const Color textTertiary = Color(0xFF9A9A9A);

  /// surface secondary slightly off-white for layered surfaces
  static const Color surfaceSecondary = Color(0xFFF8F7F5);

  // echo status colors

  /// verified echo green
  static const Color statusVerified = fernGreen;

  /// disputed echo coral
  static const Color statusDisputed = sunsetCoral;

  /// controversial echo amber
  static const Color statusControversial = Color(0xFFE8A000);

  /// under review neutral amber
  static const Color statusUnderReview = Color(0xFFF5A623);

  /// pending muted gray
  static const Color statusPending = Color(0xFFAAAAAA);

  // splash screen

  /// splash background charcoal (dark)
  static const Color splashBackground = charcoal;
}
