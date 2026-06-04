// secure screen
// @params none

import 'package:flutter/material.dart';
import 'package:flutter_windowmanager_plus/flutter_windowmanager_plus.dart';
import 'dart:io' show Platform;

class SecureScreen extends StatefulWidget {
  const SecureScreen({super.key, required this.child});
  final Widget child;

  @override
  State<SecureScreen> createState() => _SecureScreenState();
}

class _SecureScreenState extends State<SecureScreen> {
  static int _activeLocks = 0;

  @override
  void initState() {
    super.initState();
    _lock();
  }

  @override
  void dispose() {
    _unlock();
    super.dispose();
  }

  Future<void> _lock() async {
    if (!Platform.isAndroid) return;
    _activeLocks += 1;
    try {
      await FlutterWindowManagerPlus.addFlags(
        FlutterWindowManagerPlus.FLAG_SECURE,
      );
    } catch (_) {}
  }

  Future<void> _unlock() async {
    if (!Platform.isAndroid) return;
    if (_activeLocks > 0) {
      _activeLocks -= 1;
    }
    if (_activeLocks > 0) return;
    try {
      await FlutterWindowManagerPlus.clearFlags(
        FlutterWindowManagerPlus.FLAG_SECURE,
      );
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
