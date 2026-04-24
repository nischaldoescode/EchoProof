// typography — Josefin Sans throughout
// loaded from Google Fonts package — no asset files needed

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

abstract final class AppTypography {
  static const fontFamily = 'Josefin Sans';

  static TextTheme get textTheme {
    return GoogleFonts.josefinSansTextTheme(
      const TextTheme(
        displayLarge: TextStyle(
            fontSize: 57, fontWeight: FontWeight.w700, letterSpacing: -1.5),
        displayMedium: TextStyle(
            fontSize: 45, fontWeight: FontWeight.w600, letterSpacing: -1.0),
        displaySmall: TextStyle(
            fontSize: 36, fontWeight: FontWeight.w600, letterSpacing: -0.5),
        headlineLarge: TextStyle(
            fontSize: 32, fontWeight: FontWeight.w600, letterSpacing: -0.5),
        headlineMedium: TextStyle(
            fontSize: 28, fontWeight: FontWeight.w600, letterSpacing: -0.3),
        headlineSmall: TextStyle(
            fontSize: 24, fontWeight: FontWeight.w600, letterSpacing: -0.2),
        titleLarge: TextStyle(
            fontSize: 20, fontWeight: FontWeight.w600, letterSpacing: 0),
        titleMedium: TextStyle(
            fontSize: 16, fontWeight: FontWeight.w600, letterSpacing: 0),
        titleSmall: TextStyle(
            fontSize: 14, fontWeight: FontWeight.w600, letterSpacing: 0.1),
        bodyLarge: TextStyle(
            fontSize: 16, fontWeight: FontWeight.w400, letterSpacing: 0.15),
        bodyMedium: TextStyle(
            fontSize: 14, fontWeight: FontWeight.w400, letterSpacing: 0.25),
        bodySmall: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w400,
            letterSpacing: 0.4,
            height: 1.5),
        labelLarge: TextStyle(
            fontSize: 12, fontWeight: FontWeight.w500, letterSpacing: 0.5),
        labelMedium: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w500,
            letterSpacing: 0.4,
            color: Color(0xFF7A7A7A)),
        labelSmall: TextStyle(
            fontSize: 10, fontWeight: FontWeight.w500, letterSpacing: 0.5),
      ),
    );
  }

  // use this when you need a TextStyle outside of the theme
  static TextStyle josefin({
    double size = 14,
    FontWeight weight = FontWeight.w400,
    Color? color,
    double? height,
    double letterSpacing = 0,
  }) {
    return GoogleFonts.josefinSans(
      fontSize: size,
      fontWeight: weight,
      color: color,
      height: height,
      letterSpacing: letterSpacing,
    );
  }
}
