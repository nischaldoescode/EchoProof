import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../app/theme/colors.dart';

/// Shows a snackbar correctly positioned above the bottom nav on any device.
void showAppSnack(
  BuildContext context,
  String message, {
  Color backgroundColor = AppColors.fernGreen,
  Duration duration = const Duration(seconds: 3),
}) {
  final bottomPadding = MediaQuery.of(context).padding.bottom + 68;
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(
        message,
        style: GoogleFonts.josefinSans(fontSize: 13),
      ),
      backgroundColor: backgroundColor,
      behavior: SnackBarBehavior.floating,
      margin: EdgeInsets.only(
        bottom: bottomPadding,
        left: 16,
        right: 16,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
      ),
      duration: duration,
    ),
  );
}