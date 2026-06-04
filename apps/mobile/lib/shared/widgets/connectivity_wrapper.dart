// connectivity wrapper
// @params none

import 'dart:async';
import 'package:flutter/material.dart';
import '../../core/services/connectivity_service.dart';
import '../../core/utils/snack.dart';

class ConnectivityWrapper extends StatefulWidget {
  const ConnectivityWrapper({super.key, required this.child});
  final Widget child;

  @override
  State<ConnectivityWrapper> createState() => _ConnectivityWrapperState();
}

class _ConnectivityWrapperState extends State<ConnectivityWrapper> {
  StreamSubscription<bool>? _sub;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || ConnectivityService.instance.isOnline) return;
      showWarningSnack(context, 'No internet connection');
    });
    _sub =
        ConnectivityService.instance.onConnectivityChanged.listen((isOnline) {
      if (!mounted) return;
      if (isOnline) {
        showSuccessSnack(context, 'Back online');
      } else {
        showWarningSnack(context, 'No internet connection');
      }
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
