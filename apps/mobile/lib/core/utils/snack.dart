import 'package:flutter/material.dart';
import 'package:hyper_snackbar/hyper_snackbar.dart';
import '../../app/theme/colors.dart';
import '../../app/theme/spacing.dart';
import '../utils/logger.dart';
import '../services/connectivity_service.dart';

enum SnackType { success, error, warning, info }

void showAppSnack(
  BuildContext context,
  String message, {
  SnackType type = SnackType.success,
  Duration duration = const Duration(seconds: 3),
  double bottomMargin = 14,
  String? actionLabel,
  VoidCallback? onAction,
}) {
  final colors = _snackColors(type);
  final mediaQuery = MediaQuery.maybeOf(context);
  final bottomInset = mediaQuery?.viewInsets.bottom ?? 0;
  final bottomPadding = mediaQuery?.viewPadding.bottom ?? 0;
  final resolvedMargin = bottomInset + bottomPadding + bottomMargin;
  final route = ModalRoute.of(context);

  AppLogger.info(
    'snack: show request type=${type.name} route=${route?.settings.name} '
    'message="$message" bottomInset=$bottomInset '
    'bottomPadding=$bottomPadding bottomMargin=$bottomMargin '
    'resolvedBottomMargin=$resolvedMargin',
  );

  try {
    HyperSnackbar.show(
      title: _snackTitle(type),
      message: message,
      snackPosition: HyperSnackPosition.bottom,
      snackStyle: HyperSnackStyle.floating,
      displayMode: HyperSnackDisplayMode.queue,
      maxVisibleCount: 1,
      displayDuration: duration,
      backgroundColor: colors.bg,
      textColor: colors.fg,
      border: Border.all(color: colors.border),
      borderRadius: AppSpacing.radiusMd,
      margin: EdgeInsets.fromLTRB(
        14,
        0,
        14,
        resolvedMargin,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      maxWidth: 520,
      alignment: Alignment.bottomCenter,
      icon: Icon(_snackIcon(type), color: colors.icon, size: 20),
      showCloseButton: true,
      animationType: HyperSnackAnimationType.scale,
      action: actionLabel == null || onAction == null
          ? null
          : HyperSnackAction(
              label: actionLabel,
              onPressed: onAction,
            ),
    );
    AppLogger.info('snack: HyperSnackbar.show dispatched type=${type.name}');
  } catch (error, stack) {
    AppLogger.error(
      'snack: HyperSnackbar.show failed type=${type.name}',
      error,
      stack,
    );
  }
}

void showSuccessSnack(BuildContext context, String message) =>
    showAppSnack(context, message, type: SnackType.success);

void showErrorSnack(BuildContext context, String message) =>
    showAppSnack(context, message, type: SnackType.error);

void showWarningSnack(BuildContext context, String message) =>
    showAppSnack(context, message, type: SnackType.warning);

void showInfoSnack(
  BuildContext context,
  String message, {
  double bottomMargin = 14,
}) =>
    showAppSnack(
      context,
      message,
      type: SnackType.info,
      bottomMargin: bottomMargin,
    );

bool showOfflineSnackIfNeeded(
  BuildContext context, {
  String message = 'No internet connection. Try again when you are online.',
}) {
  if (ConnectivityService.instance.isOnline) return false;
  showWarningSnack(context, message);
  return true;
}

String _snackTitle(SnackType type) => switch (type) {
      SnackType.success => 'Success',
      SnackType.error => 'Error',
      SnackType.warning => 'Warning',
      SnackType.info => 'Info',
    };

IconData _snackIcon(SnackType type) => switch (type) {
      SnackType.success => Icons.check_circle_outline_rounded,
      SnackType.error => Icons.error_outline_rounded,
      SnackType.warning => Icons.warning_amber_rounded,
      SnackType.info => Icons.info_outline_rounded,
    };

({Color bg, Color fg, Color border, Color icon}) _snackColors(SnackType type) =>
    switch (type) {
      SnackType.success => (
          bg: AppColors.fernGreenDark,
          fg: AppColors.white,
          border: AppColors.fernGreen,
          icon: AppColors.white,
        ),
      SnackType.error => (
          bg: AppColors.sunsetCoralDark,
          fg: AppColors.white,
          border: AppColors.sunsetCoral,
          icon: AppColors.white,
        ),
      SnackType.warning => (
          bg: const Color(0xFF7A5200),
          fg: AppColors.white,
          border: AppColors.statusControversial,
          icon: AppColors.white,
        ),
      SnackType.info => (
          bg: AppColors.charcoal,
          fg: AppColors.white,
          border: AppColors.borderMedium,
          icon: AppColors.white,
        ),
    };
