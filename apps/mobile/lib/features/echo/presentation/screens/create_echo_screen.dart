// create echo screen
// full form: title, content, category, verification toggle
// uses CreateEchoService via provider — no riverpod

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../../../app/theme/colors.dart';
import '../../../../app/theme/spacing.dart';
import '../../../../app/theme/typography.dart';
import '../../domain/entities/echo_entity.dart';
import '../services/create_echo_service.dart';
import '../../../../core/services/ad_service.dart';
import '../../../../features/subscription/presentation/services/subscription_service.dart';
import 'package:image_picker/image_picker.dart';
import '../../../../core/utils/logger.dart';
import 'package:flutter_mentions/flutter_mentions.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../core/utils/snack.dart';
import '../../../../core/services/tflite_spam_checker.dart';
import '../../../../core/utils/media_file_safety.dart';
import '../../../../core/utils/sanitizer.dart';
import '../widgets/link_preview_card.dart';
import '../../../../shared/widgets/rich_text_display.dart';

enum _DraftAction { save, discard }

class CreateEchoScreen extends StatefulWidget {
  const CreateEchoScreen({super.key});

  @override
  State<CreateEchoScreen> createState() => _CreateEchoScreenState();
}

class _CreateEchoScreenState extends State<CreateEchoScreen>
    with SingleTickerProviderStateMixin {
  final _titleController = TextEditingController();
  final _contentKey = GlobalKey<FlutterMentionsState>();
  final _formKey = GlobalKey<FormState>();
  String? _detectedUrl;
  bool _showLinkPreview = false;
  List<Map<String, dynamic>> _mentionableUsers = [];

  late final AnimationController _entranceController;
  late final Animation<double> _slideY;
  late final Animation<double> _fade;
  late final Animation<double> _rotX;

  @override
  void initState() {
    super.initState();
    _entranceController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 520),
    );
    _slideY = Tween<double>(begin: 40, end: 0).animate(
      CurvedAnimation(parent: _entranceController, curve: Curves.easeOutCubic),
    );
    _fade = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(
        parent: _entranceController,
        curve: const Interval(0, 0.55, curve: Curves.easeOut),
      ),
    );
    _rotX = Tween<double>(begin: 0.06, end: 0).animate(
      CurvedAnimation(parent: _entranceController, curve: Curves.easeOutCubic),
    );
    _entranceController.forward();

    // restore draft into text controllers
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final service = context.read<CreateEchoService>();
      _titleController.text = service.title;
      _loadMentionableUsers();
      // Sync Pro status so character limits are correct.
      final isPro = context.read<SubscriptionService>().isPro;
      service.setProStatus(isPro);
    });
  }

  @override
  void dispose() {
    _entranceController.dispose();
    _titleController.dispose();
    super.dispose();
  }

  Future<void> _loadMentionableUsers() async {
    try {
      final client = Supabase.instance.client;
      final rows = await client
          .from('users_public')
          .select('id, username, avatar_url, trust_tier')
          .eq('is_suspended', false)
          .limit(60);
      if (!mounted) return;
      setState(() {
        _mentionableUsers = (rows as List).map((r) {
          final m = r as Map<String, dynamic>;
          return {
            'id': m['id'] as String,
            'display': m['username'] as String,
            'avatar_url': m['avatar_url'] as String? ?? '',
            'trust_tier': m['trust_tier'] as String? ?? 'unverified',
          };
        }).toList();
      });
    } catch (e) {
      AppLogger.error('create echo: load mentionable users failed $e');
    }
  }

  Future<void> _pickMedia(bool isVideo) async {
    final service = context.read<CreateEchoService>();

    if (service.localMediaPaths.length >= 2) {
      showInfoSnack(context, 'Maximum 2 attachments allowed');
      return;
    }

    final picker = ImagePicker();
    XFile? file;

    if (isVideo) {
      file = await picker.pickVideo(
        source: ImageSource.gallery,
      );
    } else {
      file = await picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 72,
        maxWidth: 1280,
        maxHeight: 1280,
      );
    }

    if (file == null) return;
    if (!mounted) return;

    final validation = await MediaFileSafety.validateLocalFile(
      file.path,
      expectedKind: isVideo ? MediaFileKind.video : MediaFileKind.image,
    );

    if (!mounted) return;
    if (!validation.isValid) {
      showInfoSnack(context, validation.error ?? 'File could not be attached');
      return;
    }

    final selectedPath = File(file.path).absolute.path;
    final alreadyAttached = service.localMediaPaths.any(
      (path) => File(path).absolute.path == selectedPath,
    );
    if (alreadyAttached) {
      showInfoSnack(context, 'That attachment is already selected');
      return;
    }

    // Store local path for preview + upload later.
    service.addLocalMedia(file.path);
    HapticFeedback.selectionClick();
  }

  Future<void> _submit() async {
    final service = context.read<CreateEchoService>();
    final contentController = _contentKey.currentState?.controller;
    final cleanTitle = Sanitizer.text(_titleController.text);
    final cleanContent = Sanitizer.text(contentController?.text ?? '');

    if (_titleController.text != cleanTitle) {
      _titleController.value = TextEditingValue(
        text: cleanTitle,
        selection: TextSelection.collapsed(offset: cleanTitle.length),
      );
    }
    if (contentController != null && contentController.text != cleanContent) {
      final currentOffset = contentController.selection.baseOffset;
      final offset = currentOffset < 0
          ? cleanContent.length
          : currentOffset.clamp(0, cleanContent.length).toInt();
      contentController.value = TextEditingValue(
        text: cleanContent,
        selection: TextSelection.collapsed(offset: offset),
      );
    }

    service
      ..setTitle(cleanTitle)
      ..setContent(cleanContent);

    if (!(_formKey.currentState?.validate() ?? false)) return;

    // Client-side pre-check — fast, no network.
    if (TfliteSpamChecker.shouldWarn(service.title, cleanContent)) {
      final proceed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Text(
            'Content warning',
            style: GoogleFonts.josefinSans(fontWeight: FontWeight.w700),
          ),
          content: Text(
            'Your echo looks like it might be flagged by our community filters. '
            'Review your content and make sure it follows our guidelines before posting.',
            style: GoogleFonts.josefinSans(fontSize: 13, height: 1.5),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text('Edit', style: GoogleFonts.josefinSans()),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(
                'Post anyway',
                style: GoogleFonts.josefinSans(color: AppColors.sunsetCoral),
              ),
            ),
          ],
        ),
      );
      if (proceed != true) return;
    }

    await service.submit();
  }

  Future<_DraftAction?> _showDiscardSheet(BuildContext context) {
    return showModalBottomSheet<_DraftAction>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.borderMedium,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 20),
              Text(
                'Save this draft?',
                style: GoogleFonts.josefinSans(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  color: AppColors.charcoal,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Your echo is not published. You can save it as a draft or discard it.',
                style: GoogleFonts.josefinSans(
                  fontSize: 13,
                  color: AppColors.textSecondary,
                  height: 1.5,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(ctx, _DraftAction.save),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.charcoal,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    elevation: 0,
                  ),
                  child: Text(
                    'Save draft',
                    style: GoogleFonts.josefinSans(fontWeight: FontWeight.w600),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: TextButton(
                  onPressed: () => Navigator.pop(ctx, _DraftAction.discard),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  child: Text(
                    'Discard',
                    style: GoogleFonts.josefinSans(
                      fontWeight: FontWeight.w600,
                      color: AppColors.sunsetCoral,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 4),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final service = context.watch<CreateEchoService>();
    final size = MediaQuery.sizeOf(context);
    final isTablet = size.width > 700;
    final isPro = context.watch<SubscriptionService>().isPro;
    if (service.isPro != isPro) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          context.read<CreateEchoService>().setProStatus(isPro);
        }
      });
    }

    // navigate away on success
    if (service.success) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          context.read<CreateEchoService>().resetSuccess();

          // show rewarded interstitial every 3rd echo for non-pro users
          final isPro = context.read<SubscriptionService>().isPro;
          final count =
              context.read<CreateEchoService>().echoesCreatedThisSession;

          if (!isPro && count % 3 == 0) {
            context.read<AdService>().showRewardedInterstitial(
              onRewarded: () {
                showSuccessSnack(context,
                    '🎉 Thanks for supporting Echoproof — 1 hour ad-free!');
              },
            );
          }

          context.pop();
          HapticFeedback.mediumImpact();
          showSuccessSnack(
              context, 'Echo created — awaiting community signals');
        }
      });
    }

    final hasDraft = service.title.isNotEmpty ||
        service.content.isNotEmpty ||
        service.localMediaPaths.isNotEmpty;

    return PopScope(
        canPop: !hasDraft,
        onPopInvokedWithResult: (didPop, _) async {
          if (didPop) return;
          final action = await _showDiscardSheet(context);
          if (!context.mounted) return;
          if (action == _DraftAction.discard) {
            service.reset();
            context.pop();
          }
          // If save — just close (service retains state since it's a provider).
          if (action == _DraftAction.save || action == _DraftAction.discard) {
            // save = just close without clearing
            if (action == _DraftAction.save) context.pop();
          }
        },
        child: Scaffold(
          backgroundColor: AppColors.white,
          appBar: AppBar(
            title:
                Text('Create Echo', style: AppTypography.textTheme.titleLarge),
            leading: IconButton(
              icon: const Icon(Icons.close, size: 22),
              onPressed: () async {
                if (!hasDraft) {
                  context.pop();
                  return;
                }
                final action = await _showDiscardSheet(context);
                if (!context.mounted) return;
                if (action == _DraftAction.discard) {
                  service.reset();
                  context.pop();
                } else if (action == _DraftAction.save) {
                  context.pop(); // retain draft in service
                }
              },
            ),
            actions: [
              if (isPro)
                IconButton(
                  icon: const Icon(Icons.tips_and_updates_outlined, size: 20),
                  onPressed: _showProGuide,
                  color: AppColors.fernGreen,
                  tooltip: 'Pro writing guide',
                ),
              Padding(
                padding: const EdgeInsets.only(right: AppSpacing.md),
                child: _SubmitButton(
                  canSubmit: service.canSubmit,
                  isLoading: service.isSubmitting,
                  onTap: _submit,
                ),
              ),
            ],
          ),
          body: AnimatedBuilder(
            animation: _entranceController,
            builder: (context, child) {
              return Opacity(
                opacity: _fade.value,
                child: Transform(
                  transform: Matrix4.identity()
                    ..setEntry(3, 2, 0.001)
                    ..rotateX(_rotX.value)
                    ..translateByDouble(0.0, _slideY.value, 0.0, 1.0),
                  alignment: Alignment.topCenter,
                  child: child,
                ),
              );
            },
            child: Center(
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: isTablet ? 560 : double.infinity,
                ),
                child: Form(
                  key: _formKey,
                  child: ListView(
                    keyboardDismissBehavior:
                        ScrollViewKeyboardDismissBehavior.onDrag,
                    padding: EdgeInsets.fromLTRB(
                      AppSpacing.xl,
                      AppSpacing.xl,
                      AppSpacing.xl,
                      MediaQuery.paddingOf(context).bottom + 100,
                    ),
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('Title',
                              style: AppTypography.textTheme.titleSmall),
                          _CharCounter(
                            current: service.title.length,
                            max: service.titleMaxLength,
                          ),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      TextFormField(
                        controller: _titleController,
                        maxLength: service.titleMaxLength,
                        buildCounter: (_,
                                {required currentLength,
                                required isFocused,
                                maxLength}) =>
                            null,
                        onChanged: context.read<CreateEchoService>().setTitle,
                        decoration: const InputDecoration(
                          hintText: 'Short, clear claim or opinion',
                        ),
                        style: AppTypography.textTheme.bodyLarge,
                        validator: (v) => (v == null || v.trim().isEmpty)
                            ? 'title cannot be empty'
                            : null,
                      ),
                      const SizedBox(height: AppSpacing.xl),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('Content',
                              style: AppTypography.textTheme.titleSmall),
                          _CharCounter(
                            current: service.content.length,
                            max: service.contentMaxLength,
                          ),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      _ContentMentionField(
                        mentionKey: _contentKey,
                        mentionableUsers: _mentionableUsers,
                        onChanged: context.read<CreateEchoService>().setContent,
                        maxLength: service.contentMaxLength,
                        isPro: isPro,
                        onUrlDetected: (url) {
                          setState(() {
                            _detectedUrl = url;
                            _showLinkPreview = url != null;
                          });
                        },
                      ),
                      if (_showLinkPreview && _detectedUrl != null)
                        LinkPreviewCard(
                          url: _detectedUrl!,
                          onDismiss: () => setState(() {
                            _showLinkPreview = false;
                            _detectedUrl = null;
                          }),
                          onAttach: () {},
                        ),
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 220),
                        switchInCurve: Curves.easeOutCubic,
                        switchOutCurve: Curves.easeInCubic,
                        child: isPro &&
                                (service.title.trim().isNotEmpty ||
                                    service.content.trim().isNotEmpty)
                            ? Padding(
                                key: const ValueKey('pro-preview'),
                                padding:
                                    const EdgeInsets.only(top: AppSpacing.lg),
                                child: _ProEchoPreviewCard(
                                  title: service.title,
                                  content: service.content,
                                  category: service.category,
                                ),
                              )
                            : const SizedBox.shrink(
                                key: ValueKey('no-pro-preview'),
                              ),
                      ),
                      const SizedBox(height: AppSpacing.xl),
                      Text('Category',
                          style: AppTypography.textTheme.titleSmall),
                      const SizedBox(height: AppSpacing.sm),
                      _CategoryPicker(
                        selected: service.category,
                        onSelect: context.read<CreateEchoService>().setCategory,
                      ),
                      const SizedBox(height: AppSpacing.xl),
                      _VerificationToggle(
                        value: service.requiresVerification,
                        onToggle: context
                            .read<CreateEchoService>()
                            .toggleVerification,
                      ),
                      const SizedBox(height: AppSpacing.xl),
                      if (service.error != null)
                        Container(
                          padding: const EdgeInsets.all(AppSpacing.md),
                          decoration: BoxDecoration(
                            color: AppColors.sunsetCoralLight,
                            borderRadius:
                                BorderRadius.circular(AppSpacing.radiusMd),
                          ),
                          child: Text(
                            service.error!,
                            style: TextStyle(
                              fontSize: 13,
                              color: AppColors.sunsetCoralDark,
                              fontFamily: AppTypography.fontFamily,
                            ),
                          ),
                        ),
                      _MediaPickerRow(
                        localPaths: service.localMediaPaths,
                        onPickImage: () => _pickMedia(false),
                        onPickVideo: () => _pickMedia(true),
                        onRemove: (i) => service.removeLocalMedia(i),
                      ),
                      const SizedBox(height: 100),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ));
  }

  void _showProGuide() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.7,
        maxChildSize: 0.95,
        builder: (_, ctrl) => ListView(
          controller: ctrl,
          padding: const EdgeInsets.all(AppSpacing.xl),
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
            Row(
              children: [
                const Icon(Icons.star_rounded,
                    color: AppColors.fernGreen, size: 20),
                const SizedBox(width: 8),
                Text(
                  'Pro Writing Guide',
                  style: GoogleFonts.josefinSans(
                      fontSize: 18, fontWeight: FontWeight.w700),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.xl),
            _GuideSection(
              icon: Icons.format_bold_rounded,
              title: 'Rich Text Formatting',
              tips: [
                '**bold text** uses exactly two asterisks on each side',
                '***bold italic*** uses three asterisks on each side',
                '_italic text_ wraps words in underscores',
                '~~strikethrough~~ wraps words in double tildes',
                '[large]large text[/large] and [small]small text[/small] change size',
                'The editor shows markers while Pro preview shows the final card',
                'Use the B / I / S / A+ / A- toolbar above the text field',
              ],
            ),
            _GuideSection(
              icon: Icons.link_rounded,
              title: 'Link Previews',
              tips: [
                'Paste any URL and a preview card appears automatically',
                'Tap "Attach preview" to include the card in your echo',
                'Click the external link icon to open it first',
                'Links are validated — only http/https accepted',
              ],
            ),
            _GuideSection(
              icon: Icons.alternate_email_rounded,
              title: 'Mentions & Signals',
              tips: [
                'Type @username to mention another user',
                'Type ~topic to add a signal tag to your echo',
                'Signals help your echo appear in Discover',
                'Max 5 signals per echo for best reach',
              ],
            ),
            _GuideSection(
              icon: Icons.photo_library_outlined,
              title: 'Media Attachments',
              tips: [
                'Attach up to 2 images or videos as evidence',
                'Images are compressed to 1280px max',
                'Videos must be under 50MB',
                'File type, size, and file header are validated before upload',
              ],
            ),
            _GuideSection(
              icon: Icons.bar_chart_rounded,
              title: 'Getting Verified',
              tips: [
                'Trust score = support_weight − challenge_weight',
                'Score ≥ 50 + confidence ≥ 70% = Verified status',
                'Verified identity users have 4x voting weight',
                'Pro + Verified = highest feed ranking boost (1.25x)',
              ],
            ),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }
}

class _GuideSection extends StatelessWidget {
  const _GuideSection({
    required this.icon,
    required this.title,
    required this.tips,
  });
  final IconData icon;
  final String title;
  final List<String> tips;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.xl),
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: AppColors.softSand,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.borderSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: AppColors.fernGreen),
              const SizedBox(width: 8),
              Text(
                title,
                style: GoogleFonts.josefinSans(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: AppColors.charcoal),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          ...tips.map((tip) => Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 4,
                      height: 4,
                      margin: const EdgeInsets.only(top: 6, right: 8),
                      decoration: const BoxDecoration(
                        color: AppColors.fernGreen,
                        shape: BoxShape.circle,
                      ),
                    ),
                    Expanded(
                      child: Text(
                        tip,
                        style: GoogleFonts.josefinSans(
                            fontSize: 13,
                            color: AppColors.textSecondary,
                            height: 1.5),
                      ),
                    ),
                  ],
                ),
              )),
        ],
      ),
    );
  }
}

