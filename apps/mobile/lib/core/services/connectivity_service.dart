// connectivity service
// @params none

import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import '../utils/logger.dart';

class ConnectivityService {
  static final ConnectivityService instance = ConnectivityService._();
  ConnectivityService._();

  StreamSubscription<List<ConnectivityResult>>? _subscription;
  bool _isOnline = true;
  bool get isOnline => _isOnline;

  final _controller = StreamController<bool>.broadcast();
  Stream<bool> get onConnectivityChanged => _controller.stream;

  Future<void> initialize() async {
    final results = await Connectivity().checkConnectivity();
    _isOnline = results.any((r) => r != ConnectivityResult.none);

    _subscription = Connectivity().onConnectivityChanged.listen((results) {
      final wasOnline = _isOnline;
      _isOnline = results.any((r) => r != ConnectivityResult.none);
      if (wasOnline != _isOnline) {
        _controller.add(_isOnline);
        AppLogger.info('connectivity: ${_isOnline ? "online" : "offline"}');
      }
    });
  }

  void dispose() {
    _subscription?.cancel();
    _controller.close();
  }
}
