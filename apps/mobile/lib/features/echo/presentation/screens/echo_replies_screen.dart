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
import '../../../../shared/widgets/avatar_image_provider.dart';
import '../../../../shared/widgets/rich_text_display.dart';
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
          .select('id, username, avatar_url, trust_tier')
          .eq('is_suspended', false)
          .limit(50);

      setState(() {
        _mentionableUsers = (rows as List).map((r) {
          final map = r as Map<String, dynamic>;
          return {
            'id': map['id'] as String,
            'display': map['username'] as String,
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
            id, content, parent_reply_id, created_at, mentioned_users,
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
          List<Map<String, dynamic>>.from(likeRows as List)
              .map((row) => row['reply_id'] as String?)
              .whereType<String>(),
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

    setState(() => _isSubmitting = true);
    HapticFeedback.lightImpact();

    try {
      final client = Supabase.instance.client;
      final userId = client.auth.currentUser?.id;
      if (userId == null) throw Exception('not authenticated');

      final inserted = await client
          .from('echo_replies')
          .insert({
            'echo_id': widget.echoId,
            'user_id': userId,
            'content': content,
            'parent_reply_id': _replyingToId,
          })
          .select('id')
          .single();
      final replyId = inserted['id'] as String?;
      if (replyId != null) {
        unawaited(_notifySocialEvent('echo_reply', {'reply_id': replyId}));
      }

      await client.rpc(
        'increment_reply_count',
        params: {'p_echo_id': widget.echoId},
      );

      _replyKey.currentState?.controller?.clear();
      setState(() {
        _replyingToId = null;
        _replyingToUsername = null;
        _isSubmitting = false;
      });

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
        showErrorSnack(context, e.toString());
      }
    }
  }

  void _setReplyingTo(String replyId, String username) {
    setState(() {
      _replyingToId = replyId;
      _replyingToUsername = username;
    });
    // Pre-fill with @mention
    _replyKey.currentState?.controller?.text = '@$username ';
  }

  Future<void> _toggleReplyLike(String replyId) async {
    try {
      final rows = await Supabase.instance.client.rpc(
        'toggle_echo_reply_like',
        params: {'p_reply_id': replyId},
      ) as List;
      final row = rows.isEmpty ? null : rows.first as Map<String, dynamic>;
      final liked = row?['liked'] as bool? ?? !_likedReplyIds.contains(replyId);
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
            'like_count': nextCount ??
                ((reply['like_count'] as num?)?.toInt() ?? 0) +
                    (liked ? 1 : -1),
          };
        }).toList();
      });
      if (liked) {
        unawaited(_notifySocialEvent('reply_like', {'reply_id': replyId}));
      }
    } catch (e) {
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
              Text('Delete this reply?',
                  style: AppTypography.textTheme.titleMedium),
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
        _likedReplyIds =
            _likedReplyIds.where((id) => !removedIds.contains(id)).toSet();
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

  @override
  Widget build(BuildContext context) {
    // Group replies into threads: top-level and their children
    final topLevel =
        _replies.where((r) => r['parent_reply_id'] == null).toList();
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
        title: Text(context.l('Thread'),
            style: AppTypography.textTheme.titleLarge),
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
                          );
                        }
                        final reply = topLevel[index - 1];
                        final children =
                            collectDescendants(reply['id'] as String);

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
            onSubmit: _submitReply,
            onCancelReply: _cancelReply,
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
  });

  final String authorUsername;
  final String? authorAvatarUrl;
  final String? authorId;
  final String content;
  final void Function(String username, String? userId) onAuthorTap;

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
        border: Border(
          bottom: BorderSide(color: AppColors.borderSubtle),
        ),
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
    final created = DateTime.tryParse(reply['created_at'] as String? ?? '') ??
        DateTime.now();
    final userId = user['id'] as String?;
    final replyId = reply['id'] as String;
    final storedChildCount = (reply['child_reply_count'] as num?)?.toInt() ?? 0;
    final childCount =
        storedChildCount < children.length ? children.length : storedChildCount;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Avatar column with thread line below
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
              // Reply content
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
        // Nested children
        ...children.map((child) => _NestedReply(
              reply: child,
              onReply: onReply,
              onLike: onLike,
              onDelete: onDelete,
              onAuthorTap: onAuthorTap,
              currentUserId: currentUserId,
              likedReplyIds: likedReplyIds,
            )),
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
    final created = DateTime.tryParse(reply['created_at'] as String? ?? '') ??
        DateTime.now();
    final replyId = reply['id'] as String;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Indent + thread connector
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
  const _ReplyTextWithPreview({required this.content});

  final String content;

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
          icon: isLiked ? Icons.favorite_rounded : Icons.favorite_border,
          label: likeCount > 0 ? Formatters.compactNumber(likeCount) : '',
          active: isLiked,
          onTap: () => onLike(replyId),
        ),
        const SizedBox(width: AppSpacing.lg),
        _ReplyActionChip(
          icon: Icons.mode_comment_outlined,
          label: childReplyCount > 0
              ? Formatters.compactNumber(childReplyCount)
              : context.l('Reply'),
          active: false,
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
    required this.label,
    required this.active,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = active ? AppColors.sunsetCoral : AppColors.textTertiary;
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedScale(
              scale: active ? 1.08 : 1.0,
              duration: const Duration(milliseconds: 160),
              curve: Curves.easeOutBack,
              child: Icon(icon, size: 16, color: color),
            ),
            if (label.isNotEmpty) ...[
              const SizedBox(width: 4),
              AnimatedDefaultTextStyle(
                duration: const Duration(milliseconds: 160),
                style: GoogleFonts.josefinSans(
                  fontSize: 12,
                  color: color,
                  fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                ),
                child: Text(label),
              ),
            ],
          ],
        ),
      ),
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

    final color = isPro ? const Color(0xFFFFB300) : AppColors.fernGreen;
    final bg = isPro ? const Color(0xFFFFF6D7) : AppColors.fernGreenLight;
    final icon =
        isPro ? Icons.workspace_premium_rounded : Icons.verified_rounded;

    return Tooltip(
      message: isPro ? 'Pro' : 'Trusted',
      child: Container(
        width: 15,
        height: 15,
        margin: const EdgeInsets.only(left: 4),
        decoration: BoxDecoration(
          color: bg,
          shape: BoxShape.circle,
          border: Border.all(color: color.withValues(alpha: 0.35)),
        ),
        child: Icon(icon, size: 10, color: color),
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

class _ReplyInput extends StatelessWidget {
  const _ReplyInput({
    required this.replyKey,
    required this.replyingToUsername,
    required this.mentionableUsers,
    required this.isSubmitting,
    required this.onSubmit,
    required this.onCancelReply,
  });

  final GlobalKey<FlutterMentionsState> replyKey;
  final String? replyingToUsername;
  final List<Map<String, dynamic>> mentionableUsers;
  final bool isSubmitting;
  final VoidCallback onSubmit;
  final VoidCallback onCancelReply;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.white,
        border: Border(
          top: BorderSide(color: AppColors.borderSubtle),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Replying to banner - like Twitter
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
                        'username': replyingToUsername!,
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
                    child: Container(
                      decoration: BoxDecoration(
                        color: AppColors.softSand,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: AppColors.borderSubtle),
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.md,
                        vertical: AppSpacing.xs,
                      ),
                      child: FlutterMentions(
                        key: replyKey,
                        suggestionPosition: SuggestionPosition.Top,
                        maxLines: 5,
                        minLines: 1,
                        style: AppTypography.textTheme.bodyMedium,
                        decoration: InputDecoration(
                          hintText: replyingToUsername != null
                              ? context.l('Reply to @{username}...', {
                                  'username': replyingToUsername!,
                                })
                              : context.l('Add a reply...'),
                          hintStyle: GoogleFonts.josefinSans(
                            fontSize: 14,
                            color: AppColors.textTertiary,
                          ),
                          border: InputBorder.none,
                          isDense: true,
                          contentPadding:
                              const EdgeInsets.symmetric(vertical: 8),
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
                              return _MentionSuggestionTile(data: data);
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
                  ),
                  const SizedBox(width: AppSpacing.sm),
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

class _MentionSuggestionTile extends StatelessWidget {
  const _MentionSuggestionTile({required this.data});
  final Map<String, dynamic> data;

  @override
  Widget build(BuildContext context) {
    final avatarUrl = data['avatar_url'] as String?;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 16,
            backgroundColor: AppColors.softSand,
            backgroundImage: avatarImageProvider(avatarUrl),
            child: avatarImageProvider(avatarUrl) == null
                ? const Icon(Icons.person_outline,
                    size: 16, color: AppColors.textTertiary)
                : null,
          ),
          const SizedBox(width: AppSpacing.sm),
          Text(
            '@${data['display']}',
            style: AppTypography.textTheme.titleSmall,
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
              ? Icon(Icons.person_outline,
                  size: size * 0.5, color: AppColors.textTertiary)
              : null,
        ),
      ),
    );
  }
}
