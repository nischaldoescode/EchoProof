// create echo service
// manages form state and echo submission
// replaces: create_echo_provider.dart (riverpod version)

import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../domain/entities/echo_entity.dart';
import '../../../../core/utils/logger.dart';
import '../../../../core/utils/media_file_safety.dart';
import '../../../../core/utils/sanitizer.dart';
import '../../../../core/services/onnx_spam_checker.dart';

const _kDraftKey = 'echo_draft';

class CreateEchoService extends ChangeNotifier {
  String _title = '';
  String _content = '';
  EchoCategory? _category;
  String _categoryDetail = '';
  bool _requiresVerification = true;
  bool _isSubmitting = false;
  bool _success = false;
  String? _error;
  int _echoesCreatedThisSession = 0;

  String get title => _title;
  String get content => _content;
  EchoCategory? get category => _category;
  String get categoryDetail => _categoryDetail;
  bool get requiresVerification => _requiresVerification;
  bool get isSubmitting => _isSubmitting;
  bool get success => _success;
  String? get error => _error;
  int get echoesCreatedThisSession => _echoesCreatedThisSession;
  bool _isPro = false;
  bool get isPro => _isPro;

  // Call this from the screen after subscription status is known.
  void setProStatus(bool isPro) {
    if (_isPro == isPro) return;
    _isPro = isPro;
    notifyListeners();
  }

  int get contentMaxLength => _isPro ? 5000 : 308;
  int get titleMaxLength => _isPro ? 200 : 120;

  bool get canSubmit =>
      _title.trim().isNotEmpty &&
      _content.trim().isNotEmpty &&
      _category != null &&
      (_category != EchoCategory.other ||
          (_categoryDetail.trim().isNotEmpty &&
              _categoryDetail.trim().length <= 10)) &&
      !_isSubmitting &&
      _content.length <= contentMaxLength &&
      _title.length <= titleMaxLength;

  final List<String> _mediaUrls = [];
  List<String> get mediaUrls => List.unmodifiable(_mediaUrls);

  // Local file paths for preview before upload.
  final List<String> _localPaths = [];
  List<String> get localMediaPaths => List.unmodifiable(_localPaths);

