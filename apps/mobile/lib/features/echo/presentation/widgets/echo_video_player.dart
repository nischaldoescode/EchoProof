// echo video player
// @params none

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:visibility_detector/visibility_detector.dart';
import '../../../../app/theme/colors.dart';
import '../../../../app/theme/spacing.dart';
import '../../../../core/services/connectivity_service.dart';
import '../../../../core/services/video_playback_coordinator.dart';
import '../../../../core/utils/snack.dart';

class EchoVideoPlayer extends StatefulWidget {
  const EchoVideoPlayer({
    super.key,
    required this.url,
    required this.playbackId,
    this.autoPlay = true,
    this.initiallyMuted = true,
    this.borderRadius = AppSpacing.radiusMd,
    this.fit = BoxFit.cover,
    this.onOpen,
    this.compact = false,
  });

  final String url;
  final String playbackId;
  final bool autoPlay;
  final bool initiallyMuted;
  final double borderRadius;
  final BoxFit fit;
  final VoidCallback? onOpen;
  final bool compact;

  @override
  State<EchoVideoPlayer> createState() => _EchoVideoPlayerState();
}

class _EchoVideoPlayerState extends State<EchoVideoPlayer>
    with WidgetsBindingObserver {
  VideoPlayerController? _controller;
  StreamSubscription<bool>? _connectivitySub;
  bool _initializing = true;
  bool _failed = false;
  bool _visible = false;
  bool _muted = true;
  bool _offlineSnackShown = false;

  bool get _isReady =>
      _controller != null &&
      _controller!.value.isInitialized &&
      !_controller!.value.hasError;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _muted = widget.initiallyMuted;
    VideoPlaybackCoordinator.instance.activeVideoId.addListener(_syncPlayback);
    _connectivitySub =
        ConnectivityService.instance.onConnectivityChanged.listen((isOnline) {
      if (!mounted || !_isReady) return;
      if (!isOnline && _controller!.value.isPlaying) {
        _controller!.pause();
        _offlineSnackShown = true;
        showWarningSnack(context, 'Video paused. Check your connection.');
      } else if (isOnline && _offlineSnackShown && _visible) {
        _offlineSnackShown = false;
        showInfoSnack(context, 'Connection restored.');
        _playIfEligible();
      }
    });
    _initialize();
  }

  @override
  void didUpdateWidget(covariant EchoVideoPlayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url ||
        oldWidget.playbackId != widget.playbackId) {
      _disposeController();
      _initializing = true;
      _failed = false;
      _initialize();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.detached) {
      _controller?.pause();
      VideoPlaybackCoordinator.instance.release(widget.playbackId);
    } else if (state == AppLifecycleState.resumed) {
      _playIfEligible();
    }
  }

  Future<void> _initialize() async {
    final uri = Uri.tryParse(widget.url);
    if (uri == null) {
      if (mounted) {
        setState(() {
          _initializing = false;
          _failed = true;
        });
      }
      return;
    }

    final controller = VideoPlayerController.networkUrl(
      uri,
      videoPlayerOptions: VideoPlayerOptions(mixWithOthers: false),
    );
    _controller = controller;

    try {
      await controller.initialize();
      await controller.setLooping(true);
      await controller.setVolume(_muted ? 0 : 1);
      if (!mounted) return;
      setState(() => _initializing = false);
      _playIfEligible();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _initializing = false;
        _failed = true;
      });
      showWarningSnack(context, 'Could not load this video.');
    }
  }

  void _syncPlayback() {
    if (!_isReady) return;
    final active = VideoPlaybackCoordinator.instance.activeVideoId.value;
    if (active == widget.playbackId && _visible && widget.autoPlay) {
      if (!_controller!.value.isPlaying) _controller!.play();
    } else if (_controller!.value.isPlaying) {
      _controller!.pause();
    }
    if (mounted) setState(() {});
  }

  void _playIfEligible() {
    if (!_isReady || !_visible || !widget.autoPlay) return;
    if (!ConnectivityService.instance.isOnline) return;
    VideoPlaybackCoordinator.instance.requestPlay(widget.playbackId);
    _syncPlayback();
  }

  void _toggleMute() {
    if (!_isReady) return;
    setState(() => _muted = !_muted);
    _controller!.setVolume(_muted ? 0 : 1);
  }

  void _togglePlay() {
    if (!_isReady) return;
    if (_controller!.value.isPlaying) {
      _controller!.pause();
      VideoPlaybackCoordinator.instance.release(widget.playbackId);
    } else {
      _visible = true;
      VideoPlaybackCoordinator.instance.requestPlay(widget.playbackId);
      _syncPlayback();
    }
    setState(() {});
  }

  void _disposeController() {
    VideoPlaybackCoordinator.instance.release(widget.playbackId);
    final controller = _controller;
    _controller = null;
    controller?.dispose();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    VideoPlaybackCoordinator.instance.activeVideoId
        .removeListener(_syncPlayback);
    _connectivitySub?.cancel();
    _disposeController();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return VisibilityDetector(
      key: Key('video_${widget.playbackId}'),
      onVisibilityChanged: (info) {
        final nowVisible = info.visibleFraction >= 0.62;
        if (_visible == nowVisible) return;
        _visible = nowVisible;
        if (_visible) {
          _playIfEligible();
        } else {
          _controller?.pause();
          VideoPlaybackCoordinator.instance.release(widget.playbackId);
        }
      },
      child: ClipRRect(
        borderRadius: BorderRadius.circular(widget.borderRadius),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onOpen ?? _togglePlay,
          child: ColoredBox(
            color: AppColors.charcoal,
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (_isReady)
                  FittedBox(
                    fit: widget.fit,
                    child: SizedBox(
                      width: _controller!.value.size.width,
                      height: _controller!.value.size.height,
                      child: VideoPlayer(_controller!),
                    ),
                  )
                else
                  const SizedBox.shrink(),
                if (_initializing) const _VideoLoadingOverlay(),
                if (_failed) const _VideoErrorOverlay(),
                if (_isReady && !_controller!.value.isPlaying)
                  Center(
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      width: widget.compact ? 46 : 58,
                      height: widget.compact ? 46 : 58,
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.42),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.28),
                        ),
                      ),
                      child: Icon(
                        Icons.play_arrow_rounded,
                        color: Colors.white,
                        size: widget.compact ? 28 : 36,
                      ),
                    ),
                  ),
                if (_isReady)
                  Positioned(
                    right: AppSpacing.sm,
                    bottom: AppSpacing.sm,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _RoundVideoButton(
                          icon: _muted
                              ? Icons.volume_off_rounded
                              : Icons.volume_up_rounded,
                          onTap: _toggleMute,
                        ),
                        if (widget.onOpen != null) ...[
                          const SizedBox(width: AppSpacing.xs),
                          _RoundVideoButton(
                            icon: Icons.open_in_full_rounded,
                            onTap: widget.onOpen!,
                          ),
                        ],
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _RoundVideoButton extends StatelessWidget {
  const _RoundVideoButton({required this.icon, required this.onTap});
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        width: 34,
        height: 34,
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.54),
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
        ),
        child: Icon(icon, size: 18, color: Colors.white),
      ),
    );
  }
}

class _VideoLoadingOverlay extends StatelessWidget {
  const _VideoLoadingOverlay();

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: AppColors.charcoal,
      child: Center(
        child: SizedBox(
          width: 34,
          height: 34,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: AppColors.fernGreen.withValues(alpha: 0.95),
          ),
        ),
      ),
    );
  }
}

class _VideoErrorOverlay extends StatelessWidget {
  const _VideoErrorOverlay();

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: AppColors.charcoal,
      child: const Center(
        child: Icon(
          Icons.videocam_off_outlined,
          color: Colors.white70,
          size: 34,
        ),
      ),
    );
  }
}
