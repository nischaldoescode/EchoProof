// profile banner crop editor
// @params bytes source image bytes selected by the owner

import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image/image.dart' as img;

import '../../../../app/theme/colors.dart';
import '../../../../app/theme/spacing.dart';
import '../../../../core/localization/app_copy.dart';

const profileBannerAspectRatio = 3.0;
const profileBannerOutputWidth = 1500;
const profileBannerOutputHeight = 500;
const profileBannerMinWidth = 900;
const profileBannerMinHeight = 300;
const profileBannerMaxBytes = 1024 * 1024;

class ProfileBannerCropResult {
  const ProfileBannerCropResult({
    required this.bytes,
    required this.extension,
    required this.width,
    required this.height,
  });

  final Uint8List bytes;
  final String extension;
  final int width;
  final int height;
}

Future<ProfileBannerCropResult?> showProfileBannerCropEditor({
  required BuildContext context,
  required Uint8List bytes,
  required int imageWidth,
  required int imageHeight,
}) {
  return Navigator.of(context).push<ProfileBannerCropResult>(
    PageRouteBuilder(
      fullscreenDialog: true,
      opaque: true,
      pageBuilder: (context, animation, secondaryAnimation) =>
          _ProfileBannerCropEditor(
            bytes: bytes,
            imageWidth: imageWidth,
            imageHeight: imageHeight,
          ),
      transitionsBuilder: (context, animation, secondaryAnimation, child) {
        final reduceMotion = MediaQuery.disableAnimationsOf(context);
        return AnimatedBuilder(
          animation: animation,
          child: RepaintBoundary(child: child),
          builder: (context, child) {
            final raw = animation.value.clamp(0.0, 1.0).toDouble();
            final progress = Curves.easeOutCubic.transform(raw);

            if (reduceMotion) {
              return Opacity(opacity: progress, child: child);
            }

            final devicePixelRatio = MediaQuery.devicePixelRatioOf(context);
            final offset = (1 - progress) * 18;
            final snappedOffset =
                (offset * devicePixelRatio).roundToDouble() / devicePixelRatio;

            return Opacity(
              opacity: progress,
              child: Transform.translate(
                offset: Offset(0, snappedOffset),
                child: child,
              ),
            );
          },
        );
      },
      transitionDuration: const Duration(milliseconds: 240),
      reverseTransitionDuration: const Duration(milliseconds: 180),
    ),
  );
}

class _ProfileBannerCropEditor extends StatefulWidget {
  const _ProfileBannerCropEditor({
    required this.bytes,
    required this.imageWidth,
    required this.imageHeight,
  });

  final Uint8List bytes;
  final int imageWidth;
  final int imageHeight;

  @override
  State<_ProfileBannerCropEditor> createState() =>
      _ProfileBannerCropEditorState();
}

class _ProfileBannerCropEditorState extends State<_ProfileBannerCropEditor> {
  double _zoom = 1;
  Offset _pan = Offset.zero;
  _BannerCropGeometry? _geometry;
  bool _isApplying = false;

  void _setZoom(double value) {
    final geometry = _geometry;
    setState(() {
      _zoom = value;
      if (geometry != null) {
        _pan = geometry.copyWith(zoom: value).clampPan(_pan);
      }
    });
  }

  void _panImage(DragUpdateDetails details) {
    final geometry = _geometry;
    if (geometry == null) return;
    setState(() {
      _pan = geometry.clampPan(_pan + details.delta);
    });
  }

  Future<void> _apply() async {
    final geometry = _geometry;
    if (geometry == null || _isApplying) return;

    setState(() => _isApplying = true);
    try {
      final crop = geometry.sourceCrop(_pan);
      final result = await compute(_encodeProfileBanner, {
        'bytes': widget.bytes,
        'x': crop.left.round(),
        'y': crop.top.round(),
        'width': crop.width.round(),
        'height': crop.height.round(),
      });

      final output = result['bytes'] as Uint8List?;
      final error = result['error'] as String?;
      if (!mounted) return;

      if (output == null || error != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(error ?? context.l('Could not prepare image.')),
          ),
        );
        setState(() => _isApplying = false);
        return;
      }

