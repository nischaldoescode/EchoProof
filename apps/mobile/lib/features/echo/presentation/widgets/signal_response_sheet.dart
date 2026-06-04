// signal response sheet
// @params none

import 'dart:io';
import 'package:echoproof/core/utils/snack.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../app/theme/colors.dart';
import '../../../../app/theme/spacing.dart';
import '../../../../app/theme/typography.dart';
import '../../../../core/utils/logger.dart';
import '../../../../core/utils/media_file_safety.dart';

void showSignalResponseSheet({
  required BuildContext context,
  required String echoId,
  String initialStance = 'support',
  required Future<void> Function() onPosted,
}) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: AppColors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(
        top: Radius.circular(AppSpacing.radiusLg),
      ),
    ),
    builder: (_) => _SignalResponseSheet(
      echoId: echoId,
      initialStance: initialStance,
      onPosted: onPosted,
    ),
  );
}

class _SignalResponseSheet extends StatefulWidget {
  const _SignalResponseSheet({
    required this.echoId,
    required this.initialStance,
    required this.onPosted,
  });

  final String echoId;
  final String initialStance;
  final Future<void> Function() onPosted;

  @override
  State<_SignalResponseSheet> createState() => _SignalResponseSheetState();
}

class _SignalResponseSheetState extends State<_SignalResponseSheet> {
  final _controller = TextEditingController();
  final List<_ContextMedia> _media = [];
  late String _stance;
  bool _submitting = false;
  bool _loadingExisting = true;
  bool _hasExisting = false;
  int _editCount = 0;
  List<String> _existingMediaUrls = const [];
  List<String> _existingMediaTypes = const [];

  static const _stances = [
    (
      value: 'support',
      label: 'Supporting',
      icon: Icons.thumb_up_alt_outlined,
      color: AppColors.fernGreen,
    ),
    (
      value: 'challenge',
      label: 'Challenging',
      icon: Icons.report_problem_outlined,
      color: AppColors.sunsetCoral,
    ),
  ];

  @override
  void initState() {
    super.initState();
    _stance = widget.initialStance == 'challenge' ? 'challenge' : 'support';
    _loadExistingResponse();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final content = _controller.text.trim();
    if (content.length < 10 || _submitting || _loadingExisting) return;
    if (showOfflineSnackIfNeeded(context)) return;
    if (_hasExisting && _editCount >= 1) {
      showInfoSnack(context, 'You already edited this context once.');
      return;
    }

    setState(() => _submitting = true);
    HapticFeedback.lightImpact();

    try {
      final client = Supabase.instance.client;
      final userId = client.auth.currentUser?.id;
      if (userId == null) throw Exception('not authenticated');

      final uploadedUrls =
          _media.isEmpty ? List<String>.from(_existingMediaUrls) : <String>[];
      final uploadedTypes =
          _media.isEmpty ? List<String>.from(_existingMediaTypes) : <String>[];
      for (final item in _media) {
        final url = await _uploadMedia(client, userId, item);
        uploadedUrls.add(url);
        uploadedTypes.add(item.kind == MediaFileKind.video ? 'video' : 'image');
      }

      await client.functions.invoke(
        'on-signal-response',
        body: {
          'echo_id': widget.echoId,
          'stance': _stance,
          'content': content,
          'media_urls': uploadedUrls,
          'media_types': uploadedTypes,
        },
      );

      AppLogger.info('signal response posted for echo ${widget.echoId}');

      if (mounted) {
        Navigator.pop(context);
        await widget.onPosted();
      }
    } catch (e) {
      AppLogger.error('signal response failed', e);
      if (mounted) {
        showErrorSnack(context, _friendlyError(e));
        setState(() => _submitting = false);
      }
    }
  }

  Future<void> _loadExistingResponse() async {
    try {
      final client = Supabase.instance.client;
      final userId = client.auth.currentUser?.id;
      if (userId == null) return;

      final row = await client
          .from('signal_responses')
          .select('content, stance, edit_count, media_urls, media_types')
          .eq('echo_id', widget.echoId)
          .eq('user_id', userId)
          .filter('stance', 'in', '("support","challenge")')
          .maybeSingle();

      if (!mounted || row == null) return;
      final existingStance = row['stance'] as String? ?? _stance;
      setState(() {
        _hasExisting = true;
        _editCount = (row['edit_count'] as num?)?.toInt() ?? 0;
        _stance = existingStance == 'challenge' ? 'challenge' : 'support';
        _controller.text = row['content'] as String? ?? '';
        _existingMediaUrls =
            (row['media_urls'] as List?)?.cast<String>() ?? const [];
        _existingMediaTypes =
            (row['media_types'] as List?)?.cast<String>() ?? const [];
      });
    } catch (e) {
      AppLogger.warn('signal response: existing context load failed');
    } finally {
      if (mounted) setState(() => _loadingExisting = false);
    }
  }

