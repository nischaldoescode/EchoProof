// image viewer
// @params none

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../app/theme/colors.dart';
import 'dart:io' show Platform;
import 'package:flutter_windowmanager_plus/flutter_windowmanager_plus.dart';

class ImageViewer extends StatefulWidget {
  const ImageViewer({super.key, required this.urls, this.initialIndex = 0});

  final List<String> urls;
  final int initialIndex;

  static Future<void> show(
    BuildContext context, {
    required List<String> urls,
    int initialIndex = 0,
  }) {
    if (urls.isEmpty) return Future.value();
    final safeInitialIndex = initialIndex.clamp(0, urls.length - 1).toInt();
    return Navigator.of(context).push(
      PageRouteBuilder(
        opaque: false,
        barrierColor: Colors.black,
        pageBuilder: (_, _, _) =>
            ImageViewer(urls: urls, initialIndex: safeInitialIndex),
        transitionsBuilder: (_, animation, _, child) {
          return FadeTransition(opacity: animation, child: child);
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
    // image routes used to clear flag_secure on dispose
    // keep it sticky so one viewer cannot reopen screenshots globally
  }

  @override
  void initState() {
    super.initState();
    _current = widget.urls.isEmpty
        ? 0
        : widget.initialIndex.clamp(0, widget.urls.length - 1).toInt();
    _pageController = PageController(initialPage: _current);
    _lockScreen();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _precacheAround(_current);
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

  void _precacheAround(int index) {
    for (final i in [index - 1, index, index + 1]) {
      if (i < 0 || i >= widget.urls.length) continue;
      // keep swipes feeling instant without fetching the whole gallery
      unawaited(
        precacheImage(
          CachedNetworkImageProvider(widget.urls[i], cacheKey: widget.urls[i]),
          context,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.urls.isEmpty) {
      return const Scaffold(backgroundColor: Colors.black);
    }

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
          onPageChanged: (i) {
            setState(() => _current = i);
            _precacheAround(i);
          },
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
                child: CachedNetworkImage(
                  imageUrl: widget.urls[index],
                  cacheKey: widget.urls[index],
                  fit: BoxFit.contain,
                  progressIndicatorBuilder: (context, url, progress) {
                    return Center(
                      child: CircularProgressIndicator(
                        value: progress.progress,
                        color: AppColors.fernGreen,
                        strokeWidth: 2,
                      ),
                    );
                  },
                  errorWidget: (_, _, _) => const Center(
                    child: Icon(
                      Icons.broken_image_outlined,
                      color: Colors.white54,
                      size: 48,
                    ),
                  ),
                  imageBuilder: (context, imageProvider) {
                    return Center(
                      child: Image(image: imageProvider, fit: BoxFit.contain),
                    );
                  },
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
