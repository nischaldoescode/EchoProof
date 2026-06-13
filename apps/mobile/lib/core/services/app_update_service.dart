// app update guard
// @params reason force

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hyper_snackbar/hyper_snackbar.dart';
import 'package:in_app_update/in_app_update.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app/theme/colors.dart';
import '../utils/app_haptics.dart';
import '../utils/logger.dart';

enum AppUpdateCheckReason { launch, resume, retry }

class AppUpdateService {
  static const _packageName = 'com.echoproof.app';
  static const _checkTimeout = Duration(seconds: 7);
  static const _checkCooldown = Duration(seconds: 25);
  static const _nativeFlowCooldown = Duration(seconds: 16);

  bool _checking = false;
  bool _sheetOpen = false;
  DateTime? _lastCheckAt;
  DateTime? _nativeFlowStartedAt;

  Future<void> checkForRequiredUpdate({
    required AppUpdateCheckReason reason,
    bool force = false,
  }) async {
    if (!_supportsPlayUpdates) return;
    if (_checking || _sheetOpen) {
      AppLogger.info('app update: skipped because guard is already visible');
      return;
    }

    final now = DateTime.now();
    final lastCheckAt = _lastCheckAt;
    final nativeFlowStartedAt = _nativeFlowStartedAt;
    if (!force &&
        lastCheckAt != null &&
        now.difference(lastCheckAt) < _checkCooldown) {
      AppLogger.info('app update: skipped by cooldown reason=${reason.name}');
      return;
    }
    if (nativeFlowStartedAt != null &&
        now.difference(nativeFlowStartedAt) < _nativeFlowCooldown) {
      AppLogger.info('app update: skipped after native flow');
      return;
    }

    _checking = true;
    _lastCheckAt = now;
    try {
      final info = await InAppUpdate.checkForUpdate().timeout(_checkTimeout);
      AppLogger.info(
        'app update: check reason=${reason.name} '
        'availability=${info.updateAvailability.name} '
        'status=${info.installStatus.name} '
        'immediate=${info.immediateUpdateAllowed} '
        'flexible=${info.flexibleUpdateAllowed} '
        'version=${info.availableVersionCode} '
        'priority=${info.updatePriority} '
        'staleDays=${info.clientVersionStalenessDays}',
      );

      if (!_needsUpdate(info)) return;

      if (info.immediateUpdateAllowed ||
          info.updateAvailability ==
              UpdateAvailability.developerTriggeredUpdateInProgress) {
        await _runImmediateUpdate(info, reason);
        return;
      }

      await _showRequiredUpdateSheet(info, reason: reason);
    } on TimeoutException {
      AppLogger.warn('app update: check timed out reason=${reason.name}');
    } on PlatformException catch (e) {
      AppLogger.warn('app update: play check unavailable ${e.code}');
    } catch (e, stack) {
      AppLogger.error('app update: check failed', e, stack);
    } finally {
      _checking = false;
    }
  }

  bool get _supportsPlayUpdates {
    return !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
  }

  bool _needsUpdate(AppUpdateInfo info) {
    return info.updateAvailability == UpdateAvailability.updateAvailable ||
        info.updateAvailability ==
            UpdateAvailability.developerTriggeredUpdateInProgress ||
        info.installStatus == InstallStatus.downloaded;
  }

  Future<void> _runImmediateUpdate(
    AppUpdateInfo info,
    AppUpdateCheckReason reason,
  ) async {
    _nativeFlowStartedAt = DateTime.now();
    try {
      final result = await InAppUpdate.performImmediateUpdate();
      AppLogger.info(
        'app update: immediate result=${result.name} reason=${reason.name}',
      );
      if (result != AppUpdateResult.success) {
        await _showRequiredUpdateSheet(
          info,
          reason: reason,
          lastResult: result,
        );
      }
    } on PlatformException catch (e) {
      AppLogger.warn('app update: immediate failed ${e.code}');
      await _showRequiredUpdateSheet(info, reason: reason);
    }
  }

