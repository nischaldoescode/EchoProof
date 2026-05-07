// create echo service
// manages form state and echo submission
// replaces: create_echo_provider.dart (riverpod version)

import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../domain/entities/echo_entity.dart';
import '../../../../core/utils/logger.dart';
import 'dart:io';

const _kDraftKey = 'echo_draft';

class CreateEchoService extends ChangeNotifier {
  String _title = '';
  String _content = '';
  EchoCategory? _category;
  bool _requiresVerification = true;
  bool _isSubmitting = false;
  bool _success = false;
  String? _error;
  int _echoesCreatedThisSession = 0;

  String get title => _title;
  String get content => _content;
  EchoCategory? get category => _category;
  bool get requiresVerification => _requiresVerification;
  bool get isSubmitting => _isSubmitting;
  bool get success => _success;
  String? get error => _error;
  int get echoesCreatedThisSession => _echoesCreatedThisSession;
  bool get canSubmit =>
      _title.trim().isNotEmpty &&
      _content.trim().isNotEmpty &&
      _category != null &&
      !_isSubmitting;

  final List<String> _mediaUrls = [];
  List<String> get mediaUrls => List.unmodifiable(_mediaUrls);

  // Local file paths for preview before upload.
  final List<String> _localPaths = [];
  List<String> get localMediaPaths => List.unmodifiable(_localPaths);

  Future<void> addMedia(String localPath, bool isVideo) async {
    // upload to supabase storage
    try {
      final client = Supabase.instance.client;
      final userId = client.auth.currentUser?.id;
      if (userId == null) return;

      final ext = localPath.split('.').last;
      final name = '${DateTime.now().millisecondsSinceEpoch}.$ext';
      final path = 'echoes/$userId/$name';
      final file = File(localPath);

      await client.storage.from('echo-media').upload(path, file);

      final url = client.storage.from('echo-media').getPublicUrl(path);
      _mediaUrls.add(url);
      notifyListeners();

      AppLogger.info('echo: media uploaded $url');
    } catch (e) {
      AppLogger.error('echo: media upload failed $e');
    }
  }

  void addLocalMedia(String path) {
    if (_localPaths.length < 2) {
      _localPaths.add(path);
      notifyListeners();
    }
  }

  void removeLocalMedia(int index) {
    if (index < _localPaths.length) {
      _localPaths.removeAt(index);
      notifyListeners();
    }
  }

  void removeMedia(int index) {
    if (index < _mediaUrls.length) {
      _mediaUrls.removeAt(index);
    }
    if (index < _localPaths.length) {
      _localPaths.removeAt(index);
    }
    notifyListeners();
  }

  CreateEchoService() {
    _restoreDraft();
  }

  void setTitle(String v) {
    _title = v;
    _saveDraft();
    notifyListeners();
  }

  void setContent(String v) {
    _content = v;
    _saveDraft();
    notifyListeners();
  }

  void setCategory(EchoCategory c) {
    _category = c;
    notifyListeners();
  }

  void toggleVerification() {
    _requiresVerification = !_requiresVerification;
    notifyListeners();
  }

  void resetSuccess() {
    reset();
    notifyListeners();
  }

  void reset() {
    _title = '';
    _content = '';
    _category = null;
    _mediaUrls.clear();
    _localPaths.clear();
    _error = null;
    _isSubmitting = false;
    _success = false;

    notifyListeners();
  }

  Future<void> submit() async {
    if (!canSubmit) return;

    _isSubmitting = true;
    _error = null;
    notifyListeners();

    try {
      final client = Supabase.instance.client;
      final userId = client.auth.currentUser?.id;
      if (userId == null) throw Exception('not authenticated');

      await client.from('echoes').insert({
        'user_id': userId,
        'title': _title.trim(),
        'content': _content.trim(),
        'category': _category!.name,
        'verification_required': _requiresVerification,
        'status': 'pending_verification',
      });

      _echoesCreatedThisSession++;

      await Hive.box('app_settings').delete(_kDraftKey);

      _title = '';
      _content = '';
      _mediaUrls.clear();
      _localPaths.clear();
      _category = null;
      _success = true;

      AppLogger.info('echo: created successfully');
    } catch (e) {
      _error = 'failed to create echo, try again';
      AppLogger.error('echo: create failed', e);
    }

    _isSubmitting = false;
    notifyListeners();
  }

  void _saveDraft() {
    Hive.box('app_settings').put(_kDraftKey, {
      'title': _title,
      'content': _content,
    });
  }

  void _restoreDraft() {
    final draft = Hive.box('app_settings').get(_kDraftKey) as Map?;
    if (draft != null) {
      _title = draft['title'] as String? ?? '';
      _content = draft['content'] as String? ?? '';
    }
  }
}
