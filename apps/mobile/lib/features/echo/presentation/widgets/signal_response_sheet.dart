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

  static const _stances = [
    (value: 'support', label: 'Supporting', color: AppColors.fernGreen),
    (value: 'challenge', label: 'Challenging', color: AppColors.sunsetCoral),
  ];

  @override
  void initState() {
    super.initState();
    _stance = widget.initialStance == 'challenge' ? 'challenge' : 'support';
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final content = _controller.text.trim();
    if (content.length < 10 || _submitting) return;
    if (showOfflineSnackIfNeeded(context)) return;

    setState(() => _submitting = true);
    HapticFeedback.lightImpact();

    try {
      final client = Supabase.instance.client;
      final userId = client.auth.currentUser?.id;
      if (userId == null) throw Exception('not authenticated');

      final uploadedUrls = <String>[];
      final uploadedTypes = <String>[];
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
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: SafeArea(
        child: Padding(
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
                _stance == 'support'
                    ? 'Support with context'
                    : 'Challenge with context',
                style: AppTypography.textTheme.titleMedium,
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                'Explain why. Other users can like your context, and the public evaluation decides the echo.',
                style: AppTypography.textTheme.bodySmall,
              ),
              const SizedBox(height: AppSpacing.lg),
              Row(
                children: _stances.map((s) {
                  final selected = _stance == s.value;
                  return Expanded(
                    child: GestureDetector(
                      onTap: () => setState(() => _stance = s.value),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 180),
                        margin: const EdgeInsets.only(right: AppSpacing.xs),
                        padding: const EdgeInsets.symmetric(
                          vertical: AppSpacing.sm,
                        ),
                        decoration: BoxDecoration(
                          color: selected
                              ? s.color.withValues(alpha: 0.1)
                              : AppColors.softSand,
                          borderRadius:
                              BorderRadius.circular(AppSpacing.radiusMd),
                          border: Border.all(
                            color: selected ? s.color : AppColors.borderSubtle,
                          ),
                        ),
                        child: Center(
                          child: Text(
                            s.label,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight:
                                  selected ? FontWeight.w600 : FontWeight.w400,
                              color:
                                  selected ? s.color : AppColors.textSecondary,
                              fontFamily: AppTypography.fontFamily,
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                }).toList(),
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
              Row(
                children: [
                  IconButton(
                    tooltip: 'Add image',
                    onPressed: _submitting ? null : () => _pickMedia(false),
                    icon: const Icon(Icons.image_outlined),
                  ),
                  IconButton(
                    tooltip: 'Add video',
                    onPressed: _submitting ? null : () => _pickMedia(true),
                    icon: const Icon(Icons.videocam_outlined),
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  Text(
                    '${_media.length}/2 attachments · one media context per day',
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
                  onPressed: _submitting || _controller.text.trim().length < 10
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
                      : const Text('Send context'),
                ),
              ),
            ],
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

class _ContextMedia {
  const _ContextMedia({required this.path, required this.kind});
  final String path;
  final MediaFileKind kind;
}
