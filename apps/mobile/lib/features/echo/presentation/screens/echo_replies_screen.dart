// echo replies screen
// @params none

import 'dart:async';

import 'package:echoproof/core/utils/snack.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_mentions/flutter_mentions.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../app/theme/colors.dart';
import '../../../../app/theme/spacing.dart';
import '../../../../app/theme/typography.dart';
import '../../../../core/localization/app_copy.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/utils/logger.dart';
import '../../../../core/utils/ai_slop_guard.dart';
import '../../../../core/services/app_analytics_service.dart';
import '../../../../core/services/offline_mutation_outbox.dart';
import '../../../../core/services/connectivity_service.dart';
import '../../../../core/utils/link_launcher.dart';
import '../../../../shared/widgets/avatar_image_provider.dart';
import '../../../../shared/widgets/mention_helpers.dart' as mention_ui;
import '../../../../shared/widgets/rich_text_display.dart';
import '../../../../shared/widgets/social_action_button.dart';
import '../../../../shared/widgets/verified_badges.dart';
import 'package:go_router/go_router.dart';
import '../widgets/link_preview_card.dart';

class EchoRepliesScreen extends StatefulWidget {
  const EchoRepliesScreen({
    super.key,
    required this.echoId,
    required this.echoAuthorUsername,
    required this.echoContent,
    this.echoAuthorAvatarUrl,
    this.echoAuthorId,
  });

  final String echoId;
  final String echoAuthorUsername;
  final String echoContent;
  final String? echoAuthorAvatarUrl;
  final String? echoAuthorId;

  @override
  State<EchoRepliesScreen> createState() => _EchoRepliesScreenState();
}

class _EchoRepliesScreenState extends State<EchoRepliesScreen> {
  final _scrollController = ScrollController();
  final _replyKey = GlobalKey<FlutterMentionsState>();

  List<Map<String, dynamic>> _replies = [];
  Set<String> _likedReplyIds = {};
  List<Map<String, dynamic>> _mentionableUsers = [];
  bool _isLoading = true;
  bool _isSubmitting = false;
  String? _replyingToId;
  String? _replyingToUsername;
  bool _quoteOriginal = false;
  String? _evidenceUrl;

