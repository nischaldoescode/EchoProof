// echo video screen
// @params none

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../../app/theme/colors.dart';
import '../../../../app/theme/spacing.dart';
import '../../../../core/services/video_playback_coordinator.dart';
import '../../../../core/localization/app_copy.dart';
import '../../../../core/utils/snack.dart';
import '../widgets/echo_video_player.dart';

class EchoVideoScreen extends StatefulWidget {
  const EchoVideoScreen({
    super.key,
    required this.echoId,
    required this.videoUrl,
  });

  final String echoId;
  final String videoUrl;

  @override
  State<EchoVideoScreen> createState() => _EchoVideoScreenState();
}

class _EchoVideoScreenState extends State<EchoVideoScreen> {
  @override
  void initState() {
    super.initState();
    VideoPlaybackCoordinator.instance.pauseAll();
    if (widget.videoUrl.trim().isEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          showErrorSnack(context, context.l('Video link is missing.'));
        }
      });
    }
  }

  @override
  void dispose() {
    VideoPlaybackCoordinator.instance.pauseAll();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.charcoal,
      body: SafeArea(
        child: Stack(
          children: [
            Center(
              child: widget.videoUrl.trim().isEmpty
                  ? const Icon(
                      Icons.videocam_off_outlined,
                      color: Colors.white70,
                      size: 48,
                    )
                  : AspectRatio(
                      aspectRatio: 9 / 16,
                      child: EchoVideoPlayer(
                        url: widget.videoUrl,
                        playbackId: 'video_full_${widget.echoId}',
                        initiallyMuted: false,
                        borderRadius: 0,
                        fit: BoxFit.contain,
                        compact: false,
                      ),
                    ),
            ),
            Positioned(
              top: AppSpacing.sm,
              left: AppSpacing.sm,
              child: IconButton(
                onPressed: () => context.pop(),
                icon: const Icon(Icons.arrow_back_rounded),
                color: Colors.white,
                style: IconButton.styleFrom(
                  backgroundColor: Colors.black.withValues(alpha: 0.34),
                ),
                tooltip: context.l('Back to echo'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