class _ContentMentionField extends StatelessWidget {
  const _ContentMentionField({
    required this.mentionKey,
    required this.mentionableUsers,
    required this.onChanged,
    required this.maxLength,
    required this.isPro,
    required this.onUrlDetected,
  });

  final GlobalKey<FlutterMentionsState> mentionKey;
  final List<Map<String, dynamic>> mentionableUsers;
  final void Function(String) onChanged;
  final int maxLength;
  final bool isPro;
  final void Function(String?) onUrlDetected;

  void _extractUrl(String text) {
    final urlPattern = RegExp(
      r'https?://[^\s<>"{}|\\^`\[\]]+',
      caseSensitive: false,
    );

    final match = urlPattern.firstMatch(text);
    onUrlDetected(match?.group(0));
  }

  @override
  Widget build(BuildContext context) {
    return FormField<String>(
      validator: (_) {
        final v = mentionKey.currentState?.controller?.text ?? '';
        return v.trim().isEmpty ? 'content cannot be empty' : null;
      },
      builder: (field) {
        final maxLen = context.read<CreateEchoService>().contentMaxLength;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              decoration: BoxDecoration(
                color: AppColors.softSand,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: field.hasError
                      ? AppColors.sunsetCoral
                      : AppColors.borderSubtle,
                ),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (isPro)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: _ProRichToolbar(mentionKey: mentionKey),
                    ),
                  FlutterMentions(
                    key: mentionKey,
                    maxLines: isPro ? 20 : 8,
                    minLines: 4,
                    suggestionPosition: SuggestionPosition.Top,
                    onChanged: (v) {
                      if (v.length <= maxLen) {
                        onChanged(v);
                        field.didChange(v);
                        _extractUrl(v);
                      }
                    },
                    style: const TextStyle(
                      fontSize: 15,
                      color: Color(0xFF1A1A1A),
                      height: 1.5,
                    ),
                    decoration: InputDecoration(
                      hintText:
                          'Explain your opinion or claim.\n\nUse @username to mention, ~signal to tag.',
                      hintStyle: GoogleFonts.josefinSans(
                        fontSize: 14,
                        color: AppColors.textTertiary,
                        height: 1.5,
                      ),
                      border: InputBorder.none,
                      isDense: true,
                    ),
                    suggestionListDecoration: BoxDecoration(
                      color: AppColors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppColors.borderSubtle),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.08),
                          blurRadius: 12,
                          offset: const Offset(0, -4),
                        ),
                      ],
                    ),
                    mentions: [
                      Mention(
                        trigger: '@',
                        style: GoogleFonts.josefinSans(
                          color: AppColors.fernGreen,
                          fontWeight: FontWeight.w600,
                        ),
                        data: mentionableUsers,
                        suggestionBuilder: (data) {
                          final avatarUrl = data['avatar_url'] as String?;
                          return Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 8,
                            ),
                            child: Row(
                              children: [
                                CircleAvatar(
                                  radius: 16,
                                  backgroundColor: AppColors.softSand,
                                  backgroundImage: (avatarUrl != null &&
                                          avatarUrl.isNotEmpty)
                                      ? NetworkImage(avatarUrl)
                                      : null,
                                  child:
                                      (avatarUrl == null || avatarUrl.isEmpty)
                                          ? const Icon(Icons.person_outline,
                                              size: 16,
                                              color: AppColors.textTertiary)
                                          : null,
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  '@${data['display']}',
                                  style: GoogleFonts.josefinSans(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: AppColors.charcoal,
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                      Mention(
                        trigger: '~',
                        style: GoogleFonts.josefinSans(
                          color: AppColors.fernGreen,
                          fontWeight: FontWeight.w500,
                        ),
                        data: const [],
                        matchAll: true,
                        disableMarkup: true,
                      ),
                    ],
                  ),
                ],
              ),
            ),
            if (field.hasError)
              Padding(
                padding: const EdgeInsets.only(top: 4, left: 4),
                child: Text(
                  field.errorText ?? '',
                  style: TextStyle(
                    fontSize: 12,
                    color: AppColors.sunsetCoral,
                    fontFamily: AppTypography.fontFamily,
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _ProEchoPreviewCard extends StatelessWidget {
  const _ProEchoPreviewCard({
    required this.title,
    required this.content,
    required this.category,
  });

  final String title;
  final String content;
  final EchoCategory? category;

  @override
  Widget build(BuildContext context) {
    final trimmedTitle = title.trim();
    final trimmedContent = content.trim();

    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.98, end: 1),
      duration: const Duration(milliseconds: 240),
      curve: Curves.easeOutBack,
      builder: (context, value, child) =>
          Transform.scale(scale: value, child: child),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: AppColors.white,
          borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
          border: Border.all(color: AppColors.borderSubtle),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.035),
              blurRadius: 14,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 28,
                  height: 28,
                  decoration: const BoxDecoration(
                    color: AppColors.fernGreenLight,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.auto_awesome_rounded,
                    size: 15,
                    color: AppColors.fernGreen,
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    'Pro preview',
                    style: AppTypography.textTheme.titleSmall,
                  ),
                ),
                if (category != null)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.softSand,
                      borderRadius:
                          BorderRadius.circular(AppSpacing.radiusFull),
                    ),
                    child: Text(
                      category!.displayName,
                      style: AppTypography.textTheme.bodySmall,
                    ),
                  ),
              ],
            ),
            if (trimmedTitle.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.md),
              RichTextDisplay(
                text: trimmedTitle,
                style: AppTypography.textTheme.titleMedium,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
            if (trimmedContent.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.sm),
              RichTextDisplay(
                text: trimmedContent,
                style: AppTypography.textTheme.bodyMedium,
                maxLines: 5,
                overflow: TextOverflow.ellipsis,
              ),
            ],
            const SizedBox(height: AppSpacing.sm),
            Row(
              children: [
                _PreviewStat(
                    icon: Icons.chat_bubble_outline_rounded, text: 'Reply'),
                _PreviewStat(icon: Icons.arrow_upward_rounded, text: 'Support'),
                _PreviewStat(
                    icon: Icons.arrow_downward_rounded, text: 'Challenge'),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _PreviewStat extends StatelessWidget {
  const _PreviewStat({required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 14, color: AppColors.textSecondary),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTypography.textTheme.bodySmall?.copyWith(
                color: AppColors.textSecondary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ProRichToolbar extends StatelessWidget {
  const _ProRichToolbar({required this.mentionKey});
  final GlobalKey<FlutterMentionsState> mentionKey;

  void _wrap(String open, String close) {
    final ctrl = mentionKey.currentState?.controller;
    if (ctrl == null) return;
    final sel = ctrl.selection;
    if (!sel.isValid) return;
    final text = ctrl.text;
    final selected = sel.textInside(text);
    final fallback = switch (open) {
      '**' => 'bold text',
      '_' => 'italic text',
      '~~' => 'strikethrough text',
      '[large]' => 'large text',
      '[small]' => 'small text',
      _ => 'text',
    };

    if (selected.isEmpty) {
      final replacement = '$open$fallback$close';
      final newText = text.replaceRange(sel.start, sel.end, replacement);
      ctrl.value = TextEditingValue(
        text: newText,
        selection: TextSelection(
          baseOffset: sel.start + open.length,
          extentOffset: sel.start + open.length + fallback.length,
        ),
      );
      return;
    }

    final leading = RegExp(r'^\s+').firstMatch(selected)?.group(0) ?? '';
    final trailing = RegExp(r'\s+$').firstMatch(selected)?.group(0) ?? '';
    final coreStart = sel.start + leading.length;
    final coreEnd = sel.end - trailing.length;
    final core = coreEnd > coreStart ? text.substring(coreStart, coreEnd) : '';

    if (core.isEmpty) {
      final replacement = '$leading$open$fallback$close$trailing';
      final newText = text.replaceRange(sel.start, sel.end, replacement);
      ctrl.value = TextEditingValue(
        text: newText,
        selection: TextSelection(
          baseOffset: sel.start + leading.length + open.length,
          extentOffset:
              sel.start + leading.length + open.length + fallback.length,
        ),
      );
      return;
    }

    if (core.startsWith(open) &&
        core.endsWith(close) &&
        core.length >= open.length + close.length) {
      final unwrapped = core.substring(
        open.length,
        core.length - close.length,
      );
      final replacement = '$leading$unwrapped$trailing';
      final newText = text.replaceRange(sel.start, sel.end, replacement);
      ctrl.value = TextEditingValue(
        text: newText,
        selection: TextSelection(
          baseOffset: sel.start + leading.length,
          extentOffset: sel.start + leading.length + unwrapped.length,
        ),
      );
      return;
    }

    final hasOuterOpen = coreStart >= open.length &&
        text.substring(coreStart - open.length, coreStart) == open;
    final hasOuterClose = coreEnd + close.length <= text.length &&
        text.substring(coreEnd, coreEnd + close.length) == close;
    if (hasOuterOpen && hasOuterClose) {
      final newText = text.replaceRange(coreEnd, coreEnd + close.length, '');
      final unwrappedText =
          newText.replaceRange(coreStart - open.length, coreStart, '');
      ctrl.value = TextEditingValue(
        text: unwrappedText,
        selection: TextSelection(
          baseOffset: coreStart - open.length,
          extentOffset: coreEnd - open.length,
        ),
      );
      return;
    }

    final replacement = '$leading$open$core$close$trailing';
    final newText = text.replaceRange(sel.start, sel.end, replacement);

    ctrl.value = TextEditingValue(
      text: newText,
      selection:
          TextSelection.collapsed(offset: sel.start + replacement.length),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _TBtn(label: 'B', bold: true, onTap: () => _wrap('**', '**')),
        _TBtn(label: 'I', italic: true, onTap: () => _wrap('_', '_')),
        _TBtn(label: 'S', strikethrough: true, onTap: () => _wrap('~~', '~~')),
        _TBtn(
            label: 'A+', bold: true, onTap: () => _wrap('[large]', '[/large]')),
        _TBtn(label: 'A-', onTap: () => _wrap('[small]', '[/small]')),
        const SizedBox(width: 8),
        Text(
          'Pro rich text',
          style: GoogleFonts.josefinSans(
            fontSize: 10,
            color: AppColors.fernGreen,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

class _TBtn extends StatelessWidget {
  const _TBtn(
      {required this.label,
      required this.onTap,
      this.bold = false,
      this.italic = false,
      this.strikethrough = false});
  final String label;
  final VoidCallback onTap;
  final bool bold, italic, strikethrough;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 28,
        height: 24,
        margin: const EdgeInsets.only(right: 4),
        decoration: BoxDecoration(
          color: AppColors.softSand,
          borderRadius: BorderRadius.circular(5),
          border: Border.all(color: AppColors.borderSubtle),
        ),
        child: Center(
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: bold ? FontWeight.w700 : FontWeight.w400,
              fontStyle: italic ? FontStyle.italic : FontStyle.normal,
              decoration: strikethrough ? TextDecoration.lineThrough : null,
            ),
          ),
        ),
      ),
    );
  }
}

class _SubmitButton extends StatelessWidget {
  const _SubmitButton({
    required this.canSubmit,
    required this.isLoading,
    required this.onTap,
  });
  final bool canSubmit;
  final bool isLoading;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return AnimatedOpacity(
      opacity: canSubmit ? 1.0 : 0.4,
      duration: const Duration(milliseconds: 200),
      child: GestureDetector(
        onTap: canSubmit ? onTap : null,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.xs,
          ),
          decoration: BoxDecoration(
            color: canSubmit ? AppColors.charcoal : AppColors.borderMedium,
            borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
          ),
          child: isLoading
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: AppColors.white,
                  ),
                )
              : Text(
                  'Publish',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.white,
                    fontFamily: AppTypography.fontFamily,
                  ),
                ),
        ),
      ),
    );
  }
}

