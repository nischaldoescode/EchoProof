import 'dart:io';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../../../app/theme/colors.dart';
import '../../../../app/theme/spacing.dart';

class PermissionsSheet extends StatefulWidget {
  const PermissionsSheet({super.key});

  @override
  State<PermissionsSheet> createState() => _PermissionsSheetState();
}

class _PermissionsSheetState extends State<PermissionsSheet> {
  bool _notificationsGranted = false;
  bool _cameraGranted = false;
  bool _photosGranted = false;
  bool _isRequesting = false;

  @override
  void initState() {
    super.initState();
    _checkExisting();
  }

  Future<void> _checkExisting() async {
    final notif = await Permission.notification.status;
    final cam = await Permission.camera.status;
    final photos =
        await (Platform.isAndroid ? Permission.photos : Permission.photos)
            .status;
    setState(() {
      _notificationsGranted = notif.isGranted;
      _cameraGranted = cam.isGranted;
      _photosGranted = photos.isGranted;
    });
  }

  Future<void> _requestAll() async {
    setState(() => _isRequesting = true);

    // Request notification permission.
    final notifStatus = await Permission.notification.request();
    if (notifStatus.isPermanentlyDenied) {
      await openAppSettings();
    }

    // Request camera.
    final camStatus = await Permission.camera.request();
    if (camStatus.isPermanentlyDenied) await openAppSettings();

    // Request photos.
    final photoStatus = await Permission.photos.request();
    if (photoStatus.isPermanentlyDenied) await openAppSettings();

    setState(() {
      _notificationsGranted = notifStatus.isGranted;
      _cameraGranted = camStatus.isGranted;
      _photosGranted = photoStatus.isGranted;
      _isRequesting = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.borderMedium,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 20),
            const Icon(Icons.security_rounded,
                size: 40, color: AppColors.fernGreen),
            const SizedBox(height: 12),
            Text(
              'A few permissions',
              style: GoogleFonts.josefinSans(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: AppColors.charcoal,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Echoproof needs these to work properly. You can change them anytime in your phone settings.',
              style: GoogleFonts.josefinSans(
                fontSize: 13,
                color: AppColors.textSecondary,
                height: 1.5,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            _PermRow(
              icon: Icons.notifications_outlined,
              title: 'Notifications',
              desc: 'Get notified when your echoes are supported or challenged',
              granted: _notificationsGranted,
            ),
            const SizedBox(height: 12),
            _PermRow(
              icon: Icons.camera_alt_outlined,
              title: 'Camera',
              desc: 'Take photos to attach as evidence to your echoes',
              granted: _cameraGranted,
            ),
            const SizedBox(height: 12),
            _PermRow(
              icon: Icons.photo_library_outlined,
              title: 'Photos',
              desc: 'Attach images from your gallery',
              granted: _photosGranted,
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _isRequesting ? null : _requestAll,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.charcoal,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  elevation: 0,
                ),
                child: _isRequesting
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : Text(
                        'Allow permissions',
                        style: GoogleFonts.josefinSans(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
              ),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(
                'Skip for now',
                style: GoogleFonts.josefinSans(
                  color: AppColors.textSecondary,
                  fontSize: 13,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PermRow extends StatelessWidget {
  const _PermRow({
    required this.icon,
    required this.title,
    required this.desc,
    required this.granted,
  });

  final IconData icon;
  final String title;
  final String desc;
  final bool granted;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: granted ? AppColors.fernGreenLight : AppColors.softSand,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(
            icon,
            size: 20,
            color: granted ? AppColors.fernGreen : AppColors.textTertiary,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: GoogleFonts.josefinSans(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: AppColors.charcoal,
                ),
              ),
              Text(
                desc,
                style: GoogleFonts.josefinSans(
                  fontSize: 12,
                  color: AppColors.textSecondary,
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
        if (granted)
          const Icon(Icons.check_circle_rounded,
              size: 18, color: AppColors.fernGreen)
        else
          GestureDetector(
            onTap: () => openAppSettings(),
            child: const Icon(Icons.settings_outlined,
                size: 18, color: AppColors.textTertiary),
          ),
      ],
    );
  }
}
