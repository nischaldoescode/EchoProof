import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../app/theme/colors.dart';

enum SnackType { success, error, warning, info }

/// Shows a snackbar correctly positioned above the bottom nav on any device.
/// Uses dynamic safe area so it works on all screen sizes.
void showAppSnack(
  BuildContext context,
  String message, {
  SnackType type = SnackType.success,
  Duration duration = const Duration(seconds: 3),
  String? actionLabel,
  VoidCallback? onAction,
}) {
  // Dynamic bottom: safe area (home bar on iPhones, etc.) + nav bar height.
  final safeBottom = MediaQuery.of(context).padding.bottom;
  final bottomPadding = safeBottom + 68.0;

  final colors = _snackColors(type);

  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(_snackIcon(type), size: 16, color: colors.fg),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                message,
                style: GoogleFonts.josefinSans(
                  fontSize: 13,
                  color: colors.fg,
                ),
              ),
            ),
          ],
        ),
        backgroundColor: colors.bg,
        behavior: SnackBarBehavior.floating,
        margin: EdgeInsets.only(
          bottom: bottomPadding,
          left: 16,
          right: 16,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: BorderSide(color: colors.border, width: 0.5),
        ),
        duration: duration,
        action: actionLabel != null && onAction != null
            ? SnackBarAction(
                label: actionLabel,
                textColor: colors.fg,
                onPressed: onAction,
              )
            : null,
      ),
    );
}

// Convenience wrappers.
void showSuccessSnack(BuildContext context, String message) =>
    showAppSnack(context, message, type: SnackType.success);

void showErrorSnack(BuildContext context, String message) =>
    showAppSnack(context, message, type: SnackType.error);

void showWarningSnack(BuildContext context, String message) =>
    showAppSnack(context, message, type: SnackType.warning);

void showInfoSnack(BuildContext context, String message) =>
    showAppSnack(context, message, type: SnackType.info);

IconData _snackIcon(SnackType type) => switch (type) {
      SnackType.success => Icons.check_circle_outline_rounded,
      SnackType.error => Icons.error_outline_rounded,
      SnackType.warning => Icons.warning_amber_rounded,
      SnackType.info => Icons.info_outline_rounded,
    };

({Color bg, Color fg, Color border}) _snackColors(SnackType type) =>
    switch (type) {
      SnackType.success => (
          bg: const Color(0xFF1E3A2A),
          fg: Colors.white,
          border: const Color(0xFF2D6A4F),
        ),
      SnackType.error => (
          bg: const Color(0xFF3A1E1E),
          fg: Colors.white,
          border: const Color(0xFF8B3A3A),
        ),
      SnackType.warning => (
          bg: const Color(0xFF3A2E1E),
          fg: Colors.white,
          border: const Color(0xFF8B6A3A),
        ),
      SnackType.info => (
          bg: const Color(0xFF1E2A3A),
          fg: Colors.white,
          border: const Color(0xFF2D4A6A),
        ),
    };
