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

    // Reject files over 10MB to prevent upload timeouts.
    final fileSize = await File(file.path).length();
    if (fileSize > 10 * 1024 * 1024) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'File is too large. Maximum size is 10MB.',
              style: GoogleFonts.josefinSans(fontSize: 13),
            ),
            backgroundColor: AppColors.sunsetCoral,
            behavior: SnackBarBehavior.floating,
            margin: const EdgeInsets.only(bottom: 88, left: 16, right: 16),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        );
      }
      return;
    }

    final service = context.read<CreateEchoService>();

    if (service.mediaUrls.length >= 2) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Maximum 2 attachments allowed',
            style: GoogleFonts.josefinSans(fontSize: 13),
          ),
          backgroundColor: AppColors.sunsetCoral,
        ),
      );
      return;
    }
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final content = _contentKey.currentState?.controller?.text ?? '';
    context.read<CreateEchoService>().setContent(content);
    await context.read<CreateEchoService>().submit();
  }

  @override
  Widget build(BuildContext context) {
    final service = context.watch<CreateEchoService>();
    final size = MediaQuery.sizeOf(context);
    final isTablet = size.width > 700;

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
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      '🎉 Thanks for supporting Echoproof — 1 hour ad-free!',
                      style: GoogleFonts.josefinSans(),
                    ),
                    backgroundColor: const Color(0xFF1E3A2A),
                    behavior: SnackBarBehavior.floating,
                    margin:
                        const EdgeInsets.only(bottom: 88, left: 16, right: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                );
              },
            );
          }

          context.pop();
          HapticFeedback.mediumImpact();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('Echo created — awaiting community signals'),
              backgroundColor: AppColors.fernGreen,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          );
        }
      });
    }

    return Scaffold(
      backgroundColor: AppColors.white,
      appBar: AppBar(
        title: Text('Create Echo', style: AppTypography.textTheme.titleLarge),
        leading: IconButton(
          icon: const Icon(Icons.close, size: 22),
          onPressed: () => context.pop(),
        ),
        actions: [
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
                padding: const EdgeInsets.all(AppSpacing.xl),
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Title', style: AppTypography.textTheme.titleSmall),
                      _CharCounter(
                        current: service.title.length,
                        max: 120,
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  TextFormField(
                    controller: _titleController,
                    maxLength: 120,
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
                        max: 308,
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  _ContentMentionField(
                    mentionKey: _contentKey,
                    mentionableUsers: _mentionableUsers,
                    onChanged: context.read<CreateEchoService>().setContent,
                    maxLength: 308,
                  ),
                  const SizedBox(height: AppSpacing.xl),
                  Text('Category', style: AppTypography.textTheme.titleSmall),
                  const SizedBox(height: AppSpacing.sm),
                  _CategoryPicker(
                    selected: service.category,
                    onSelect: context.read<CreateEchoService>().setCategory,
                  ),
                  const SizedBox(height: AppSpacing.xl),
                  _VerificationToggle(
                    value: service.requiresVerification,
                    onToggle:
                        context.read<CreateEchoService>().toggleVerification,
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
                    mediaUrls: service.mediaUrls,
                    onPickImage: () => _pickMedia(false),
                    onPickVideo: () => _pickMedia(true),
                    onRemove: service.removeMedia,
                  ),
                  const SizedBox(height: 100),
                ],
              ),
            ),
          ),
        ),
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
  });

  final GlobalKey<FlutterMentionsState> mentionKey;
  final List<Map<String, dynamic>> mentionableUsers;
  final void Function(String) onChanged;
  final int maxLength;

  @override
  Widget build(BuildContext context) {
    return FormField<String>(
      validator: (_) {
        final v = mentionKey.currentState?.controller?.text ?? '';
        return v.trim().isEmpty ? 'content cannot be empty' : null;
      },
      builder: (field) {
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
              child: FlutterMentions(
                key: mentionKey,
                maxLines: 8,
                minLines: 4,
                suggestionPosition: SuggestionPosition.Top,
                onChanged: (v) {
                  onChanged(v);
                  field.didChange(v);
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
                              backgroundImage:
                                  (avatarUrl != null && avatarUrl.isNotEmpty)
                                      ? NetworkImage(avatarUrl)
                                      : null,
                              child: (avatarUrl == null || avatarUrl.isEmpty)
                                  ? const Icon(Icons.person_outline,
                                      size: 16, color: AppColors.textTertiary)
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
    required this.mediaUrls,
    required this.onPickImage,
    required this.onPickVideo,
    required this.onRemove,
  });

  final List<String> mediaUrls;
  final VoidCallback onPickImage;
  final VoidCallback onPickVideo;
  final void Function(int) onRemove;

  bool _isVideo(String url) {
    return url.endsWith('.mp4') || url.endsWith('.mov') || url.endsWith('.avi');
  }

  String _getName(String url) {
    return url.split('/').last;
  }

  @override
  Widget build(BuildContext context) {
    final isMax = mediaUrls.length >= 2;

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

        // 📊 COUNTER
        if (mediaUrls.isNotEmpty) ...[
          Row(
            children: [
              Text(
                '${mediaUrls.length}/2 attachment${mediaUrls.length > 1 ? 's' : ''}',
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

        // 📦 ATTACHMENT CARDS
        if (mediaUrls.isNotEmpty) ...[
          ...List.generate(mediaUrls.length, (i) {
            final url = mediaUrls[i];
            final isVideo = _isVideo(url);
            final name = _getName(url);
            final ext = name.split('.').last.toUpperCase();

            return Padding(
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
                          : Image.network(
                              url,
                              width: 64,
                              height: 64,
                              fit: BoxFit.cover,
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
                                  : AppColors.fernGreen.withValues(alpha: 0.1),
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
                          color: AppColors.sunsetCoral.withValues(alpha: 0.08),
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
