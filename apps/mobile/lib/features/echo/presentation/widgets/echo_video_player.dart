// echo video player
// @params url remote video url
// @params playbackid unique id used to stop competing videos
// @params compact uses smaller controls inside echo cards
// renders responsive controls without assuming phone-only dimensions

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
  bool _controlsVisible = false;
  bool _seeking = false;
  Timer? _controlsTimer;

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
      if (!mounted || _controller != controller) {
        await controller.dispose();
        return;
      }
      controller.addListener(_handleControllerTick);
      await controller.setLooping(true);
      await controller.setVolume(_muted ? 0 : 1);
      setState(() => _initializing = false);
      _playIfEligible();
    } catch (_) {
      if (!mounted || _controller != controller) {
        await controller.dispose();
        return;
      }
      setState(() {
        _initializing = false;
        _failed = true;
      });
      showWarningSnack(context, 'Could not load this video.');
    }
  }

  void _handleControllerTick() {
    if (!mounted || !_isReady) return;
    if (_controlsVisible || _seeking || !_controller!.value.isPlaying) {
      setState(() {});
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
    _scheduleControlsHide();
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
    _showControls(keepVisible: !_controller!.value.isPlaying);
  }

  void _handleTap() {
    if (!_isReady) return;
    _showControls();
  }

  void _showControls({bool keepVisible = false}) {
    _controlsTimer?.cancel();
    if (mounted) setState(() => _controlsVisible = true);
    if (!keepVisible) _scheduleControlsHide();
  }

  void _scheduleControlsHide() {
    _controlsTimer?.cancel();
    _controlsTimer = Timer(const Duration(seconds: 4), () {
      if (!mounted || _seeking) return;
      setState(() => _controlsVisible = false);
    });
  }

  Future<void> _seekToFraction(double fraction) async {
    if (!_isReady) return;
    final duration = _controller!.value.duration;
    if (duration <= Duration.zero) return;
    final safeFraction = fraction.clamp(0.0, 1.0).toDouble();
    final targetMs = (duration.inMilliseconds * safeFraction).round();
    await _controller!.seekTo(Duration(milliseconds: targetMs));
    _scheduleControlsHide();
  }

  Future<void> _seekBy(Duration delta) async {
    if (!_isReady) return;
    final value = _controller!.value;
    final duration = value.duration;
    if (duration <= Duration.zero) return;
    final targetMs = (value.position + delta).inMilliseconds.clamp(
          0,
          duration.inMilliseconds,
        );
    await _controller!.seekTo(Duration(milliseconds: targetMs));
    _showControls();
  }

  void _disposeController() {
    VideoPlaybackCoordinator.instance.release(widget.playbackId);
    final controller = _controller;
    _controller = null;
    controller?.removeListener(_handleControllerTick);
    controller?.dispose();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controlsTimer?.cancel();
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
          onTap: _handleTap,
          onDoubleTap: widget.onOpen ?? _togglePlay,
          child: ColoredBox(
            color: AppColors.charcoal,
            child: LayoutBuilder(
              builder: (context, constraints) {
                final controlCompact = widget.compact ||
                    constraints.maxWidth < 420 ||
                    constraints.maxHeight < 240;
                final showControls = _controlsVisible ||
                    (_isReady && !_controller!.value.isPlaying);

                return Stack(
                  fit: StackFit.expand,
                  children: [
                    if (_isReady)
                      FittedBox(
                        fit: widget.fit,
                        child: SizedBox(
                          width: _safeVideoWidth,
                          height: _safeVideoHeight,
                          child: VideoPlayer(_controller!),
                        ),
                      )
                    else
                      const SizedBox.shrink(),
                    if (_initializing) const _VideoLoadingOverlay(),
                    if (_failed) const _VideoErrorOverlay(),
                    if (_isReady)
                      _CenterVideoButton(
                        visible: showControls,
                        compact: controlCompact,
                        playing: _controller!.value.isPlaying,
                        onTap: _togglePlay,
                      ),
                    if (_isReady)
                      _VideoControlsOverlay(
                        visible: showControls,
                        compact: controlCompact,
                        value: _controller!.value,
                        muted: _muted,
                        hasOpenAction: widget.onOpen != null,
                        onTogglePlay: _togglePlay,
                        onToggleMute: _toggleMute,
                        onOpen: widget.onOpen,
                        onSeekBy: _seekBy,
                        onSeekStart: () {
                          _controlsTimer?.cancel();
                          setState(() => _seeking = true);
                        },
                        onSeekChanged: _seekToFraction,
                        onSeekEnd: () {
                          setState(() => _seeking = false);
                          _scheduleControlsHide();
                        },
                      ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  double get _safeVideoWidth {
    final width = _controller?.value.size.width ?? 1;
    if (width.isFinite && width > 0) return width;
    return 1;
  }

  double get _safeVideoHeight {
    final height = _controller?.value.size.height ?? 1;
    if (height.isFinite && height > 0) return height;
    return 1;
  }
}

class _CenterVideoButton extends StatelessWidget {
  const _CenterVideoButton({
    required this.visible,
    required this.compact,
    required this.playing,
    required this.onTap,
  });

  final bool visible;
  final bool compact;
  final bool playing;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      ignoring: !visible,
      child: AnimatedOpacity(
        opacity: visible ? 1 : 0,
        duration: const Duration(milliseconds: 180),
        child: Center(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onTap,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              width: compact ? 46 : 60,
              height: compact ? 46 : 60,
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.45),
                shape: BoxShape.circle,
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.28),
                ),
              ),
              child: Icon(
                playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                color: Colors.white,
                size: compact ? 28 : 38,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _VideoControlsOverlay extends StatelessWidget {
  const _VideoControlsOverlay({
    required this.visible,
    required this.compact,
    required this.value,
    required this.muted,
    required this.hasOpenAction,
    required this.onTogglePlay,
    required this.onToggleMute,
    required this.onOpen,
    required this.onSeekBy,
    required this.onSeekStart,
    required this.onSeekChanged,
    required this.onSeekEnd,
  });

  final bool visible;
  final bool compact;
  final VideoPlayerValue value;
  final bool muted;
  final bool hasOpenAction;
  final VoidCallback onTogglePlay;
  final VoidCallback onToggleMute;
  final VoidCallback? onOpen;
  final Future<void> Function(Duration delta) onSeekBy;
  final VoidCallback onSeekStart;
  final Future<void> Function(double fraction) onSeekChanged;
  final VoidCallback onSeekEnd;

  @override
  Widget build(BuildContext context) {
    final duration = value.duration;
    final position = value.position > duration ? duration : value.position;
    final hasDuration = duration > Duration.zero;
    final progress =
        hasDuration ? position.inMilliseconds / duration.inMilliseconds : 0.0;

    return IgnorePointer(
      ignoring: !visible,
      child: AnimatedOpacity(
        opacity: visible ? 1 : 0,
        duration: const Duration(milliseconds: 180),
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.bottomCenter,
              end: Alignment.topCenter,
              colors: [
                Colors.black.withValues(alpha: 0.62),
                Colors.black.withValues(alpha: 0.18),
                Colors.transparent,
              ],
              stops: const [0, 0.58, 1],
            ),
          ),
          child: Align(
            alignment: Alignment.bottomCenter,
            child: SafeArea(
              top: false,
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  compact ? 8 : 12,
                  28,
                  compact ? 8 : 12,
                  compact ? 8 : 10,
                ),
                child: compact
                    ? _CompactVideoControls(
                        playing: value.isPlaying,
                        muted: muted,
                        progress: progress,
                        hasOpenAction: hasOpenAction,
                        onTogglePlay: onTogglePlay,
                        onToggleMute: onToggleMute,
                        onOpen: onOpen,
                        onSeekStart: onSeekStart,
                        onSeekChanged: onSeekChanged,
                        onSeekEnd: onSeekEnd,
                      )
                    : _FullVideoControls(
                        playing: value.isPlaying,
                        muted: muted,
                        progress: progress,
                        position: position,
                        duration: duration,
                        hasOpenAction: hasOpenAction,
                        onTogglePlay: onTogglePlay,
                        onToggleMute: onToggleMute,
                        onOpen: onOpen,
                        onSeekBy: onSeekBy,
                        onSeekStart: onSeekStart,
                        onSeekChanged: onSeekChanged,
                        onSeekEnd: onSeekEnd,
                      ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _CompactVideoControls extends StatelessWidget {
  const _CompactVideoControls({
    required this.playing,
    required this.muted,
    required this.progress,
    required this.hasOpenAction,
    required this.onTogglePlay,
    required this.onToggleMute,
    required this.onOpen,
    required this.onSeekStart,
    required this.onSeekChanged,
    required this.onSeekEnd,
  });

  final bool playing;
  final bool muted;
  final double progress;
  final bool hasOpenAction;
  final VoidCallback onTogglePlay;
  final VoidCallback onToggleMute;
  final VoidCallback? onOpen;
  final VoidCallback onSeekStart;
  final Future<void> Function(double fraction) onSeekChanged;
  final VoidCallback onSeekEnd;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _RoundVideoButton(
          icon: playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
          onTap: onTogglePlay,
        ),
        Expanded(
          child: _VideoSeekBar(
            value: progress,
            compact: true,
            onSeekStart: onSeekStart,
            onSeekChanged: onSeekChanged,
            onSeekEnd: onSeekEnd,
          ),
        ),
        _RoundVideoButton(
          icon: muted ? Icons.volume_off_rounded : Icons.volume_up_rounded,
          onTap: onToggleMute,
        ),
        if (hasOpenAction && onOpen != null)
          _RoundVideoButton(
            icon: Icons.open_in_full_rounded,
            onTap: onOpen!,
          ),
      ],
    );
  }
}

class _FullVideoControls extends StatelessWidget {
  const _FullVideoControls({
    required this.playing,
    required this.muted,
    required this.progress,
    required this.position,
    required this.duration,
    required this.hasOpenAction,
    required this.onTogglePlay,
    required this.onToggleMute,
    required this.onOpen,
    required this.onSeekBy,
    required this.onSeekStart,
    required this.onSeekChanged,
    required this.onSeekEnd,
  });

  final bool playing;
  final bool muted;
  final double progress;
  final Duration position;
  final Duration duration;
  final bool hasOpenAction;
  final VoidCallback onTogglePlay;
  final VoidCallback onToggleMute;
  final VoidCallback? onOpen;
  final Future<void> Function(Duration delta) onSeekBy;
  final VoidCallback onSeekStart;
  final Future<void> Function(double fraction) onSeekChanged;
  final VoidCallback onSeekEnd;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Text(
              _formatVideoDuration(position),
              style: _timeStyle,
            ),
            Expanded(
              child: _VideoSeekBar(
                value: progress,
                compact: false,
                onSeekStart: onSeekStart,
                onSeekChanged: onSeekChanged,
                onSeekEnd: onSeekEnd,
              ),
            ),
            Text(
              _formatVideoDuration(duration),
              style: _timeStyle,
            ),
          ],
        ),
        const SizedBox(height: 4),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _RoundVideoButton(
              icon: Icons.replay_10_rounded,
              onTap: () => onSeekBy(const Duration(seconds: -10)),
            ),
            _RoundVideoButton(
              icon: playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
              onTap: onTogglePlay,
              large: true,
            ),
            _RoundVideoButton(
              icon: Icons.forward_10_rounded,
              onTap: () => onSeekBy(const Duration(seconds: 10)),
            ),
            const SizedBox(width: AppSpacing.xs),
            _RoundVideoButton(
              icon: muted ? Icons.volume_off_rounded : Icons.volume_up_rounded,
              onTap: onToggleMute,
            ),
            if (hasOpenAction && onOpen != null)
              _RoundVideoButton(
                icon: Icons.open_in_full_rounded,
                onTap: onOpen!,
              ),
          ],
        ),
      ],
    );
  }
}

class _VideoSeekBar extends StatelessWidget {
  const _VideoSeekBar({
    required this.value,
    required this.compact,
    required this.onSeekStart,
    required this.onSeekChanged,
    required this.onSeekEnd,
  });

  final double value;
  final bool compact;
  final VoidCallback onSeekStart;
  final Future<void> Function(double fraction) onSeekChanged;
  final VoidCallback onSeekEnd;

  @override
  Widget build(BuildContext context) {
    return SliderTheme(
      data: SliderTheme.of(context).copyWith(
        trackHeight: compact ? 2 : 3,
        thumbShape: RoundSliderThumbShape(enabledThumbRadius: compact ? 4 : 5),
        overlayShape: RoundSliderOverlayShape(overlayRadius: compact ? 10 : 14),
        activeTrackColor: AppColors.fernGreen,
        inactiveTrackColor: Colors.white.withValues(alpha: 0.32),
        thumbColor: Colors.white,
        overlayColor: AppColors.fernGreen.withValues(alpha: 0.18),
      ),
      child: Slider(
        min: 0,
        max: 1,
        value: value.isFinite ? value.clamp(0.0, 1.0).toDouble() : 0,
        onChangeStart: (_) => onSeekStart(),
        onChanged: (next) => onSeekChanged(next),
        onChangeEnd: (_) => onSeekEnd(),
      ),
    );
  }
}

class _RoundVideoButton extends StatelessWidget {
  const _RoundVideoButton({
    required this.icon,
    required this.onTap,
    this.large = false,
  });

  final IconData icon;
  final VoidCallback onTap;
  final bool large;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        width: large ? 42 : 34,
        height: large ? 42 : 34,
        margin: const EdgeInsets.symmetric(horizontal: 2),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.54),
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
        ),
        child: Icon(icon, size: large ? 24 : 18, color: Colors.white),
      ),
    );
  }
}

String _formatVideoDuration(Duration duration) {
  final safe = duration.isNegative ? Duration.zero : duration;
  final minutes = safe.inMinutes.remainder(60).toString().padLeft(2, '0');
  final seconds = safe.inSeconds.remainder(60).toString().padLeft(2, '0');
  final hours = safe.inHours;
  if (hours > 0) {
    return '$hours:$minutes:$seconds';
  }
  return '$minutes:$seconds';
}

TextStyle get _timeStyle => TextStyle(
      color: Colors.white.withValues(alpha: 0.82),
      fontSize: 11,
      fontWeight: FontWeight.w600,
      height: 1,
    );

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
