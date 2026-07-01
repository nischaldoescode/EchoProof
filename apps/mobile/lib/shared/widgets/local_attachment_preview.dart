// compact local attachment previews used before upload
// @params path absolute or picker-provided local path for the selected file

import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../app/theme/colors.dart';
import '../../app/theme/spacing.dart';

/// shows a filename-free attachment preview that stays compact in composers.
///
/// the larger preview opens in an animated dialog so split-screen users can
/// inspect the selected file without a full route change or leaked local path.
class LocalAttachmentPreviewTile extends StatelessWidget {
  const LocalAttachmentPreviewTile({
    super.key,
    required this.path,
    required this.index,
    required this.isVideo,
    required this.onRemove,
  });

  final String path;
  final int index;
  final bool isVideo;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final mediaLabel = isVideo ? 'Video' : 'Image';

    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Duration(milliseconds: 210 + index * 35),
      curve: Curves.easeOutCubic,
      builder: (context, value, child) {
        return Opacity(
          opacity: value,
          child: Transform.scale(
            scale: 0.94 + value * 0.06,
            alignment: Alignment.bottomLeft,
            child: child,
          ),
        );
      },
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => showLocalAttachmentPreview(
          context,
          path: path,
          index: index,
          isVideo: isVideo,
        ),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: Container(
                width: 92,
                height: 92,
                color: AppColors.softSand,
                child: isVideo
                    ? DecoratedBox(
                        decoration: BoxDecoration(
                          color: AppColors.charcoal.withValues(alpha: 0.92),
                        ),
                        child: const Icon(
                          Icons.play_circle_fill_rounded,
                          color: AppColors.white,
                          size: 30,
                        ),
                      )
                    : Image.file(
                        File(path),
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) => const Icon(
                          Icons.broken_image_outlined,
                          color: AppColors.textTertiary,
                        ),
                      ),
              ),
            ),
            Positioned(
              left: 6,
              bottom: 6,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                decoration: BoxDecoration(
                  color: AppColors.charcoal.withValues(alpha: 0.72),
                  borderRadius: BorderRadius.circular(AppSpacing.radiusFull),
                ),
                child: Text(
                  mediaLabel,
                  style: GoogleFonts.josefinSans(
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    color: AppColors.white,
                  ),
                ),
              ),
            ),
            Positioned(
              right: -7,
              top: -7,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: onRemove,
                child: Container(
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    color: AppColors.white,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.12),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.close_rounded,
                    size: 16,
                    color: AppColors.sunsetCoral,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

Future<void> showLocalAttachmentPreview(
  BuildContext context, {
  required String path,
  required int index,
  required bool isVideo,
}) {
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
    barrierColor: Colors.black.withValues(alpha: 0.44),
    transitionDuration: const Duration(milliseconds: 220),
    pageBuilder: (context, animation, secondaryAnimation) {
      final size = MediaQuery.sizeOf(context);
      final horizontalInset = size.width < 360 ? AppSpacing.md : AppSpacing.xl;
      final maxWidth = math.min(420.0, size.width - horizontalInset * 2);

      return Center(
        child: Padding(
          padding: EdgeInsets.all(horizontalInset),
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: math.max(260.0, maxWidth)),
            child: Material(
              color: AppColors.white,
              borderRadius: BorderRadius.circular(22),
              clipBehavior: Clip.antiAlias,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AspectRatio(
                    aspectRatio: 1,
                    child: isVideo
                        ? Container(
                            color: AppColors.charcoal,
                            child: const Icon(
                              Icons.play_circle_fill_rounded,
                              color: AppColors.white,
                              size: 48,
                            ),
                          )
                        : Image.file(
                            File(path),
                            fit: BoxFit.cover,
                            errorBuilder: (_, _, _) => Container(
                              color: AppColors.softSand,
                              child: const Icon(
                                Icons.broken_image_outlined,
                                color: AppColors.textTertiary,
                              ),
                            ),
                          ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(18, 14, 18, 18),
                    child: Row(
                      children: [
                        Container(
                          width: 28,
                          height: 28,
                          decoration: BoxDecoration(
                            color: AppColors.fernGreenLight,
                            borderRadius: BorderRadius.circular(
                              AppSpacing.radiusFull,
                            ),
                          ),
                          child: Center(
                            child: Text(
                              '${index + 1}',
                              style: GoogleFonts.josefinSans(
                                color: AppColors.fernGreenDark,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            isVideo ? 'Video attachment' : 'Image attachment',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.josefinSans(
                              fontSize: 14,
                              fontWeight: FontWeight.w800,
                              color: AppColors.charcoal,
                            ),
                          ),
                        ),
                        TextButton(
                          onPressed: () => Navigator.pop(context),
                          child: const Text('Done'),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    },
    transitionBuilder: (context, animation, secondaryAnimation, child) {
      final curved = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
      );
      return FadeTransition(
        opacity: curved,
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.96, end: 1).animate(curved),
          child: child,
        ),
      );
    },
  );
}
