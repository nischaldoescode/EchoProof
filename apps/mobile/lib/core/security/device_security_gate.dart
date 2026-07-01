// device security gate
// @params none

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/theme/colors.dart';
import '../../app/theme/spacing.dart';
import 'device_security.dart';
import 'secure_screen.dart';

class DeviceSecurityGate extends StatefulWidget {
  const DeviceSecurityGate({super.key, required this.child});

  final Widget child;

  @override
  State<DeviceSecurityGate> createState() => _DeviceSecurityGateState();
}

class _DeviceSecurityGateState extends State<DeviceSecurityGate>
    with WidgetsBindingObserver {
  Timer? _timer;
  DeviceSecurityReport? _blockedReport;
  bool _checking = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _checkDevice();
    if (kReleaseMode) {
      _timer = Timer.periodic(
        const Duration(seconds: 30),
        (_) => _checkDevice(),
      );
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkDevice();
    }
  }

  Future<void> _checkDevice() async {
    if (!mounted || !kReleaseMode || _blockedReport != null || _checking) {
      return;
    }
    _checking = true;
    try {
      final report = await DeviceSecurity.inspect();
      if (!mounted) return;
      if (report.compromised) {
        setState(() => _blockedReport = report);
      }
    } finally {
      _checking = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final report = _blockedReport;
    if (report != null) {
      return MaterialApp(
        debugShowCheckedModeBanner: false,
        home: SecureScreen(child: SecurityLockdownScreen(report: report)),
      );
    }

    return widget.child;
  }
}

class SecurityLockdownScreen extends StatelessWidget {
  const SecurityLockdownScreen({super.key, this.report});

  final DeviceSecurityReport? report;

  @override
  Widget build(BuildContext context) {
    final copy = _SecurityLockdownCopy.fromReport(report);
    return PopScope(
      canPop: false,
      child: Material(
        color: const Color(0xFFEFF7F1),
        child: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.xl),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(
                      color: AppColors.fernGreen.withValues(alpha: 0.16),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.10),
                        blurRadius: 30,
                        offset: const Offset(0, 14),
                      ),
                    ],
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(AppSpacing.xl),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 72,
                          height: 72,
                          decoration: BoxDecoration(
                            color: AppColors.fernGreen.withValues(alpha: 0.10),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.shield_outlined,
                            color: AppColors.fernGreen,
                            size: 34,
                          ),
                        ),
                        const SizedBox(height: AppSpacing.lg),
                        Text(
                          copy.title,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: AppColors.charcoal,
                            fontSize: 22,
                            height: 1.15,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: AppSpacing.sm),
                        Text(
                          copy.message,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 14,
                            height: 1.45,
                          ),
                        ),
                        const SizedBox(height: AppSpacing.xl),
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton.icon(
                            onPressed: () =>
                                SystemNavigator.pop(animated: true),
                            icon: const Icon(Icons.exit_to_app_rounded),
                            label: const Text('Exit app'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SecurityLockdownCopy {
  const _SecurityLockdownCopy({required this.title, required this.message});

  final String title;
  final String message;

  factory _SecurityLockdownCopy.fromReport(DeviceSecurityReport? report) {
    final installOnly =
        report?.hasInstallIntegrityIssue == true &&
        report?.hasDeviceIntegrityIssue != true;

    if (installOnly) {
      return const _SecurityLockdownCopy(
        title: 'Install from Google Play',
        message:
            'This copy of Echoproof was not installed from a trusted store or its app signature does not match the expected release. Install or update from Google Play to continue.',
      );
    }

    // keep the generic message for rooted, hooked, debugged, or modified
    // runtime signals. the exact technical reason stays out of the ui so the
    // screen does not become a checklist for bypass attempts.
    return const _SecurityLockdownCopy(
      title: 'Device security required',
      message:
          'Echoproof cannot continue on a rooted, jailbroken, or modified device. Close the app and use a secure device to protect your account and verification activity.',
    );
  }
}
