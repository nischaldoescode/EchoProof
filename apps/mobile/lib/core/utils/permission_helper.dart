// permission helper
// @params none

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:permission_handler/permission_handler.dart';

abstract final class PermissionHelper {
  // requests photo permission
  // if denied, shows a dialog explaining why and offers to open settings
  static Future<bool> requestPhotos(BuildContext context) async {
    final status = await Permission.photos.status;

    if (status.isGranted || status.isLimited) return true;

    if (status.isPermanentlyDenied) {
      if (context.mounted) await _showSettingsDialog(context, 'Photo library');
      return false;
    }

    final result = await Permission.photos.request();

    if (result.isGranted || result.isLimited) return true;

    if (result.isPermanentlyDenied && context.mounted) {
      await _showSettingsDialog(context, 'Photo library');
    }

    return false;
  }

  // requests camera permission
  static Future<bool> requestCamera(BuildContext context) async {
    final status = await Permission.camera.status;

    if (status.isGranted) return true;

    if (status.isPermanentlyDenied) {
      if (context.mounted) await _showSettingsDialog(context, 'Camera');
      return false;
    }

    final result = await Permission.camera.request();
    if (result.isGranted) return true;

    if (result.isPermanentlyDenied && context.mounted) {
      await _showSettingsDialog(context, 'Camera');
    }

    return false;
  }

  // shows a dialog when permission is permanently denied
  // explains why we need it and offers to open app settings
  static Future<void> _showSettingsDialog(
    BuildContext context,
    String permissionName,
  ) async {
    final (reason, icon) = _reasonFor(permissionName);

    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        contentPadding: const EdgeInsets.all(24),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: const Color(0xFFD4F0E2),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(icon, size: 28, color: const Color(0xFF4CAF6E)),
            ),
            const SizedBox(height: 16),
            Text(
              '$permissionName access needed',
              style: GoogleFonts.josefinSans(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: const Color(0xFF1A1A1A),
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 10),
            Text(
              reason,
              style: GoogleFonts.josefinSans(
                fontSize: 13,
                color: const Color(0xFF6B7280),
                height: 1.5,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'You previously denied this permission. Please enable it in your device settings.',
              style: GoogleFonts.josefinSans(
                fontSize: 12,
                color: const Color(0xFF9CA3AF),
                fontStyle: FontStyle.italic,
                height: 1.5,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
        actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        actions: [
          OutlinedButton(
            onPressed: () => Navigator.pop(ctx),
            style: OutlinedButton.styleFrom(
              foregroundColor: const Color(0xFF6B7280),
              side: const BorderSide(color: Color(0xFFE5E7EB)),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            child: Text(
              'Not now',
              style: GoogleFonts.josefinSans(fontSize: 13),
            ),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              openAppSettings();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF1A1A1A),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            child: Text(
              'Open settings',
              style: GoogleFonts.josefinSans(
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  static (String, IconData) _reasonFor(String name) => switch (name) {
        'Photo library' => (
            'Echoproof needs access to your photos so you can attach evidence to your echoes. We never access your library without you choosing a photo.',
            Icons.photo_library_outlined,
          ),
        'Camera' => (
            'Echoproof needs your camera to take photos as evidence for echoes or during identity verification.',
            Icons.camera_alt_outlined,
          ),
        _ => (
            'This permission is needed for Echoproof to work correctly.',
            Icons.lock_outlined,
          ),
      };
}