  Future<void> _showRequiredUpdateSheet(
    AppUpdateInfo info, {
    required AppUpdateCheckReason reason,
    AppUpdateResult? lastResult,
  }) async {
    if (_sheetOpen) return;
    final context = HyperSnackbar.navigatorKey.currentContext;
    if (context == null || !context.mounted) {
      AppLogger.warn('app update: no context for update sheet');
      return;
    }

    final packageInfo = await _packageInfo();
    if (!context.mounted) return;

    _sheetOpen = true;
    try {
      unawaited(AppHaptics.criticalOpen(key: 'required_update_sheet'));
      await showModalBottomSheet<void>(
        context: context,
        useRootNavigator: true,
        isDismissible: false,
        enableDrag: false,
        isScrollControlled: true,
        useSafeArea: true,
        backgroundColor: Colors.transparent,
        barrierColor: Colors.black.withValues(alpha: 0.28),
        builder: (_) => _UpdateRequiredSheet(
          info: info,
          reason: reason,
          packageInfo: packageInfo,
          lastResult: lastResult,
          onUpdate: () => _startBestAvailableUpdate(info),
        ),
      );
    } finally {
      _sheetOpen = false;
    }
  }

  Future<PackageInfo?> _packageInfo() async {
    try {
      return PackageInfo.fromPlatform();
    } catch (e) {
      AppLogger.warn('app update: package info unavailable $e');
      return null;
    }
  }

  Future<String?> _startBestAvailableUpdate(AppUpdateInfo info) async {
    try {
      if (info.installStatus == InstallStatus.downloaded) {
        await InAppUpdate.completeFlexibleUpdate();
        return 'Google Play is installing the update';
      }

      if (info.immediateUpdateAllowed ||
          info.updateAvailability ==
              UpdateAvailability.developerTriggeredUpdateInProgress) {
        _nativeFlowStartedAt = DateTime.now();
        final result = await InAppUpdate.performImmediateUpdate();
        if (result == AppUpdateResult.success) {
          return 'Google Play accepted the update';
        }
        if (result == AppUpdateResult.userDeniedUpdate) {
          return 'The update window was closed, please update to continue';
        }
        return 'Google Play could not start the update, try again';
      }

      if (info.flexibleUpdateAllowed) {
        final result = await InAppUpdate.startFlexibleUpdate();
        if (result == AppUpdateResult.success) {
          await InAppUpdate.completeFlexibleUpdate();
          return 'Google Play is installing the update';
        }
        if (result == AppUpdateResult.userDeniedUpdate) {
          return 'The update was cancelled, please update to continue';
        }
        return 'Google Play could not download the update, try again';
      }

      final opened = await _openPlayStore();
      if (opened) {
        return 'Play Store opened, install the update and return here';
      }
      return 'Could not open Play Store, search EchoProof manually';
    } on PlatformException catch (e) {
      AppLogger.warn('app update: start failed ${e.code}');
      final opened = await _openPlayStore();
      if (opened) {
        return 'Play Store opened, install the update and return here';
      }
      return 'Google Play could not start the update, try again';
    } catch (e, stack) {
      AppLogger.error('app update: update flow failed', e, stack);
      return 'Something interrupted the update, try again';
    }
  }

  Future<bool> _openPlayStore() async {
    final marketUri = Uri.parse('market://details?id=$_packageName');
    final webUri = Uri.parse(
      'https://play.google.com/store/apps/details?id=$_packageName',
    );
    try {
      if (await launchUrl(marketUri, mode: LaunchMode.externalApplication)) {
        return true;
      }
    } catch (e) {
      AppLogger.warn('app update: market link failed $e');
    }
    try {
      return launchUrl(webUri, mode: LaunchMode.externalApplication);
    } catch (e) {
      AppLogger.warn('app update: web store link failed $e');
      return false;
    }
  }
}

class _UpdateRequiredSheet extends StatefulWidget {
  const _UpdateRequiredSheet({
    required this.info,
    required this.reason,
    required this.onUpdate,
    this.packageInfo,
    this.lastResult,
  });

  final AppUpdateInfo info;
  final AppUpdateCheckReason reason;
  final PackageInfo? packageInfo;
  final AppUpdateResult? lastResult;
  final Future<String?> Function() onUpdate;

