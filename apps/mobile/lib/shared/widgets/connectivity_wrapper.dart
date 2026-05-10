import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/services/connectivity_service.dart';
import '../../app/theme/colors.dart';

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
    _sub = ConnectivityService.instance.onConnectivityChanged.listen((isOnline) {
      if (!mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(
        SnackBar(
          content: Row(
            children: [
              Icon(
                isOnline ? Icons.wifi_rounded : Icons.wifi_off_rounded,
                color: Colors.white,
                size: 16,
              ),
              const SizedBox(width: 8),
              Text(
                isOnline ? 'Back online' : 'No internet connection',
                style: GoogleFonts.josefinSans(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
          backgroundColor:
              isOnline ? AppColors.fernGreen : AppColors.sunsetCoral,
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.only(bottom: 88, left: 16, right: 16),
          duration: Duration(seconds: isOnline ? 2 : 10),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      );
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