      Navigator.of(context).pop(
        ProfileBannerCropResult(
          bytes: output,
          extension: 'jpg',
          width: profileBannerOutputWidth,
          height: profileBannerOutputHeight,
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l('Could not prepare image.'))),
      );
      setState(() => _isApplying = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final safe = MediaQuery.paddingOf(context);
    final size = MediaQuery.sizeOf(context);
    final isWide = size.width >= 720;

    return Scaffold(
      backgroundColor: const Color(0xFFF3F8F5),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(
                AppSpacing.sm,
                AppSpacing.xs,
                AppSpacing.md,
                AppSpacing.xs,
              ),
              child: Row(
                children: [
                  IconButton(
                    onPressed: _isApplying
                        ? null
                        : () => Navigator.pop(context),
                    icon: const Icon(Icons.arrow_back_rounded),
                    color: AppColors.charcoal,
                    tooltip: context.l('Back'),
                  ),
                  Expanded(
                    child: Text(
                      context.l('Edit banner'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.josefinSans(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        color: AppColors.charcoal,
                      ),
                    ),
                  ),
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 180),
                    child: _isApplying
                        ? const SizedBox(
                            key: ValueKey('applying'),
                            width: 84,
                            height: 42,
                            child: Center(
                              child: SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: AppColors.fernGreen,
                                ),
                              ),
                            ),
                          )
                        : FilledButton(
                            key: const ValueKey('apply'),
                            onPressed: _apply,
                            style: FilledButton.styleFrom(
                              backgroundColor: AppColors.charcoal,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 20,
                                vertical: 12,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(20),
                              ),
                            ),
                            child: Text(context.l('Apply')),
                          ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final horizontalPadding = isWide ? 48.0 : AppSpacing.md;
                  final stageWidth = math.min(
                    constraints.maxWidth - horizontalPadding * 2,
                    760.0,
                  );
                  final cropHeight = stageWidth / profileBannerAspectRatio;
                  final stageHeight = math.min(
                    constraints.maxHeight - 112,
                    math.max(cropHeight + 128, cropHeight),
                  );
                  final cropTop = math.max((stageHeight - cropHeight) / 2, 0.0);

                  final geometry = _BannerCropGeometry(
                    stageSize: Size(stageWidth, stageHeight),
                    cropRect: Rect.fromLTWH(0, cropTop, stageWidth, cropHeight),
                    imageSize: Size(
                      widget.imageWidth.toDouble(),
                      widget.imageHeight.toDouble(),
                    ),
                    zoom: _zoom,
                  );
                  _geometry = geometry;
                  final clampedPan = geometry.clampPan(_pan);
                  if (clampedPan != _pan) {
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (mounted) setState(() => _pan = clampedPan);
                    });
                  }

                  return SingleChildScrollView(
                    physics: const ClampingScrollPhysics(),
                    padding: EdgeInsets.fromLTRB(
                      horizontalPadding,
                      AppSpacing.md,
                      horizontalPadding,
                      safe.bottom + AppSpacing.lg,
                    ),
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 820),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _BannerCropStage(
                              bytes: widget.bytes,
                              geometry: geometry,
                              pan: clampedPan,
                              onPanUpdate: _panImage,
                            ),
                            const SizedBox(height: AppSpacing.lg),
                            _ZoomControl(
                              value: _zoom,
                              onChanged: _isApplying ? null : _setZoom,
                            ),
                            const SizedBox(height: AppSpacing.md),
                            _BannerCropMeta(
                              imageWidth: widget.imageWidth,
                              imageHeight: widget.imageHeight,
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BannerCropStage extends StatelessWidget {
  const _BannerCropStage({
    required this.bytes,
    required this.geometry,
    required this.pan,
    required this.onPanUpdate,
  });

  final Uint8List bytes;
  final _BannerCropGeometry geometry;
  final Offset pan;
  final ValueChanged<DragUpdateDetails> onPanUpdate;

  @override
  Widget build(BuildContext context) {
    final display = geometry.displayRect(pan);

    return GestureDetector(
      onPanUpdate: onPanUpdate,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
        width: geometry.stageSize.width,
        height: geometry.stageSize.height,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: const Color(0xFFE8F0ED),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: AppColors.borderSubtle),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.06),
              blurRadius: 24,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            Positioned.fromRect(
              rect: display,
              child: Image.memory(
                bytes,
                fit: BoxFit.fill,
                gaplessPlayback: true,
              ),
            ),
            CustomPaint(
              painter: _CropOverlayPainter(cropRect: geometry.cropRect),
            ),
            Positioned.fromRect(
              rect: geometry.cropRect,
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    border: Border.all(color: AppColors.fernGreen, width: 2.2),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.fernGreen.withValues(alpha: 0.12),
                        blurRadius: 16,
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Positioned(
              left: AppSpacing.md,
              right: AppSpacing.md,
              bottom: AppSpacing.sm,
              child: IgnorePointer(
                child: Text(
                  context.l(
                    'Drag to place the crop. Pinch is kept simple with zoom below.',
                  ),
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.josefinSans(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppColors.charcoal.withValues(alpha: 0.72),
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

class _ZoomControl extends StatelessWidget {
  const _ZoomControl({required this.value, required this.onChanged});

  final double value;
  final ValueChanged<double>? onChanged;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppColors.borderSubtle),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.sm,
        ),
        child: Row(
          children: [
            const Icon(
              Icons.zoom_out_rounded,
              color: AppColors.textSecondary,
              size: 20,
            ),
            Expanded(
              child: SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  activeTrackColor: AppColors.fernGreen,
                  inactiveTrackColor: AppColors.fernGreen.withValues(
                    alpha: 0.18,
                  ),
                  thumbColor: AppColors.fernGreen,
                  overlayColor: AppColors.fernGreen.withValues(alpha: 0.14),
                  trackHeight: 3,
                ),
                child: Slider(
                  min: 1,
                  max: 3,
                  value: value,
                  onChanged: onChanged,
                ),
              ),
            ),
            const Icon(
              Icons.zoom_in_rounded,
              color: AppColors.textSecondary,
              size: 20,
            ),
          ],
        ),
      ),
    );
  }
}