  Future<void> _pickMedia(bool isVideo) async {
    if (_media.length >= 2) {
      showInfoSnack(context, 'Maximum 2 attachments allowed');
      return;
    }

    final picker = ImagePicker();
    final file = isVideo
        ? await picker.pickVideo(source: ImageSource.gallery)
        : await picker.pickImage(
            source: ImageSource.gallery,
            imageQuality: 72,
            maxWidth: 1280,
            maxHeight: 1280,
          );
    if (file == null || !mounted) return;

    final kind = isVideo ? MediaFileKind.video : MediaFileKind.image;
    final validation = await MediaFileSafety.validateLocalFile(
      file.path,
      expectedKind: kind,
    );
    if (!mounted) return;
    if (!validation.isValid) {
      showErrorSnack(context, validation.error ?? 'Invalid attachment.');
      return;
    }

    setState(() => _media.add(_ContextMedia(path: file.path, kind: kind)));
    HapticFeedback.selectionClick();
  }

  Future<String> _uploadMedia(
    SupabaseClient client,
    String userId,
    _ContextMedia item,
  ) async {
    final ext = MediaFileSafety.extensionOf(item.path);
    final nonce = DateTime.now().microsecondsSinceEpoch.toRadixString(16);
    final path = '$userId/context/$nonce.$ext';
    final file = File(item.path);

    await client.storage.from('media').uploadBinary(
          path,
          await file.readAsBytes(),
          fileOptions: FileOptions(
            contentType: MediaFileSafety.contentTypeForExtension(ext),
            upsert: false,
          ),
        );

    return client.storage.from('media').getPublicUrl(path);
  }

  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    final maxSheetHeight = mediaQuery.size.height * 0.9;

    return Padding(
      padding: EdgeInsets.only(bottom: mediaQuery.viewInsets.bottom),
      child: SafeArea(
        top: false,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: maxSheetHeight),
          child: SingleChildScrollView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            padding: const EdgeInsets.all(AppSpacing.xl),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: AppSpacing.lg),
                    decoration: BoxDecoration(
                      color: AppColors.borderMedium,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                Text(
                  _loadingExisting
                      ? 'Checking your context'
                      : _hasExisting
                          ? 'Edit your context'
                          : _stance == 'support'
                              ? 'Support with context'
                              : 'Challenge with context',
                  style: AppTypography.textTheme.titleMedium,
                ),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  _loadingExisting
                      ? 'Looking for your existing support or challenge on this echo.'
                      : _hasExisting
                          ? _editCount >= 1
                              ? 'You already used your one edit. Your context remains visible in echo details.'
                              : 'You can edit this ${_stance == 'support' ? 'support' : 'challenge'} once. You cannot add the opposite side on the same echo.'
                          : 'Explain why. Other users can like your context, and the public evaluation decides the echo.',
                  style: AppTypography.textTheme.bodySmall,
                ),
                if (_loadingExisting) ...[
                  const SizedBox(height: AppSpacing.md),
                  const LinearProgressIndicator(minHeight: 2),
                ],
                const SizedBox(height: AppSpacing.lg),
                _StanceSegmentedControl(
                  stances: _stances,
                  selected: _stance,
                  locked: _loadingExisting || _hasExisting,
                  onChanged: (value) => setState(() => _stance = value),
                  onLockedTap: () {
                    if (_loadingExisting) return;
                    showInfoSnack(
                      context,
                      'You already added ${_stance == 'support' ? 'support' : 'challenge'} context. Edit it instead of adding the other side.',
                    );
                  },
                ),
                const SizedBox(height: AppSpacing.lg),
                TextField(
                  controller: _controller,
                  maxLines: 4,
                  maxLength: 500,
                  autofocus: true,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    hintText: _stance == 'support'
                        ? 'What makes this echo credible?'
                        : 'What context makes this echo unsupported?',
                    alignLabelWithHint: true,
                  ),
                  style: AppTypography.textTheme.bodyMedium,
                ),
                Wrap(
                  spacing: AppSpacing.xs,
                  runSpacing: AppSpacing.xs,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    IconButton(
                      tooltip: 'Add image',
                      onPressed:
                          _submitting || (_hasExisting && _editCount >= 1)
                              ? null
                              : () => _pickMedia(false),
                      icon: const Icon(Icons.image_outlined),
                    ),
                    IconButton(
                      tooltip: 'Add video',
                      onPressed:
                          _submitting || (_hasExisting && _editCount >= 1)
                              ? null
                              : () => _pickMedia(true),
                      icon: const Icon(Icons.videocam_outlined),
                    ),
                    Text(
                      _media.isEmpty && _existingMediaUrls.isNotEmpty
                          ? '${_existingMediaUrls.length}/2 existing attachments'
                          : '${_media.length}/2 attachments · one media context per day',
                      style: AppTypography.textTheme.labelSmall,
                    ),
                  ],
                ),
                AnimatedSize(
                  duration: const Duration(milliseconds: 180),
                  curve: Curves.easeOutCubic,
                  child: Column(
                    children: List.generate(_media.length, (index) {
                      final item = _media[index];
                      final name = MediaFileSafety.displayName(item.path);
                      final isVideo = item.kind == MediaFileKind.video;
                      return ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(
                          isVideo ? Icons.movie_outlined : Icons.image_outlined,
                          color: AppColors.textSecondary,
                        ),
                        title: Text(
                          name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTypography.textTheme.bodySmall,
                        ),
                        trailing: IconButton(
                          tooltip: 'Remove',
                          onPressed: _submitting
                              ? null
                              : () => setState(() => _media.removeAt(index)),
                          icon: const Icon(Icons.close_rounded, size: 18),
                        ),
                      );
                    }),
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _submitting ||
                            _controller.text.trim().length < 10 ||
                            _loadingExisting ||
                            (_hasExisting && _editCount >= 1)
                        ? null
                        : _submit,
                    child: _submitting
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: AppColors.white,
                            ),
                          )
                        : Text(
                            _hasExisting ? 'Update context' : 'Send context'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _friendlyError(Object e) {
    final message = e.toString().toLowerCase();
    if (message.contains('media to one context response per day')) {
      return 'You can add media to one support context per day.';
    }
    if (message.contains('own echo')) {
      return 'You cannot support or challenge your own echo.';
    }
    if (message.contains('edit limit') || message.contains('edit_limit')) {
      return 'You already edited this context once.';
    }
    if (message.contains('stance_locked')) {
      return 'You already picked a side on this echo. Edit that context instead.';
    }
    if (message.contains('public context') ||
        message.contains('public_context_closed')) {
      return 'Public context is closed for this echo.';
    }
    if (message.contains('ai_generated_media')) {
      return 'That attachment looks AI-generated, so it cannot be used as context.';
    }
    if (message.contains('ai_generated_text')) {
      return 'That context looks AI-generated. Write it in your own words.';
    }
    if (message.contains('content_policy')) {
      return 'That context could not be posted because of the content policy.';
    }
    if (message.contains('500')) {
      return 'Could not post context. Try again in a moment.';
    }
    return 'Could not post context. Try again.';
  }
}

