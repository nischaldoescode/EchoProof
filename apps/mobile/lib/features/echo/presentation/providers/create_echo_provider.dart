// create echo provider
// manages the create echo form state + submission
// handles draft saving to hive so crashes don't lose user content

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../domain/entities/echo_entity.dart';
import '../../../auth/presentation/providers/auth_provider.dart';

const _kDraftKey = 'echo_draft';

class CreateEchoState {
  const CreateEchoState({
    this.title = '',
    this.content = '',
    this.category,
    this.requiresVerification = true,
    this.isSubmitting = false,
    this.error,
    this.success = false,
  });

  final String title;
  final String content;
  final EchoCategory? category;
  final bool requiresVerification;
  final bool isSubmitting;
  final String? error;
  final bool success;

  bool get canSubmit =>
    title.trim().isNotEmpty &&
    content.trim().isNotEmpty &&
    category != null &&
    !isSubmitting;

  CreateEchoState copyWith({
    String? title,
    String? content,
    EchoCategory? category,
    bool? requiresVerification,
    bool? isSubmitting,
    String? error,
    bool? success,
  }) {
    return CreateEchoState(
      title: title ?? this.title,
      content: content ?? this.content,
      category: category ?? this.category,
      requiresVerification: requiresVerification ?? this.requiresVerification,
      isSubmitting: isSubmitting ?? this.isSubmitting,
      error: error,
      success: success ?? this.success,
    );
  }
}

class CreateEchoNotifier extends Notifier<CreateEchoState> {
  @override
  CreateEchoState build() {
    // restore draft on build
    _restoreDraft();
    return const CreateEchoState();
  }

  void setTitle(String value)   => _saveDraftAndUpdate(state.copyWith(title: value));
  void setContent(String value) => _saveDraftAndUpdate(state.copyWith(content: value));
  void setCategory(EchoCategory cat) => state = state.copyWith(category: cat);
  void toggleVerification()     => state = state.copyWith(requiresVerification: !state.requiresVerification);

  /// submits the echo to supabase
  Future<void> submit() async {
    if (!state.canSubmit) return;

    state = state.copyWith(isSubmitting: true, error: null);

    try {
      final userId = ref.read(currentUserIdProvider);
      final client = ref.read(supabaseProvider);

      await client.from('echoes').insert({
        'user_id': userId,
        'title': state.title.trim(),
        'content': state.content.trim(),
        'category': state.category!.name,
        'verification_required': state.requiresVerification,
        'status': 'pending_verification',
      });

      // clear draft on success
      await Hive.box('app_settings').delete(_kDraftKey);

      state = state.copyWith(isSubmitting: false, success: true);
    } on PostgrestException catch (e) {
      state = state.copyWith(isSubmitting: false, error: e.message);
    } catch (_) {
      state = state.copyWith(isSubmitting: false, error: 'something went wrong, try again');
    }
  }

  void _saveDraftAndUpdate(CreateEchoState newState) {
    state = newState;
    // auto-save draft to hive so a crash doesn't lose the user's work
    Hive.box('app_settings').put(_kDraftKey, {
      'title': newState.title,
      'content': newState.content,
    });
  }

  void _restoreDraft() {
    final box = Hive.box('app_settings');
    final draft = box.get(_kDraftKey) as Map?;
    if (draft != null) {
      state = state.copyWith(
        title: draft['title'] as String? ?? '',
        content: draft['content'] as String? ?? '',
      );
    }
  }
}

final createEchoProvider = NotifierProvider<CreateEchoNotifier, CreateEchoState>(
  CreateEchoNotifier.new,
);