  @override
  State<_UpdateRequiredSheet> createState() => _UpdateRequiredSheetState();
}

class _UpdateRequiredSheetState extends State<_UpdateRequiredSheet>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse;
  bool _busy = false;
  String? _message;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);
    _message = _initialMessage();
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  String? _initialMessage() {
    if (widget.lastResult == AppUpdateResult.userDeniedUpdate) {
      return 'The update window was closed';
    }
    if (widget.lastResult == AppUpdateResult.inAppUpdateFailed) {
      return 'Google Play could not start the update';
    }
    if (widget.info.flexibleUpdateAllowed &&
        !widget.info.immediateUpdateAllowed) {
      return 'Google Play will download this update before installing it';
    }
    return null;
  }

  Future<void> _handleUpdate() async {
    if (_busy) return;
    unawaited(AppHaptics.criticalConfirm(key: 'required_update_confirm'));
    setState(() {
      _busy = true;
      _message = 'Opening Google Play update';
    });
    final message = await widget.onUpdate();
    if (!mounted) return;
    setState(() {
      _busy = false;
      _message = message;
    });
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final packageInfo = widget.packageInfo;
    final currentVersion = packageInfo == null
        ? 'current build'
        : '${packageInfo.version}+${packageInfo.buildNumber}';
    final availableVersion = widget.info.availableVersionCode == null
        ? 'new build'
        : 'build ${widget.info.availableVersionCode}';

    return PopScope(
      canPop: false,
      child: Padding(
        padding: EdgeInsets.only(
          left: 14,
          right: 14,
          bottom: media.viewInsets.bottom + 14,
        ),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: AppColors.white,
            borderRadius: BorderRadius.circular(28),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.16),
                blurRadius: 34,
                offset: const Offset(0, 18),
              ),
            ],
          ),
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(22, 12, 22, 22),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: Container(
                      width: 42,
                      height: 4,
                      decoration: BoxDecoration(
                        color: AppColors.borderMedium,
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      AnimatedBuilder(
                        animation: _pulse,
                        builder: (context, child) {
                          final value = 0.94 + (_pulse.value * 0.08);
                          return Transform.scale(scale: value, child: child);
                        },
                        child: Container(
                          width: 58,
                          height: 58,
                          decoration: const BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [Color(0xFFE8F5EE), Color(0xFFCFEBDD)],
                            ),
                          ),
                          child: const Icon(
                            Icons.system_update_alt_rounded,
                            color: AppColors.fernGreenDark,
                            size: 28,
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'A newer EchoProof is ready',
                              style: TextStyle(
                                color: AppColors.textPrimary,
                                fontSize: 20,
                                fontWeight: FontWeight.w800,
                                height: 1.15,
                              ),
                            ),
                            SizedBox(height: 8),
                            Text(
                              'Update from Google Play to keep feed, rooms, and payments working cleanly',
                              style: TextStyle(
                                color: AppColors.textSecondary,
                                fontSize: 14,
                                height: 1.45,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  DecoratedBox(
                    decoration: BoxDecoration(
                      color: AppColors.surfaceSecondary,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: AppColors.borderSubtle),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.verified_user_outlined,
                            color: AppColors.fernGreenDark,
                            size: 20,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              '$currentVersion  to  $availableVersion',
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: AppColors.textSecondary,
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (_message != null) ...[
                    const SizedBox(height: 12),
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 220),
                      child: Text(
                        _message!,
                        key: ValueKey(_message),
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: AppColors.fernGreenDark,
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 18),
                  SizedBox(
                    height: 52,
                    child: FilledButton(
                      onPressed: _busy ? null : _handleUpdate,
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.fernGreenDark,
                        foregroundColor: AppColors.white,
                        disabledBackgroundColor: AppColors.fernGreenDark
                            .withValues(alpha: 0.55),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 180),
                        child: _busy
                            ? const SizedBox(
                                key: ValueKey('busy'),
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.4,
                                  color: AppColors.white,
                                ),
                              )
                            : const Text(
                                'Update now',
                                key: ValueKey('idle'),
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
