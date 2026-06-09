// image viewer
// @params none

import 'package:flutter/material.dart';
import '../../app/theme/colors.dart';
import 'dart:io' show Platform;
import 'package:flutter_windowmanager_plus/flutter_windowmanager_plus.dart';

class ImageViewer extends StatefulWidget {
  const ImageViewer({
    super.key,
    required this.urls,
    this.initialIndex = 0,
  });

  final List<String> urls;
  final int initialIndex;

  static Future<void> show(
    BuildContext context, {
    required List<String> urls,
    int initialIndex = 0,
  }) {
    return Navigator.of(context).push(
      PageRouteBuilder(
        opaque: false,
        barrierColor: Colors.black,
        pageBuilder: (_, __, ___) => ImageViewer(
          urls: urls,
          initialIndex: initialIndex,
        ),
        transitionsBuilder: (_, animation, __, child) {
          return FadeTransition(
            opacity: animation,
            child: child,
          );
        },
        transitionDuration: const Duration(milliseconds: 200),
      ),
    );
  }

  @override
  State<ImageViewer> createState() => _ImageViewerState();
}

class _ImageViewerState extends State<ImageViewer> {
  late final PageController _pageController;
  late int _current;
  final TransformationController _transformCtrl = TransformationController();
  bool _isZoomed = false;

  Future<void> _lockScreen() async {
    if (!Platform.isAndroid) return;
    try {
      await FlutterWindowManagerPlus.addFlags(
        FlutterWindowManagerPlus.FLAG_SECURE,
      );
    } catch (_) {}
  }

  Future<void> _unlockScreen() async {
    if (!Platform.isAndroid) return;
    try {
      await FlutterWindowManagerPlus.clearFlags(
        FlutterWindowManagerPlus.FLAG_SECURE,
      );
    } catch (_) {}
  }

  @override
  void initState() {
    super.initState();
    _current = widget.initialIndex;
    _pageController = PageController(initialPage: widget.initialIndex);
    _lockScreen();
  }

  @override
  void dispose() {
    _unlockScreen();
    _pageController.dispose();
    _transformCtrl.dispose();
    super.dispose();
  }

  void _resetZoom() {
    _transformCtrl.value = Matrix4.identity();
    setState(() => _isZoomed = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: Colors.white,
        leading: IconButton(
          icon: const Icon(Icons.close_rounded),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          if (widget.urls.length > 1)
            Padding(
              padding: const EdgeInsets.only(right: 16),
              child: Center(
                child: Text(
                  '${_current + 1} / ${widget.urls.length}',
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ),
        ],
      ),
      body: GestureDetector(
        onTap: () {
          if (_isZoomed) {
            _resetZoom();
          } else {
            Navigator.pop(context);
          }
        },
        child: PageView.builder(
          controller: _pageController,
          physics: _isZoomed
              ? const NeverScrollableScrollPhysics()
              : const BouncingScrollPhysics(),
          onPageChanged: (i) => setState(() => _current = i),
          itemCount: widget.urls.length,
          itemBuilder: (context, index) {
            return InteractiveViewer(
              transformationController: _transformCtrl,
              minScale: 1.0,
              maxScale: 4.0,
              onInteractionStart: (_) => setState(() => _isZoomed = true),
              onInteractionEnd: (_) {
                if (_transformCtrl.value == Matrix4.identity()) {
                  setState(() => _isZoomed = false);
                }
              },
              child: Center(
                child: Image.network(
                  widget.urls[index],
                  fit: BoxFit.contain,
                  loadingBuilder: (context, child, progress) {
                    if (progress == null) return child;
                    return Center(
                      child: CircularProgressIndicator(
                        value: progress.expectedTotalBytes != null
                            ? progress.cumulativeBytesLoaded /
                                progress.expectedTotalBytes!
                            : null,
                        color: AppColors.fernGreen,
                        strokeWidth: 2,
                      ),
                    );
                  },
                  errorBuilder: (_, __, ___) => const Center(
                    child: Icon(
                      Icons.broken_image_outlined,
                      color: Colors.white54,
                      size: 48,
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
