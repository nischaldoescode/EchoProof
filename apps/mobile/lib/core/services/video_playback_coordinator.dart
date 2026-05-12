import 'package:flutter/foundation.dart';

class VideoPlaybackCoordinator {
  VideoPlaybackCoordinator._();

  static final VideoPlaybackCoordinator instance = VideoPlaybackCoordinator._();

  final ValueNotifier<String?> activeVideoId = ValueNotifier<String?>(null);

  void requestPlay(String id) {
    if (activeVideoId.value == id) return;
    activeVideoId.value = id;
  }

  void pauseAll() {
    if (activeVideoId.value == null) return;
    activeVideoId.value = null;
  }

  void release(String id) {
    if (activeVideoId.value == id) activeVideoId.value = null;
  }
}