  @override
  void initState() {
    super.initState();
    _loadReplies();
    _loadMentionableUsers();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _openProfile(String username, {String? userId}) {
    final currentUserId = Supabase.instance.client.auth.currentUser?.id;

    if (userId != null && userId == currentUserId) {
      context.push('/profile');
      return;
    }

    if (username.trim().isNotEmpty) {
      context.push('/profile/${Uri.encodeComponent(username)}');
    }
  }

  Future<void> _loadMentionableUsers() async {
    try {
      final client = Supabase.instance.client;
      final rows = await client
          .from('users_public')
          .select('id, username, display_name, avatar_url, trust_tier')
          .eq('is_suspended', false)
          .limit(50);

      if (!mounted) return;
      setState(() {
        _mentionableUsers = (rows as List).map((r) {
          final map = r as Map<String, dynamic>;
          final username = map['username'] as String? ?? 'unknown';
          final displayName = (map['display_name'] as String?)?.trim();
          return {
            'id': map['id'] as String,
            'display': username,
            'name': displayName?.isNotEmpty == true ? displayName : username,
            'avatar_url': map['avatar_url'] as String? ?? '',
            'trust_tier': map['trust_tier'] as String? ?? 'unverified',
          };
        }).toList();
      });
    } catch (e) {
      AppLogger.error('replies: load mentionable users failed', e);
    }
  }

  Future<void> _loadReplies() async {
    setState(() => _isLoading = true);
    try {
      final client = Supabase.instance.client;
      final rows = await client
          .from('echo_replies')
          .select('''
            id, content, parent_reply_id, quoted_echo_id, evidence_url,
            created_at, mentioned_users,
            like_count, child_reply_count,
            users_public!inner(id, username, display_name, avatar_url, trust_tier, is_pro)
          ''')
          .eq('echo_id', widget.echoId)
          .order('created_at', ascending: true);

      final replies = List<Map<String, dynamic>>.from(rows as List);
      final replyIds = replies
          .map((reply) => reply['id'] as String?)
          .whereType<String>()
          .toList();
      final likedIds = <String>{};
      final userId = client.auth.currentUser?.id;
      if (userId != null && replyIds.isNotEmpty) {
        final likeRows = await client
            .from('echo_reply_interactions')
            .select('reply_id')
            .eq('user_id', userId)
            .eq('type', 'like')
            .filter('reply_id', 'in', '(${replyIds.join(',')})');
        likedIds.addAll(
          List<Map<String, dynamic>>.from(
            likeRows as List,
          ).map((row) => row['reply_id'] as String?).whereType<String>(),
        );
      }

      setState(() {
        _replies = replies;
        _likedReplyIds = likedIds;
        _isLoading = false;
      });
    } catch (e) {
      AppLogger.error('replies: load failed', e);
      setState(() => _isLoading = false);
    }
  }

  Future<void> _submitReply() async {
    final content = _replyKey.currentState?.controller?.text.trim() ?? '';
    if (content.isEmpty || _isSubmitting) return;

    final aiSlop = AiSlopGuard.assess(body: content, allowShort: true);
    if (aiSlop.isBlocked) {
      showErrorSnack(context, aiSlop.message);
      return;
    }
    if (aiSlop.shouldWarn) {
      final proceed = await _showAiSlopDialog(aiSlop);
      if (proceed != true) return;
    }

    setState(() => _isSubmitting = true);
    HapticFeedback.lightImpact();

    try {
      final hadEvidence = _evidenceUrl != null;
      final quotedOriginal = _quoteOriginal;
      final submission = await OfflineMutationOutbox.instance.submitReply(
        echoId: widget.echoId,
        content: content,
        parentReplyId: _replyingToId,
        quotedEchoId: quotedOriginal ? widget.echoId : null,
        evidenceUrl: _evidenceUrl,
      );

      _replyKey.currentState?.controller?.clear();
      setState(() {
        _replyingToId = null;
        _replyingToUsername = null;
        _quoteOriginal = false;
        _evidenceUrl = null;
        _isSubmitting = false;
      });

      unawaited(
        AppAnalyticsService.instance.logEvent(
          'reply_submitted',
          parameters: {
            'queued_offline': submission.queued,
            'has_evidence': hadEvidence,
            'quoted_original': quotedOriginal,
          },
        ),
      );

      if (submission.queued) {
        if (mounted) {
          showInfoSnack(
            context,
            'You are offline. Your reply will send when you reconnect.',
          );
        }
        return;
      }

      await _loadReplies();

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scrollController.hasClients) {
          _scrollController.animateTo(
            _scrollController.position.maxScrollExtent,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
          );
        }
      });
    } catch (e) {
      AppLogger.error('replies: submit failed', e);
      setState(() => _isSubmitting = false);
      if (mounted) {
        showErrorSnack(context, _friendlyReplyError(e));
      }
    }
  }

  String _friendlyReplyError(Object error) {
    final message = error.toString().toLowerCase();
    if (message.contains('ai_generated_text')) {
      return 'Please rewrite this reply in your own words.';
    }
    if (message.contains('moderation_unavailable')) {
      return 'Reply review is unavailable right now. Try again shortly.';
    }
    if (message.contains('content_policy')) {
      return 'This reply could not be posted under the content policy.';
    }
    return 'Could not post reply. Try again.';
  }

  Future<bool?> _showAiSlopDialog(AiSlopAssessment result) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          context.l('Make it more yours?'),
          style: GoogleFonts.josefinSans(fontWeight: FontWeight.w700),
        ),
        content: Text(
          context.l(result.message),
          style: GoogleFonts.josefinSans(fontSize: 13, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(context.l('Edit'), style: GoogleFonts.josefinSans()),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              context.l('Post anyway'),
              style: GoogleFonts.josefinSans(color: AppColors.fernGreenDark),
            ),
          ),
        ],
      ),
    );
  }

  void _setReplyingTo(String replyId, String username) {
    setState(() {
      _replyingToId = replyId;
      _replyingToUsername = username;
    });
    // pre-fill with @mention
    _replyKey.currentState?.controller?.text = '@$username ';
  }

  Future<void> _toggleReplyLike(String replyId) async {
    final wasLiked = _likedReplyIds.contains(replyId);
    final nextLiked = !wasLiked;
    final previousReplies = List<Map<String, dynamic>>.from(_replies);
    final previousLikedIds = Set<String>.from(_likedReplyIds);

    setState(() {
      _likedReplyIds = {..._likedReplyIds};
      if (wasLiked) {
        _likedReplyIds.remove(replyId);
      } else {
        _likedReplyIds.add(replyId);
      }
      _replies = _replies.map((reply) {
        if (reply['id'] != replyId) return reply;
        final current = (reply['like_count'] as num?)?.toInt() ?? 0;
        return {
          ...reply,
          'like_count': (current + (wasLiked ? -1 : 1))
              .clamp(0, 1 << 31)
              .toInt(),
        };
      }).toList();
    });

    if (!ConnectivityService.instance.isOnline) {
      await OfflineMutationOutbox.instance.setReplyLike(
        replyId: replyId,
        liked: nextLiked,
      );
      if (mounted) {
        showInfoSnack(
          context,
          'You are offline. This will sync when you reconnect.',
        );
      }
      return;
    }

    try {
      final rows =
          await Supabase.instance.client.rpc(
                'set_echo_reply_like',
                params: {'p_reply_id': replyId, 'p_liked': nextLiked},
              )
              as List;
      final row = rows.isEmpty ? null : rows.first as Map<String, dynamic>?;
      final liked = row?['liked'] as bool? ?? nextLiked;
      final nextCount = (row?['like_count'] as num?)?.toInt();

      setState(() {
        _likedReplyIds = {..._likedReplyIds};
        if (liked) {
          _likedReplyIds.add(replyId);
        } else {
          _likedReplyIds.remove(replyId);
        }
        _replies = _replies.map((reply) {
          if (reply['id'] != replyId) return reply;
          return {
            ...reply,
            'like_count':
                nextCount ??
                ((reply['like_count'] as num?)?.toInt() ?? 0)
                    .clamp(0, 1 << 31)
                    .toInt(),
          };
        }).toList();
      });
      if (liked) {
        unawaited(_notifySocialEvent('reply_like', {'reply_id': replyId}));
      }
      unawaited(
        AppAnalyticsService.instance.logEvent(
          'reply_like_changed',
          parameters: {'liked': liked, 'queued_offline': false},
        ),
      );
    } catch (e) {
      if (e is! PostgrestException) {
        await OfflineMutationOutbox.instance.setReplyLike(
          replyId: replyId,
          liked: nextLiked,
        );
        if (mounted) {
          showInfoSnack(
            context,
            'Connection is unstable. This will sync when you reconnect.',
          );
        }
        return;
      }
      if (!mounted) return;
      setState(() {
        _likedReplyIds = previousLikedIds;
        _replies = previousReplies;
      });
      if (mounted) showErrorSnack(context, 'Could not update reply like.');
    }
  }

  Future<void> _notifySocialEvent(
    String event,
    Map<String, dynamic> body,
  ) async {
    try {
      await Supabase.instance.client.functions.invoke(
        'notify-social-event',
        body: {'event': event, ...body},
      );
    } catch (e) {
      AppLogger.warn('replies: social event notify failed $e');
    }
  }

  Future<void> _deleteReply(String replyId) async {
    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: AppColors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(AppSpacing.radiusLg),
        ),
      ),
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Delete this reply?',
                style: AppTypography.textTheme.titleMedium,
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                'Reply deletion is limited to 1 per day and checked on the server.',
                style: AppTypography.textTheme.bodySmall?.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              Row(
                children: [
                  Expanded(
                    child: TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text('Cancel'),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () => Navigator.pop(context, true),
                      icon: const Icon(Icons.delete_outline_rounded, size: 17),
                      label: const Text('Delete'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.sunsetCoral,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );

    if (confirmed != true) return;

    try {
      await Supabase.instance.client.rpc(
        'delete_own_reply_limited',
        params: {'p_reply_id': replyId},
      );
      setState(() {
        final byParent = <String, List<Map<String, dynamic>>>{};
        for (final reply in _replies) {
          final parentId = reply['parent_reply_id'] as String?;
          if (parentId == null) continue;
          byParent.putIfAbsent(parentId, () => []).add(reply);
        }
        final removedIds = <String>{replyId};
        void collectChildren(String parentId) {
          for (final child
              in byParent[parentId] ?? const <Map<String, dynamic>>[]) {
            final childId = child['id'] as String?;
            if (childId == null || !removedIds.add(childId)) continue;
            collectChildren(childId);
          }
        }

        collectChildren(replyId);
        _replies = _replies
            .where((reply) => !removedIds.contains(reply['id'] as String?))
            .toList();
        _likedReplyIds = _likedReplyIds
            .where((id) => !removedIds.contains(id))
            .toSet();
      });
      if (mounted) showSuccessSnack(context, 'Reply deleted');
    } catch (e) {
      final message = e.toString().contains('daily_reply_delete_limit')
          ? 'You can delete only 1 reply per day.'
          : 'Could not delete reply.';
      if (mounted) showErrorSnack(context, message);
    }
  }

  void _cancelReply() {
    setState(() {
      _replyingToId = null;
      _replyingToUsername = null;
    });
    _replyKey.currentState?.controller?.clear();
  }

  void _toggleQuoteOriginal() {
    setState(() => _quoteOriginal = !_quoteOriginal);
  }

  Future<void> _editEvidenceUrl() async {
    final controller = TextEditingController(text: _evidenceUrl ?? '');
    final result = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: AppColors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) {
        return AnimatedPadding(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          padding: EdgeInsets.only(
            bottom: MediaQuery.viewInsetsOf(sheetContext).bottom,
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              AppSpacing.lg,
              AppSpacing.lg,
              AppSpacing.xl,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Add source', style: AppTypography.textTheme.titleMedium),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  'Use a secure link that supports your reply.',
                  style: AppTypography.textTheme.bodySmall?.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),
                TextField(
                  controller: controller,
                  keyboardType: TextInputType.url,
                  autofocus: true,
                  textInputAction: TextInputAction.done,
                  decoration: const InputDecoration(
                    hintText: 'https://source.example',
                    prefixIcon: Icon(Icons.link_rounded),
                  ),
                  onSubmitted: (value) => Navigator.pop(sheetContext, value),
                ),
                const SizedBox(height: AppSpacing.lg),
                Row(
                  children: [
                    TextButton(
                      onPressed: () => Navigator.pop(sheetContext, ''),
                      child: const Text('Remove'),
                    ),
                    const Spacer(),
                    FilledButton(
                      onPressed: () =>
                          Navigator.pop(sheetContext, controller.text),
                      child: const Text('Add source'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
    controller.dispose();
    if (result == null || !mounted) return;

    final value = result.trim();
    if (value.isNotEmpty && Uri.tryParse(value)?.scheme != 'https') {
      showWarningSnack(context, 'Use a secure https link for a source.');
      return;
    }
    setState(() => _evidenceUrl = value.isEmpty ? null : value);
  }

  @override
  Widget build(BuildContext context) {
    // group replies into threads: top-level and their children
    final topLevel = _replies
        .where((r) => r['parent_reply_id'] == null)
        .toList();
    final byParent = <String, List<Map<String, dynamic>>>{};
    for (final reply in _replies) {
      final parentId = reply['parent_reply_id'] as String?;
      if (parentId == null) continue;
      byParent.putIfAbsent(parentId, () => []).add(reply);
    }
    List<Map<String, dynamic>> collectDescendants(String parentId) {
      final direct = byParent[parentId] ?? const <Map<String, dynamic>>[];
      return [
        for (final child in direct) ...[
          child,
          ...collectDescendants(child['id'] as String),
        ],
      ];
    }

    final currentUserId = Supabase.instance.client.auth.currentUser?.id;

    return Scaffold(
      backgroundColor: AppColors.white,
      appBar: AppBar(
        backgroundColor: AppColors.white,
        elevation: 0,
        scrolledUnderElevation: 0.5,
        shadowColor: AppColors.borderSubtle,
        title: Text(
          context.l('Thread'),
          style: AppTypography.textTheme.titleLarge,
        ),
        foregroundColor: AppColors.charcoal,
      ),
      body: Column(
        children: [
          Expanded(
            child: _isLoading
                ? const Center(
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: AppColors.fernGreen,
                    ),
                  )
                : RefreshIndicator(
                    color: AppColors.fernGreen,
                    onRefresh: _loadReplies,
                    child: ListView.builder(
                      controller: _scrollController,
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.only(bottom: 16),
                      itemCount: topLevel.length + 1,
                      itemBuilder: (context, index) {
                        if (index == 0) {
                          return _OriginalEchoHeader(
                            authorUsername: widget.echoAuthorUsername,
                            authorAvatarUrl: widget.echoAuthorAvatarUrl,
                            authorId: widget.echoAuthorId,
                            content: widget.echoContent,
                            onAuthorTap: (username, userId) =>
                                _openProfile(username, userId: userId),
                            onMentionTap: (username) => _openProfile(username),
                          );
                        }
                        final reply = topLevel[index - 1];
                        final children = collectDescendants(
                          reply['id'] as String,
                        );

                        return _ReplyThread(
                          reply: reply,
                          children: children,
                          onReply: (id, username) =>
                              _setReplyingTo(id, username),
                          onLike: _toggleReplyLike,
                          onDelete: _deleteReply,
                          onAuthorTap: (username, userId) =>
                              _openProfile(username, userId: userId),
                          isLastTop: index == topLevel.length,
                          currentUserId: currentUserId,
                          likedReplyIds: _likedReplyIds,
                        );
                      },
                    ),
                  ),
          ),
          _ReplyInput(
            replyKey: _replyKey,
            replyingToUsername: _replyingToUsername,
            mentionableUsers: _mentionableUsers,
            isSubmitting: _isSubmitting,
            quoteOriginal: _quoteOriginal,
            evidenceUrl: _evidenceUrl,
            onSubmit: _submitReply,
            onCancelReply: _cancelReply,
            onQuoteTap: _toggleQuoteOriginal,
            onEvidenceTap: _editEvidenceUrl,
          ),
        ],
      ),
    );
  }
}

class _OriginalEchoHeader extends StatefulWidget {
  const _OriginalEchoHeader({
    required this.authorUsername,
    required this.authorAvatarUrl,
    required this.authorId,
    required this.content,
    required this.onAuthorTap,
    required this.onMentionTap,
  });

  final String authorUsername;
  final String? authorAvatarUrl;
  final String? authorId;
  final String content;
  final void Function(String username, String? userId) onAuthorTap;
  final ValueChanged<String> onMentionTap;

  @override
  State<_OriginalEchoHeader> createState() => _OriginalEchoHeaderState();
}

class _OriginalEchoHeaderState extends State<_OriginalEchoHeader> {
  bool _previewUnavailable = false;

  @override
  void didUpdateWidget(covariant _OriginalEchoHeader oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.content != widget.content) {
      _previewUnavailable = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final previewUrl = extractFirstUrl(widget.content);
    final hideUrlText = previewUrl != null && !_previewUnavailable;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.xl),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.borderSubtle)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              GestureDetector(
                onTap: () =>
                    widget.onAuthorTap(widget.authorUsername, widget.authorId),
                child: _VerifiedAvatar(
                  avatarUrl: widget.authorAvatarUrl,
                  isVerified: false,
                  size: 40,
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              GestureDetector(
                onTap: () =>
                    widget.onAuthorTap(widget.authorUsername, widget.authorId),
                child: Text(
                  '@${widget.authorUsername}',
                  style: AppTypography.textTheme.titleSmall,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          RichTextDisplay(
            text: widget.content,
            style: AppTypography.textTheme.bodyLarge,
            hideUrls: hideUrlText,
            onMentionTap: widget.onMentionTap,
          ),
          if (previewUrl != null)
            EchoLinkPreview(
              url: previewUrl,
              variant: EchoLinkPreviewVariant.compact,
              onUnavailable: () {
                if (mounted) setState(() => _previewUnavailable = true);
              },
            ),
          const SizedBox(height: AppSpacing.md),
          Text(
            context.l('Replies'),
            style: AppTypography.textTheme.labelMedium,
          ),
        ],
      ),
    );
  }
}

class _ReplyThread extends StatelessWidget {
  const _ReplyThread({
    required this.reply,
    required this.children,
    required this.onReply,
    required this.onLike,
    required this.onDelete,
    required this.onAuthorTap,
    required this.isLastTop,
    required this.currentUserId,
    required this.likedReplyIds,
  });

  final Map<String, dynamic> reply;
  final List<Map<String, dynamic>> children;
  final void Function(String replyId, String username) onReply;
  final void Function(String replyId) onLike;
  final void Function(String replyId) onDelete;
  final void Function(String username, String? userId) onAuthorTap;
  final bool isLastTop;
  final String? currentUserId;
  final Set<String> likedReplyIds;

  @override
  Widget build(BuildContext context) {
    final user = reply['users_public'] as Map<String, dynamic>? ?? {};
    final username = user['username'] as String? ?? 'unknown';
    final displayName =
        (user['display_name'] as String?)?.trim().isNotEmpty == true
        ? user['display_name'] as String
        : username;
    final avatarUrl = user['avatar_url'] as String?;
    final created =
        DateTime.tryParse(reply['created_at'] as String? ?? '') ??
        DateTime.now();
    final userId = user['id'] as String?;
    final replyId = reply['id'] as String;
    final storedChildCount = (reply['child_reply_count'] as num?)?.toInt() ?? 0;
    final childCount = storedChildCount < children.length
        ? children.length
        : storedChildCount;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // avatar column with thread line below
              SizedBox(
                width: 56,
                child: Column(
                  children: [
                    const SizedBox(height: AppSpacing.lg),
                    GestureDetector(
                      onTap: () => onAuthorTap(username, userId),
                      child: _VerifiedAvatar(
                        avatarUrl: avatarUrl,
                        isVerified: _isBadgedUser(user),
                        size: 36,
                      ),
                    ),
                    if (children.isNotEmpty)
                      Expanded(
                        child: Container(
                          width: 2,
                          margin: const EdgeInsets.symmetric(vertical: 4),
                          color: AppColors.borderSubtle,
                        ),
                      ),
                  ],
                ),
              ),
              // reply content
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(
                    top: AppSpacing.lg,
                    right: AppSpacing.lg,
                    bottom: AppSpacing.sm,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _ReplyHeader(
                        displayName: displayName,
                        username: username,
                        created: created,
                        user: user,
                        onTap: () => onAuthorTap(username, userId),
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      _ReplyTextWithPreview(
                        content: reply['content'] as String? ?? '',
                        quotedOriginal: reply['quoted_echo_id'] != null,
                        evidenceUrl: reply['evidence_url'] as String?,
                        onMentionTap: (username) => onAuthorTap(username, null),
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      _ReplyActions(
                        replyId: replyId,
                        username: username,
                        isLiked: likedReplyIds.contains(replyId),
                        isOwnReply: userId != null && userId == currentUserId,
                        likeCount: (reply['like_count'] as num?)?.toInt() ?? 0,
                        childReplyCount: childCount,
                        onReply: onReply,
                        onLike: onLike,
                        onDelete: onDelete,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        // nested children
        ...children.map(
          (child) => _NestedReply(
            reply: child,
            onReply: onReply,
            onLike: onLike,
            onDelete: onDelete,
            onAuthorTap: onAuthorTap,
            currentUserId: currentUserId,
            likedReplyIds: likedReplyIds,
          ),
        ),
        if (!isLastTop) const Divider(height: 1, indent: 56),
      ],
    );
  }
}

class _NestedReply extends StatelessWidget {
  const _NestedReply({
    required this.reply,
    required this.onReply,
    required this.onLike,
    required this.onDelete,
    required this.onAuthorTap,
    required this.currentUserId,
    required this.likedReplyIds,
  });

  final Map<String, dynamic> reply;
  final void Function(String replyId, String username) onReply;
  final void Function(String replyId) onLike;
  final void Function(String replyId) onDelete;
  final void Function(String username, String? userId) onAuthorTap;
  final String? currentUserId;
  final Set<String> likedReplyIds;

  @override
  Widget build(BuildContext context) {
    final user = reply['users_public'] as Map<String, dynamic>? ?? {};
    final username = user['username'] as String? ?? 'unknown';
    final displayName =
        (user['display_name'] as String?)?.trim().isNotEmpty == true
        ? user['display_name'] as String
        : username;
    final avatarUrl = user['avatar_url'] as String?;
    final userId = user['id'] as String?;
    final created =
        DateTime.tryParse(reply['created_at'] as String? ?? '') ??
        DateTime.now();
    final replyId = reply['id'] as String;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // indent + thread connector
        SizedBox(
          width: 56,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              Container(
                width: 20,
                height: 20,
                decoration: const BoxDecoration(
                  border: Border(
                    left: BorderSide(color: AppColors.borderSubtle, width: 2),
                    bottom: BorderSide(color: AppColors.borderSubtle, width: 2),
                  ),
                  borderRadius: BorderRadius.only(
                    bottomLeft: Radius.circular(8),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: AppSpacing.xs),
        GestureDetector(
          onTap: () => onAuthorTap(username, userId),
          child: _VerifiedAvatar(
            avatarUrl: avatarUrl,
            isVerified: _isBadgedUser(user),
            size: 36,
          ),
        ),

        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(
              top: AppSpacing.sm,
              right: AppSpacing.lg,
              bottom: AppSpacing.sm,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _ReplyHeader(
                  displayName: displayName,
                  username: username,
                  created: created,
                  user: user,
                  onTap: () => onAuthorTap(username, userId),
                ),
                const SizedBox(height: AppSpacing.xs),
                _ReplyTextWithPreview(
                  content: reply['content'] as String? ?? '',
                  quotedOriginal: reply['quoted_echo_id'] != null,
                  evidenceUrl: reply['evidence_url'] as String?,
                  onMentionTap: (username) => onAuthorTap(username, null),
                ),
                const SizedBox(height: AppSpacing.xs),
                _ReplyActions(
                  replyId: replyId,
                  username: username,
                  isLiked: likedReplyIds.contains(replyId),
                  isOwnReply: userId != null && userId == currentUserId,
                  likeCount: (reply['like_count'] as num?)?.toInt() ?? 0,
                  childReplyCount:
                      (reply['child_reply_count'] as num?)?.toInt() ?? 0,
                  onReply: onReply,
                  onLike: onLike,
                  onDelete: onDelete,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _ReplyHeader extends StatelessWidget {
  const _ReplyHeader({
    required this.displayName,
    required this.username,
    required this.created,
    required this.user,
    required this.onTap,
  });

  final String displayName;
  final String username;
  final DateTime created;
  final Map<String, dynamic> user;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Flexible(
          child: GestureDetector(
            onTap: onTap,
            child: Text(
              displayName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTypography.textTheme.titleSmall,
            ),
          ),
        ),
        _InlineReplyBadge(user: user),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Text(
            '@$username · ${Formatters.timeAgo(created)}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTypography.textTheme.labelMedium,
          ),
        ),
      ],
    );
  }
}

class _ReplyTextWithPreview extends StatefulWidget {
  const _ReplyTextWithPreview({
    required this.content,
    required this.quotedOriginal,
    required this.evidenceUrl,
    required this.onMentionTap,
  });

  final String content;
  final bool quotedOriginal;
  final String? evidenceUrl;
  final ValueChanged<String> onMentionTap;

  @override
  State<_ReplyTextWithPreview> createState() => _ReplyTextWithPreviewState();
}

class _ReplyTextWithPreviewState extends State<_ReplyTextWithPreview> {
  bool _previewUnavailable = false;

  @override
  void didUpdateWidget(covariant _ReplyTextWithPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.content != widget.content) {
      _previewUnavailable = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final previewUrl = extractFirstUrl(widget.content);
    final hideUrlText = previewUrl != null && !_previewUnavailable;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        RichTextDisplay(
          text: widget.content,
          style: AppTypography.textTheme.bodyMedium,
          hideUrls: hideUrlText,
          onMentionTap: widget.onMentionTap,
        ),
        if (widget.quotedOriginal || widget.evidenceUrl != null)
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.xs),
            child: Wrap(
              spacing: AppSpacing.xs,
              runSpacing: AppSpacing.xs,
              children: [
                if (widget.quotedOriginal)
                  const _ReplyReferenceChip(
                    icon: Icons.format_quote_rounded,
                    label: 'Quoted original echo',
                  ),
                if (widget.evidenceUrl != null)
                  _ReplyReferenceChip(
                    icon: Icons.link_rounded,
                    label: _sourceLabel(widget.evidenceUrl!),
                    onTap: () => showOpenLinkSheet(
                      context,
                      url: widget.evidenceUrl!,
                      title: 'Source',
                    ),
                  ),
              ],
            ),
          ),
        if (previewUrl != null)
          EchoLinkPreview(
            url: previewUrl,
            variant: EchoLinkPreviewVariant.compact,
            onUnavailable: () {
              if (mounted) setState(() => _previewUnavailable = true);
            },
          ),
      ],
    );
  }
}

String _sourceLabel(String url) {
  final host = Uri.tryParse(url)?.host.trim();
  return host == null || host.isEmpty ? 'Source' : host;
}

class _ReplyReferenceChip extends StatelessWidget {
  const _ReplyReferenceChip({
    required this.icon,
    required this.label,
    this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.fernGreenLight,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 13, color: AppColors.fernGreenDark),
              const SizedBox(width: 4),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 180),
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.josefinSans(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: AppColors.fernGreenDark,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ReplyActions extends StatelessWidget {
  const _ReplyActions({
    required this.replyId,
    required this.username,
    required this.isLiked,
    required this.isOwnReply,
    required this.likeCount,
    required this.childReplyCount,
    required this.onReply,
    required this.onLike,
    required this.onDelete,
  });

  final String replyId;
  final String username;
  final bool isLiked;
  final bool isOwnReply;
  final int likeCount;
  final int childReplyCount;
  final void Function(String replyId, String username) onReply;
  final void Function(String replyId) onLike;
  final void Function(String replyId) onDelete;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _ReplyActionChip(
          icon: Icons.favorite_border_rounded,
          activeIcon: Icons.favorite_rounded,
          label: likeCount > 0 ? Formatters.compactNumber(likeCount) : '',
          active: isLiked,
          showBurst: true,
          onTap: () => onLike(replyId),
        ),
        const SizedBox(width: AppSpacing.lg),
        _ReplyActionChip(
          icon: Icons.mode_comment_outlined,
          label: childReplyCount > 0
              ? Formatters.compactNumber(childReplyCount)
              : context.l('Reply'),
          active: false,
          showBurst: false,
          onTap: () => onReply(replyId, username),
        ),
        const Spacer(),
        if (isOwnReply)
          Tooltip(
            message: 'Delete reply',
            child: InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: () => onDelete(replyId),
              child: const Padding(
                padding: EdgeInsets.all(4),
                child: Icon(
                  Icons.delete_outline_rounded,
                  size: 17,
                  color: AppColors.textTertiary,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _ReplyActionChip extends StatelessWidget {
  const _ReplyActionChip({
    required this.icon,
    this.activeIcon,
    required this.label,
    required this.active,
    required this.showBurst,
    required this.onTap,
  });

  final IconData icon;
  final IconData? activeIcon;
  final String label;
  final bool active;
  final bool showBurst;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SocialActionButton(
      icon: icon,
      activeIcon: activeIcon,
      label: label,
      active: active,
      compact: true,
      minWidth: label.isEmpty ? 34 : 46,
      activeColor: AppColors.sunsetCoral,
      inactiveColor: AppColors.textTertiary,
      showBurst: showBurst,
      onTap: onTap,
    );
  }
}

class _InlineReplyBadge extends StatelessWidget {
  const _InlineReplyBadge({required this.user});

  final Map<String, dynamic> user;

  @override
  Widget build(BuildContext context) {
    final isPro = user['is_pro'] as bool? ?? false;
    final trustTier = user['trust_tier'] as String? ?? 'unverified';
    final isTrusted = trustTier == 'high' || trustTier == 'elite';

    if (!isPro && !isTrusted) return const SizedBox.shrink();

    return Tooltip(
      message: isPro ? 'Pro' : 'Trusted',
      child: const Padding(
        padding: EdgeInsets.only(left: 4),
        child: AccountVerifiedBadge(size: 15),
      ),
    );
  }
}

bool _isBadgedUser(Map<String, dynamic> user) {
  final trustTier = user['trust_tier'] as String? ?? 'unverified';
  return (user['is_pro'] as bool? ?? false) ||
      trustTier == 'high' ||
      trustTier == 'elite';
}

class _ReplyInput extends StatefulWidget {
  const _ReplyInput({
    required this.replyKey,
    required this.replyingToUsername,
    required this.mentionableUsers,
    required this.isSubmitting,
    required this.quoteOriginal,
    required this.evidenceUrl,
    required this.onSubmit,
    required this.onCancelReply,
    required this.onQuoteTap,
    required this.onEvidenceTap,
  });

  final GlobalKey<FlutterMentionsState> replyKey;
  final String? replyingToUsername;
  final List<Map<String, dynamic>> mentionableUsers;
  final bool isSubmitting;
  final bool quoteOriginal;
  final String? evidenceUrl;
  final VoidCallback onSubmit;
  final VoidCallback onCancelReply;
  final VoidCallback onQuoteTap;
  final Future<void> Function() onEvidenceTap;

  @override
  State<_ReplyInput> createState() => _ReplyInputState();
}

class _ReplyInputState extends State<_ReplyInput> {
  bool _focused = false;
  String _mentionSearch = '';
  bool _mentionSuggestionsVisible = false;

  void _hideMentionSuggestions() {
    mention_ui.hideMentionSuggestions(widget.replyKey);
    if (_mentionSuggestionsVisible || _mentionSearch.isNotEmpty) {
      setState(() {
        _mentionSuggestionsVisible = false;
        _mentionSearch = '';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final replyKey = widget.replyKey;
    final replyingToUsername = widget.replyingToUsername;
    final mentionableUsers = mention_ui.visibleMentionUsers(
      _mentionSearch,
      widget.mentionableUsers,
    );
    final isSubmitting = widget.isSubmitting;
    final quoteOriginal = widget.quoteOriginal;
    final evidenceUrl = widget.evidenceUrl;
    final onSubmit = widget.onSubmit;
    final onCancelReply = widget.onCancelReply;

    return Container(
      decoration: const BoxDecoration(
        color: AppColors.white,
        border: Border(top: BorderSide(color: AppColors.borderSubtle)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // replying to banner - like twitter
            if (replyingToUsername != null)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.lg,
                  vertical: AppSpacing.xs,
                ),
                color: AppColors.fernGreenLight,
                child: Row(
                  children: [
                    Text(
                      context.l('Replying to @{username}', {
                        'username': replyingToUsername,
                      }),
                      style: GoogleFonts.josefinSans(
                        fontSize: 12,
                        color: AppColors.fernGreenDark,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const Spacer(),
                    GestureDetector(
                      onTap: onCancelReply,
                      child: const Icon(
                        Icons.close,
                        size: 16,
                        color: AppColors.fernGreenDark,
                      ),
                    ),
                  ],
                ),
              ),
            AnimatedSize(
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOutCubic,
              child: quoteOriginal || evidenceUrl != null
                  ? Padding(
                      padding: const EdgeInsets.fromLTRB(
                        AppSpacing.lg,
                        AppSpacing.xs,
                        AppSpacing.lg,
                        0,
                      ),
                      child: Row(
                        children: [
                          if (quoteOriginal)
                            const _ComposerMetaChip(
                              icon: Icons.format_quote_rounded,
                              label: 'Quoting original echo',
                            ),
                          if (quoteOriginal && evidenceUrl != null)
                            const SizedBox(width: AppSpacing.xs),
                          if (evidenceUrl != null)
                            Expanded(
                              child: _ComposerMetaChip(
                                icon: Icons.link_rounded,
                                label:
                                    Uri.tryParse(
                                          evidenceUrl,
                                        )?.host.isNotEmpty ==
                                        true
                                    ? Uri.parse(evidenceUrl).host
                                    : 'Source added',
                              ),
                            ),
                        ],
                      ),
                    )
                  : const SizedBox.shrink(),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md,
                vertical: AppSpacing.sm,
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Container(
                    width: 34,
                    height: 34,
                    margin: const EdgeInsets.only(bottom: 3),
                    decoration: BoxDecoration(
                      color: AppColors.fernGreenLight,
                      borderRadius: BorderRadius.circular(17),
                    ),
                    child: const Icon(
                      Icons.mode_comment_outlined,
                      size: 17,
                      color: AppColors.fernGreenDark,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Focus(
                      onFocusChange: (focused) {
                        if (_focused == focused) return;
                        setState(() => _focused = focused);
                        if (!focused) _hideMentionSuggestions();
                      },
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 180),
                        curve: Curves.easeOutCubic,
                        decoration: BoxDecoration(
                          color: AppColors.surfaceSecondary,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: _focused
                                ? AppColors.fernGreen
                                : AppColors.borderSubtle,
                            width: _focused ? 1.2 : 1,
                          ),
                          boxShadow: [
                            if (_focused)
                              BoxShadow(
                                color: AppColors.fernGreen.withValues(
                                  alpha: 0.10,
                                ),
                                blurRadius: 16,
                                offset: const Offset(0, 8),
                              ),
                          ],
                        ),
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.md,
                          vertical: AppSpacing.xs,
                        ),
                        child: Builder(
                          builder: (mentionContext) {
                            final suggestionPosition = mention_ui
                                .adaptiveMentionSuggestionPosition(
                                  mentionContext,
                                  listHeight: 220,
                                  preferTopWhenCrowded: true,
                                  forceTop: true,
                                );
                            final suggestionHeight = mention_ui
                                .adaptiveMentionSuggestionHeight(
                                  mentionContext,
                                  position: suggestionPosition,
                                  maxHeight: 220,
                                );

                            return mention_ui.CompactMentionSuggestions(
                              visible: _mentionSuggestionsVisible,
                              position: suggestionPosition,
                              suggestionHeight: suggestionHeight,
                              suggestions: mentionableUsers,
                              mentionKey: replyKey,
                              onSelected: (_) {
                                setState(() {
                                  _mentionSuggestionsVisible = false;
                                  _mentionSearch = '';
                                });
                              },
                              child: FlutterMentions(
                                key: replyKey,
                                hideSuggestionList: true,
                                suggestionPosition: suggestionPosition,
                                suggestionListHeight: suggestionHeight,
                                onSuggestionVisibleChanged: (visible) {
                                  if (_mentionSuggestionsVisible == visible) {
                                    return;
                                  }
                                  setState(() {
                                    _mentionSuggestionsVisible = visible;
                                    if (!visible) _mentionSearch = '';
                                  });
                                },
                                onSearchChanged: (trigger, value) {
                                  if (trigger != '@' ||
                                      _mentionSearch == value) {
                                    return;
                                  }
                                  setState(() => _mentionSearch = value);
                                },
                                maxLines: 5,
                                minLines: 1,
                                style: AppTypography.textTheme.bodyMedium,
                                decoration: InputDecoration(
                                  hintText: replyingToUsername != null
                                      ? context.l('Reply to @{username}...', {
                                          'username': replyingToUsername,
                                        })
                                      : context.l('Add a reply...'),
                                  hintStyle: GoogleFonts.josefinSans(
                                    fontSize: 14,
                                    color: AppColors.textTertiary,
                                  ),
                                  border: InputBorder.none,
                                  enabledBorder: InputBorder.none,
                                  focusedBorder: InputBorder.none,
                                  errorBorder: InputBorder.none,
                                  focusedErrorBorder: InputBorder.none,
                                  disabledBorder: InputBorder.none,
                                  isDense: true,
                                  contentPadding: const EdgeInsets.symmetric(
                                    vertical: 8,
                                  ),
                                ),
                                suggestionListDecoration: mention_ui
                                    .mentionSuggestionDecoration(
                                      suggestionPosition,
                                    ),
                                mentions: [
                                  Mention(
                                    trigger: '@',
                                    style: GoogleFonts.josefinSans(
                                      color: AppColors.fernGreen,
                                      fontWeight: FontWeight.w600,
                                    ),
                                    data: widget.mentionableUsers,
                                    suggestionBuilder: (data) =>
                                        mention_ui.MentionSuggestionTile(
                                          data: data,
                                        ),
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
                            );
                          },
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Tooltip(
                    message: quoteOriginal
                        ? 'Remove original quote'
                        : 'Quote original echo',
                    child: IconButton(
                      onPressed: isSubmitting ? null : widget.onQuoteTap,
                      icon: Icon(
                        quoteOriginal
                            ? Icons.format_quote_rounded
                            : Icons.format_quote_outlined,
                      ),
                      color: quoteOriginal
                          ? AppColors.fernGreenDark
                          : AppColors.textSecondary,
                    ),
                  ),
                  Tooltip(
                    message: evidenceUrl == null ? 'Add source' : 'Edit source',
                    child: IconButton(
                      onPressed: isSubmitting
                          ? null
                          : () => widget.onEvidenceTap(),
                      icon: Icon(
                        evidenceUrl == null
                            ? Icons.link_rounded
                            : Icons.link_off_rounded,
                      ),
                      color: evidenceUrl == null
                          ? AppColors.textSecondary
                          : AppColors.fernGreenDark,
                    ),
                  ),
                  GestureDetector(
                    onTap: isSubmitting ? null : onSubmit,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      height: 40,
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      decoration: BoxDecoration(
                        color: isSubmitting
                            ? AppColors.borderSubtle
                            : AppColors.charcoal,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Center(
                        child: isSubmitting
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: AppColors.white,
                                ),
                              )
                            : Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    context.l('Reply'),
                                    style: GoogleFonts.josefinSans(
                                      color: AppColors.white,
                                      fontSize: 13,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  const SizedBox(width: 4),
                                  const Icon(
                                    Icons.arrow_upward_rounded,
                                    color: AppColors.white,
                                    size: 17,
                                  ),
                                ],
                              ),
                      ),
                    ),
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

class _ComposerMetaChip extends StatelessWidget {
  const _ComposerMetaChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 220),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: AppColors.fernGreenLight,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: AppColors.fernGreenDark),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.josefinSans(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: AppColors.fernGreenDark,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _VerifiedAvatar extends StatelessWidget {
  const _VerifiedAvatar({
    required this.avatarUrl,
    required this.isVerified,
    required this.size,
  });

  final String? avatarUrl;
  final bool isVerified;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size + 4,
      height: size + 4,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: isVerified ? AppColors.fernGreen : AppColors.borderSubtle,
          width: isVerified ? 1.5 : 1.0,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(2),
        child: CircleAvatar(
          radius: size / 2,
          backgroundColor: AppColors.softSand,
          backgroundImage: avatarImageProvider(avatarUrl),
          child: avatarImageProvider(avatarUrl) == null
              ? Icon(
                  Icons.person_outline,
                  size: size * 0.5,
                  color: AppColors.textTertiary,
                )
              : null,
        ),
      ),
    );
  }
}