  Future<void> addMedia(String localPath) async {
    // upload to supabase storage
    try {
      final client = Supabase.instance.client;
      final userId = client.auth.currentUser?.id;
      if (userId == null) return;

      final ext = MediaFileSafety.extensionOf(localPath);
      // Rename to UUID to strip original filename metadata
      final uuid = DateTime.now().millisecondsSinceEpoch.toRadixString(16);
      final name = '$uuid.$ext';
      final path = '$userId/$name';
      final file = File(localPath);

      await client.storage.from('media').uploadBinary(
            path,
            await file.readAsBytes(),
            fileOptions: FileOptions(
              contentType: MediaFileSafety.contentTypeForExtension(ext),
              upsert: false,
            ),
          );

      final url = client.storage.from('media').getPublicUrl(path);
      _mediaUrls.add(url);
      notifyListeners();

      AppLogger.info('echo: media uploaded $url');
    } catch (e) {
      AppLogger.error('echo: media upload failed $e');
      throw Exception('media upload failed');
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
    if (c != EchoCategory.other && _categoryDetail.isNotEmpty) {
      _categoryDetail = '';
    }
    _saveDraft();
    notifyListeners();
  }

  void setCategoryDetail(String value) {
    _categoryDetail = Sanitizer.text(value).trim();
    if (_categoryDetail.length > 10) {
      _categoryDetail = _categoryDetail.substring(0, 10);
    }
    _saveDraft();
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

  void clearError() {
    if (_error == null) return;
    _error = null;
    notifyListeners();
  }

  void reset() {
    _title = '';
    _content = '';
    _category = null;
    _categoryDetail = '';
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

      final cooldown = await _getCooldownStatus(
        client,
        action: 'create_echo',
        subject: userId,
        windowSeconds: 10 * 60,
        maxActions: 3,
      );
      if (cooldown.retryAfterSeconds > 0) {
        throw _CooldownException(
          'You can post another echo in ${_formatCooldown(cooldown.retryAfterSeconds)}.',
        );
      }

      final localModeration = await _safeLocalModerationCheck();
      if (localModeration.isSpam) {
        throw _LocalModerationException(
          'This echo looks too spam-like to publish (${localModeration.score}%). Add clearer evidence, remove promotional language, and try again.',
        );
      }

      _mediaUrls.clear();
      for (final path in List<String>.from(_localPaths)) {
        await addMedia(path);
      }

      final inserted = await client
          .from('echoes')
          .insert({
            'user_id': userId,
            'title': Sanitizer.text(_title),
            'content': Sanitizer.text(_content),
            'category': _category!.dbValue,
            'category_detail': _category == EchoCategory.other
                ? Sanitizer.text(_categoryDetail).trim()
                : null,
            'verification_required': _requiresVerification,
            'status': 'pending_verification',
            'media_urls': _mediaUrls,
          })
          .select('id')
          .single();

      unawaited(_anchorEchoOnChain(client, inserted['id'] as String));

      _echoesCreatedThisSession++;

      await Hive.box('app_settings').delete(_kDraftKey);

      _title = '';
      _content = '';
      _mediaUrls.clear();
      _localPaths.clear();
      _category = null;
      _categoryDetail = '';
      _success = true;

      AppLogger.info('echo: created successfully');
    } on _CooldownException catch (e) {
      _error = e.message;
      AppLogger.warn('echo: create cooldown ${e.message}');
    } on _LocalModerationException catch (e) {
      _error = e.message;
      AppLogger.warn('echo: local moderation blocked post ${e.message}');
    } on PostgrestException catch (e) {
      _error = _friendlyCreateError(e);
      AppLogger.error('echo: create failed', e);
    } catch (e) {
      _error = 'failed to create echo, try again';
      AppLogger.error('echo: create failed', e);
    }

    _isSubmitting = false;
    notifyListeners();
  }

  Future<SpamCheckResult> _safeLocalModerationCheck() async {
    try {
      return await OnnxSpamChecker.checkText(_title, _content);
    } catch (e) {
      AppLogger.error('echo: local moderation crashed to fallback', e);
      final score = OnnxSpamChecker.quickScore(_title, _content);
      return SpamCheckResult(
        label: score >= OnnxSpamChecker.blockThreshold
            ? SpamLabel.spam
            : score >= OnnxSpamChecker.suspiciousThreshold
                ? SpamLabel.suspicious
                : SpamLabel.ham,
        score: score,
        spamProbability: score / 100,
        hamProbability: 1 - (score / 100),
        source: 'heuristic_after_error',
        tokenCount: 0,
        windowCount: 0,
        reason: 'local_moderation_exception',
      );
    }
  }

  Future<void> _anchorEchoOnChain(SupabaseClient client, String echoId) async {
    try {
      final response = await client.functions.invoke(
        'solana-memo',
        body: {
          'kind': 'echo_created',
          'echo_id': echoId,
        },
      );
      AppLogger.info('echo: solana anchor requested ${response.data}');
    } catch (e) {
      AppLogger.warn('echo: solana anchor will remain pending $e');
    }
  }

  void _saveDraft() {
    Hive.box('app_settings').put(_kDraftKey, {
      'title': _title,
      'content': _content,
      'category': _category?.dbValue,
      'category_detail': _categoryDetail,
    });
  }

  void _restoreDraft() {
    final draft = Hive.box('app_settings').get(_kDraftKey) as Map?;
    if (draft != null) {
      _title = draft['title'] as String? ?? '';
      _content = draft['content'] as String? ?? '';
      final category = draft['category'] as String?;
      if (category != null) _category = EchoCategory.fromString(category);
      _categoryDetail = draft['category_detail'] as String? ?? '';
    }
  }

  Future<_CooldownStatus> _getCooldownStatus(
    SupabaseClient client, {
    required String action,
    required String subject,
    required int windowSeconds,
    required int maxActions,
  }) async {
    try {
      final response = await client.rpc('get_action_cooldown_status', params: {
        'p_action': action,
        'p_subject': subject,
        'p_window_seconds': windowSeconds,
        'p_max_actions': maxActions,
        'p_include_ip': false,
      });
      final map = Map<String, dynamic>.from(response as Map);
      final retryAfter = (map['retry_after_seconds'] as num?)?.toInt() ?? 0;
      return _CooldownStatus(retryAfterSeconds: retryAfter);
    } catch (e) {
      AppLogger.warn(
          'echo: cooldown status unavailable, relying on insert guard $e');
      return const _CooldownStatus(retryAfterSeconds: 0);
    }
  }

  String _friendlyCreateError(PostgrestException e) {
    final message = e.message.toLowerCase();
    final details = e.details?.toString() ?? '';
    if (message.contains('create_echo_cooldown')) {
      final seconds = int.tryParse(RegExp(r'\d+').stringMatch(details) ?? '');
      return seconds == null || seconds <= 0
          ? 'Please wait before posting another echo.'
          : 'You can post another echo in ${_formatCooldown(seconds)}.';
    }
    if (message.contains('echo_category_detail')) {
      return 'When category is Other, add a short field name under 10 characters.';
    }
    return 'failed to create echo, try again';
  }

  String _formatCooldown(int seconds) {
    final minutes = (seconds / 60).ceil();
    if (minutes <= 1) return '$seconds seconds';
    return '$minutes minutes';
  }
}

class _CooldownStatus {
  const _CooldownStatus({required this.retryAfterSeconds});
  final int retryAfterSeconds;
}

class _CooldownException implements Exception {
  const _CooldownException(this.message);
  final String message;
}

class _LocalModerationException implements Exception {
  const _LocalModerationException(this.message);
  final String message;
}