class _StanceSegmentedControl extends StatelessWidget {
  const _StanceSegmentedControl({
    required this.stances,
    required this.selected,
    required this.locked,
    required this.onChanged,
    required this.onLockedTap,
  });

  final List<
      ({
        String value,
        String label,
        IconData icon,
        Color color,
      })> stances;
  final String selected;
  final bool locked;
  final ValueChanged<String> onChanged;
  final VoidCallback onLockedTap;

  @override
  Widget build(BuildContext context) {
    final selectedIndex = stances.indexWhere((s) => s.value == selected);
    final safeIndex = selectedIndex < 0 ? 0 : selectedIndex;
    final selectedColor = stances[safeIndex].color;

    return Container(
      height: 46,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: AppColors.softSand,
        borderRadius: BorderRadius.circular(AppSpacing.radiusFull),
        border: Border.all(color: AppColors.borderSubtle),
      ),
      child: Stack(
        children: [
          AnimatedAlign(
            duration: const Duration(milliseconds: 240),
            curve: Curves.easeOutCubic,
            alignment:
                safeIndex == 0 ? Alignment.centerLeft : Alignment.centerRight,
            child: FractionallySizedBox(
              widthFactor: stances.isEmpty ? 1 : 1 / stances.length,
              heightFactor: 1,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 240),
                curve: Curves.easeOutCubic,
                decoration: BoxDecoration(
                  color: selectedColor.withValues(alpha: locked ? 0.07 : 0.12),
                  borderRadius: BorderRadius.circular(AppSpacing.radiusFull),
                  border: Border.all(
                    color: selectedColor.withValues(alpha: locked ? 0.28 : 0.5),
                  ),
                ),
              ),
            ),
          ),
          Row(
            children: [
              for (final stance in stances)
                Expanded(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: locked
                        ? onLockedTap
                        : () {
                            if (stance.value != selected) {
                              HapticFeedback.selectionClick();
                              onChanged(stance.value);
                            }
                          },
                    child: Center(
                      child: AnimatedDefaultTextStyle(
                        duration: const Duration(milliseconds: 180),
                        curve: Curves.easeOutCubic,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: stance.value == selected
                              ? stance.color
                              : AppColors.textSecondary,
                          fontFamily: AppTypography.fontFamily,
                        ),
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                stance.icon,
                                size: 15,
                                color: stance.value == selected
                                    ? stance.color
                                    : AppColors.textTertiary,
                              ),
                              const SizedBox(width: 6),
                              Text(stance.label, maxLines: 1),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ContextMedia {
  const _ContextMedia({required this.path, required this.kind});
  final String path;
  final MediaFileKind kind;
}
