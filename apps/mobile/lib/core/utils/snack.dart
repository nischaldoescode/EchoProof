import 'package:flutter/material.dart';
import 'package:hyper_snackbar/hyper_snackbar.dart';

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

  final myBrandPreset = HyperSnackbar.preset(
  backgroundColor: Colors.deepPurple,
  icon: Icon(Icons.star, color: Colors.amber),
  borderRadius: 16,
  animationType: HyperSnackAnimationType.scale, // Sets both enter & exit
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