class _CharCounter extends StatelessWidget {
  const _CharCounter({required this.current, required this.max});
  final int current;
  final int max;

  @override
  Widget build(BuildContext context) {
    final isNearLimit = current > max * 0.85;
    return Text(
      '$current / $max',
      style: TextStyle(
        fontSize: 11,
        color: isNearLimit ? AppColors.sunsetCoral : AppColors.textTertiary,
        fontWeight: isNearLimit ? FontWeight.w600 : FontWeight.w400,
        fontFamily: AppTypography.fontFamily,
      ),
    );
  }
}

class _CategoryPicker extends StatelessWidget {
  const _CategoryPicker({required this.selected, required this.onSelect});
  final EchoCategory? selected;
  final void Function(EchoCategory) onSelect;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.sm,
      children: EchoCategory.values.map((cat) {
        final isSelected = cat == selected;
        return GestureDetector(
          onTap: () {
            HapticFeedback.selectionClick();
            onSelect(cat);
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: AppSpacing.sm,
            ),
            decoration: BoxDecoration(
              color: isSelected ? AppColors.charcoal : AppColors.softSand,
              borderRadius: BorderRadius.circular(AppSpacing.radiusFull),
              border: Border.all(
                color: isSelected ? AppColors.charcoal : AppColors.borderSubtle,
              ),
            ),
            child: Text(
              cat.displayName,
              style: TextStyle(
                fontSize: 13,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                color: isSelected ? AppColors.white : AppColors.textPrimary,
                fontFamily: AppTypography.fontFamily,
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}

class _MediaPickerRow extends StatelessWidget {
  const _MediaPickerRow({
    required this.localPaths,
    required this.onPickImage,
    required this.onPickVideo,
    required this.onRemove,
  });

  // final List<String> mediaUrls;
  final VoidCallback onPickImage;
  final VoidCallback onPickVideo;
  final List<String> localPaths;
  final void Function(int) onRemove;

  @override
  Widget build(BuildContext context) {
    final isMax = localPaths.length >= 2;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 12),

        // 🎯 PICKER ROW
        Row(
          children: [
            IconButton(
              icon: Icon(
                Icons.attach_file_rounded,
                size: 20,
                color: isMax ? AppColors.textTertiary : AppColors.charcoal,
              ),
              onPressed: isMax ? null : onPickImage,
            ),
            IconButton(
              icon: Icon(
                Icons.videocam_rounded,
                size: 20,
                color: isMax ? AppColors.textTertiary : AppColors.charcoal,
              ),
              onPressed: isMax ? null : onPickVideo,
            ),
          ],
        ),

        // counter
        if (localPaths.isNotEmpty) ...[
          Row(
            children: [
              Text(
                '${localPaths.length}/2 attachment${localPaths.length > 1 ? 's' : ''}',
                style: GoogleFonts.josefinSans(
                  fontSize: 11,
                  color:
                      isMax ? AppColors.sunsetCoral : AppColors.textSecondary,
                ),
              ),
              if (isMax) ...[
                const SizedBox(width: 4),
                const Icon(Icons.block_rounded,
                    size: 11, color: AppColors.sunsetCoral),
              ],
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
        ],

        // cards
        if (localPaths.isNotEmpty) ...[
          ...List.generate(localPaths.length, (i) {
            final path = localPaths[i];
            final isVideo = MediaFileSafety.isVideoPath(path);
            final name = MediaFileSafety.displayName(path);
            final ext = MediaFileSafety.extensionOf(name).toUpperCase();

            return TweenAnimationBuilder<double>(
              key: ValueKey(path),
              tween: Tween(begin: 0, end: 1),
              duration: Duration(milliseconds: 220 + i * 40),
              curve: Curves.easeOutCubic,
              builder: (context, value, child) => Opacity(
                opacity: value,
                child: Transform.translate(
                  offset: Offset(0, (1 - value) * 12),
                  child: child,
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Container(
                  decoration: BoxDecoration(
                    color: AppColors.softSand,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.borderSubtle),
                  ),
                  child: Row(
                    children: [
                      // 🎬 Thumbnail / Icon
                      ClipRRect(
                        borderRadius: const BorderRadius.only(
                          topLeft: Radius.circular(11),
                          bottomLeft: Radius.circular(11),
                        ),
                        child: isVideo
                            ? Container(
                                width: 64,
                                height: 64,
                                color: AppColors.charcoal,
                                child: const Icon(
                                  Icons.play_circle_filled_rounded,
                                  color: Colors.white,
                                  size: 28,
                                ),
                              )
                            : Image.file(
                                File(path),
                                width: 64,
                                height: 64,
                                fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) => Container(
                                  width: 64,
                                  height: 64,
                                  color: AppColors.softSand,
                                  child: const Icon(
                                    Icons.broken_image_outlined,
                                    color: AppColors.textTertiary,
                                  ),
                                ),
                              ),
                      ),

                      const SizedBox(width: 12),

                      // 📝 FILE INFO
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              name.length > 30
                                  ? '${name.substring(0, 27)}...'
                                  : name,
                              style: GoogleFonts.josefinSans(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: AppColors.charcoal,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 2),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: isVideo
                                    ? AppColors.charcoal.withValues(alpha: 0.1)
                                    : AppColors.fernGreen
                                        .withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                ext,
                                style: GoogleFonts.josefinSans(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                  color: isVideo
                                      ? AppColors.charcoal
                                      : AppColors.fernGreenDark,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),

                      // ❌ REMOVE
                      GestureDetector(
                        onTap: () => onRemove(i),
                        child: Container(
                          width: 36,
                          height: 64,
                          decoration: BoxDecoration(
                            color:
                                AppColors.sunsetCoral.withValues(alpha: 0.08),
                            borderRadius: const BorderRadius.only(
                              topRight: Radius.circular(11),
                              bottomRight: Radius.circular(11),
                            ),
                          ),
                          child: const Icon(
                            Icons.close_rounded,
                            size: 18,
                            color: AppColors.sunsetCoral,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }),
          const SizedBox(height: AppSpacing.xs),
        ],
      ],
    );
  }
}

class _VerificationToggle extends StatelessWidget {
  const _VerificationToggle({required this.value, required this.onToggle});
  final bool value;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onToggle,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(AppSpacing.lg),
        decoration: BoxDecoration(
          color: value ? AppColors.fernGreenLight : AppColors.softSand,
          borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
          border: Border.all(
            color: value
                ? AppColors.fernGreen.withValues(alpha: 0.25)
                : AppColors.borderSubtle,
          ),
        ),
        child: Row(
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 44,
              height: 26,
              decoration: BoxDecoration(
                color: value ? AppColors.fernGreen : AppColors.borderMedium,
                borderRadius: BorderRadius.circular(13),
              ),
              child: AnimatedAlign(
                duration: const Duration(milliseconds: 200),
                alignment: value ? Alignment.centerRight : Alignment.centerLeft,
                child: Container(
                  margin: const EdgeInsets.all(3),
                  width: 20,
                  height: 20,
                  decoration: const BoxDecoration(
                    color: AppColors.white,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Require verification',
                    style: AppTypography.textTheme.titleSmall,
                  ),
                  Text(
                    'Community members will be asked to support or challenge this echo',
                    style: AppTypography.textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
