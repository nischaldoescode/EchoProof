import 'package:echoproof/core/utils/snack.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_mentions/flutter_mentions.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../app/theme/colors.dart';
import '../../../../app/theme/spacing.dart';
import '../../../../app/theme/typography.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/utils/logger.dart';

class EchoRepliesScreen extends StatefulWidget {
  const EchoRepliesScreen({
    super.key,
    required this.echoId,
    required this.echoAuthorUsername,
    required this.echoContent,
  });

  final String echoId;
  final String echoAuthorUsername;
  final String echoContent;

  @override
  State<EchoRepliesScreen> createState() => _EchoRepliesScreenState();
}

class _EchoRepliesScreenState extends State<EchoRepliesScreen> {
  final _scrollController = ScrollController();
  final _replyKey = GlobalKey<FlutterMentionsState>();

  List<Map<String, dynamic>> _replies = [];
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
            users_public!inner(id, username, avatar_url, trust_tier, is_identity_verified)
          ''')
          .eq('echo_id', widget.echoId)
          .order('created_at', ascending: true);

      setState(() {
        _replies = List<Map<String, dynamic>>.from(rows as List);
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

      await client.from('echo_replies').insert({
        'echo_id': widget.echoId,
        'user_id': userId,
        'content': content,
        'parent_reply_id': _replyingToId,
      });

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
    final topLevel = _replies.where((r) => r['parent_reply_id'] == null).toList();

    return Scaffold(
      backgroundColor: AppColors.white,
      appBar: AppBar(
        backgroundColor: AppColors.white,
        elevation: 0,
        scrolledUnderElevation: 0.5,
        shadowColor: AppColors.borderSubtle,
        title: Text('Replies', style: AppTypography.textTheme.titleLarge),
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
                : ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.only(bottom: 16),
                    itemCount: topLevel.length + 1,
                    itemBuilder: (context, index) {
                      if (index == 0) {
                        return _OriginalEchoHeader(
                          authorUsername: widget.echoAuthorUsername,
                          content: widget.echoContent,
                        );
                      }
                      final reply = topLevel[index - 1];
                      final children = _replies
                          .where((r) => r['parent_reply_id'] == reply['id'])
                          .toList();

                      return _ReplyThread(
                        reply: reply,
                        children: children,
                        onReply: (id, username) => _setReplyingTo(id, username),
                        isLastTop: index == topLevel.length,
                      );
                    },
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

class _OriginalEchoHeader extends StatelessWidget {
  const _OriginalEchoHeader({
    required this.authorUsername,
    required this.content,
  });

  final String authorUsername;
  final String content;

  @override
  Widget build(BuildContext context) {
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
              const CircleAvatar(
                radius: 20,
                backgroundColor: AppColors.softSand,
                child: Icon(Icons.person_outline, size: 20, color: AppColors.textTertiary),
              ),
              const SizedBox(width: AppSpacing.sm),
              Text(
                '@$authorUsername',
                style: AppTypography.textTheme.titleSmall,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            content,
            style: AppTypography.textTheme.bodyLarge,
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            'Replies',
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
    required this.isLastTop,
  });

  final Map<String, dynamic> reply;
  final List<Map<String, dynamic>> children;
  final void Function(String replyId, String username) onReply;
  final bool isLastTop;

  @override
  Widget build(BuildContext context) {
    final user = reply['users_public'] as Map<String, dynamic>;
    final username = user['username'] as String;
    final avatarUrl = user['avatar_url'] as String?;
    final isVerified = user['is_identity_verified'] as bool? ?? false;
    final created = DateTime.tryParse(reply['created_at'] as String? ?? '') ?? DateTime.now();

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
                    _VerifiedAvatar(avatarUrl: avatarUrl, isVerified: isVerified, size: 36),
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
                      Row(
                        children: [
                          Text(
                            '@$username',
                            style: AppTypography.textTheme.titleSmall,
                          ),
                          const SizedBox(width: AppSpacing.sm),
                          Text(
                            Formatters.timeAgo(created),
                            style: AppTypography.textTheme.labelMedium,
                          ),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      _MentionText(content: reply['content'] as String),
                      const SizedBox(height: AppSpacing.xs),
                      GestureDetector(
                        onTap: () => onReply(reply['id'] as String, username),
                        child: Text(
                          'Reply',
                          style: GoogleFonts.josefinSans(
                            fontSize: 12,
                            color: AppColors.textTertiary,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
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
        )),
        if (!isLastTop)
          const Divider(height: 1, indent: 56),
      ],
    );
  }
}

class _NestedReply extends StatelessWidget {
  const _NestedReply({
    required this.reply,
    required this.onReply,
  });

  final Map<String, dynamic> reply;
  final void Function(String replyId, String username) onReply;

  @override
  Widget build(BuildContext context) {
    final user = reply['users_public'] as Map<String, dynamic>;
    final username = user['username'] as String;
    final avatarUrl = user['avatar_url'] as String?;
    final isVerified = user['is_identity_verified'] as bool? ?? false;
    final created = DateTime.tryParse(reply['created_at'] as String? ?? '') ?? DateTime.now();

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
        _VerifiedAvatar(avatarUrl: avatarUrl, isVerified: isVerified, size: 28),
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
                Row(
                  children: [
                    Text(
                      '@$username',
                      style: AppTypography.textTheme.titleSmall,
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Text(
                      Formatters.timeAgo(created),
                      style: AppTypography.textTheme.labelMedium,
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.xs),
                _MentionText(content: reply['content'] as String),
                const SizedBox(height: AppSpacing.xs),
                GestureDetector(
                  onTap: () => onReply(reply['id'] as String, username),
                  child: Text(
                    'Reply',
                    style: GoogleFonts.josefinSans(
                      fontSize: 12,
                      color: AppColors.textTertiary,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _MentionText extends StatelessWidget {
  const _MentionText({required this.content});
  final String content;

  @override
  Widget build(BuildContext context) {
    final words = content.split(' ');
    return Text.rich(
      TextSpan(
        children: words.map((word) {
          if (word.startsWith('@') && word.length > 1) {
            return TextSpan(
              text: '$word ',
              style: GoogleFonts.josefinSans(
                fontSize: 14,
                color: AppColors.fernGreen,
                fontWeight: FontWeight.w600,
              ),
            );
          }
          if (word.startsWith('~') && word.length > 1) {
            return TextSpan(
              text: '$word ',
              style: GoogleFonts.josefinSans(
                fontSize: 14,
                color: AppColors.fernGreen,
                fontWeight: FontWeight.w500,
              ),
            );
          }
          return TextSpan(
            text: '$word ',
            style: AppTypography.textTheme.bodyMedium,
          );
        }).toList(),
      ),
    );
  }
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
                      'Replying to @$replyingToUsername',
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
                              ? 'Reply to @$replyingToUsername...'
                              : 'Add a reply...',
                          hintStyle: GoogleFonts.josefinSans(
                            fontSize: 14,
                            color: AppColors.textTertiary,
                          ),
                          border: InputBorder.none,
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(vertical: 8),
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
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: isSubmitting
                            ? AppColors.borderSubtle
                            : AppColors.charcoal,
                        shape: BoxShape.circle,
                      ),
                      child: isSubmitting
                          ? const Padding(
                              padding: EdgeInsets.all(10),
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: AppColors.white,
                              ),
                            )
                          : const Icon(
                              Icons.arrow_upward_rounded,
                              color: AppColors.white,
                              size: 20,
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
            backgroundImage: (avatarUrl != null && avatarUrl.isNotEmpty)
                ? NetworkImage(avatarUrl)
                : null,
            child: (avatarUrl == null || avatarUrl.isEmpty)
                ? const Icon(Icons.person_outline, size: 16, color: AppColors.textTertiary)
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
          backgroundImage: (avatarUrl != null && avatarUrl!.isNotEmpty)
              ? NetworkImage(avatarUrl!)
              : null,
          child: (avatarUrl == null || avatarUrl!.isEmpty)
              ? Icon(Icons.person_outline, size: size * 0.5, color: AppColors.textTertiary)
              : null,
        ),
      ),
    );
  }
}