class _BannerCropMeta extends StatelessWidget {
  const _BannerCropMeta({required this.imageWidth, required this.imageHeight});

  final int imageWidth;
  final int imageHeight;

  @override
  Widget build(BuildContext context) {
    return AnimatedOpacity(
      duration: const Duration(milliseconds: 220),
      opacity: 1,
      child: Text(
        context.l('Output: 1500 x 500, under 1 MB. Original: {size}.', {
          'size': '$imageWidth x $imageHeight',
        }),
        textAlign: TextAlign.center,
        style: GoogleFonts.josefinSans(
          fontSize: 12,
          height: 1.35,
          color: AppColors.textSecondary,
        ),
      ),
    );
  }
}

class _CropOverlayPainter extends CustomPainter {
  const _CropOverlayPainter({required this.cropRect});

  final Rect cropRect;

  @override
  void paint(Canvas canvas, Size size) {
    final mask = Paint()..color = Colors.white.withValues(alpha: 0.56);
    final full = Path()..addRect(Offset.zero & size);
    final hole = Path()..addRect(cropRect);
    final path = Path.combine(PathOperation.difference, full, hole);
    canvas.drawPath(path, mask);

    final guide = Paint()
      ..color = Colors.white.withValues(alpha: 0.48)
      ..strokeWidth = 1;
    for (var i = 1; i < 3; i++) {
      final x = cropRect.left + cropRect.width * i / 3;
      canvas.drawLine(
        Offset(x, cropRect.top),
        Offset(x, cropRect.bottom),
        guide,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _CropOverlayPainter oldDelegate) {
    return oldDelegate.cropRect != cropRect;
  }
}

class _BannerCropGeometry {
  const _BannerCropGeometry({
    required this.stageSize,
    required this.cropRect,
    required this.imageSize,
    required this.zoom,
  });

  final Size stageSize;
  final Rect cropRect;
  final Size imageSize;
  final double zoom;

  double get baseScale {
    return math.max(
      cropRect.width / imageSize.width,
      cropRect.height / imageSize.height,
    );
  }

  double get displayScale => baseScale * zoom;

  Rect displayRect(Offset pan) {
    final displaySize = Size(
      imageSize.width * displayScale,
      imageSize.height * displayScale,
    );
    final origin =
        Offset(
          (stageSize.width - displaySize.width) / 2,
          (stageSize.height - displaySize.height) / 2,
        ) +
        pan;
    return origin & displaySize;
  }

  Offset clampPan(Offset pan) {
    final display = displayRect(Offset.zero);
    final minX = cropRect.right - display.right;
    final maxX = cropRect.left - display.left;
    final minY = cropRect.bottom - display.bottom;
    final maxY = cropRect.top - display.top;
    return Offset(
      pan.dx.clamp(math.min(minX, maxX), math.max(minX, maxX)).toDouble(),
      pan.dy.clamp(math.min(minY, maxY), math.max(minY, maxY)).toDouble(),
    );
  }

  Rect sourceCrop(Offset pan) {
    final display = displayRect(clampPan(pan));
    final left = ((cropRect.left - display.left) / displayScale).clamp(
      0.0,
      imageSize.width - 1,
    );
    final top = ((cropRect.top - display.top) / displayScale).clamp(
      0.0,
      imageSize.height - 1,
    );
    final width = (cropRect.width / displayScale).clamp(
      1.0,
      imageSize.width - left,
    );
    final height = (cropRect.height / displayScale).clamp(
      1.0,
      imageSize.height - top,
    );
    return Rect.fromLTWH(left, top, width, height);
  }

  _BannerCropGeometry copyWith({double? zoom}) {
    return _BannerCropGeometry(
      stageSize: stageSize,
      cropRect: cropRect,
      imageSize: imageSize,
      zoom: zoom ?? this.zoom,
    );
  }
}

Map<String, dynamic> _encodeProfileBanner(Map<String, dynamic> payload) {
  final source = payload['bytes'] as Uint8List;
  final decoded = img.decodeImage(source);
  if (decoded == null) {
    return {'error': 'That image could not be read.'};
  }

  final x = payload['x'] as int;
  final y = payload['y'] as int;
  final width = payload['width'] as int;
  final height = payload['height'] as int;
  final safeX = x.clamp(0, decoded.width - 1).toInt();
  final safeY = y.clamp(0, decoded.height - 1).toInt();
  final safeWidth = width.clamp(1, decoded.width - safeX).toInt();
  final safeHeight = height.clamp(1, decoded.height - safeY).toInt();

  final cropped = img.copyCrop(
    decoded,
    x: safeX,
    y: safeY,
    width: safeWidth,
    height: safeHeight,
  );
  final resized = img.copyResize(
    cropped,
    width: profileBannerOutputWidth,
    height: profileBannerOutputHeight,
    interpolation: img.Interpolation.cubic,
  );

  for (final quality in [92, 86, 80, 74, 68]) {
    final encoded = Uint8List.fromList(
      img.encodeJpg(resized, quality: quality),
    );
    if (encoded.length <= profileBannerMaxBytes) {
      return {'bytes': encoded};
    }
  }

  final smaller = img.copyResize(
    cropped,
    width: 1200,
    height: 400,
    interpolation: img.Interpolation.cubic,
  );
  final encoded = Uint8List.fromList(img.encodeJpg(smaller, quality: 68));
  if (encoded.length <= profileBannerMaxBytes) {
    return {'bytes': encoded};
  }

  return {'error': 'That banner is still over 1 MB after compression.'};
}
