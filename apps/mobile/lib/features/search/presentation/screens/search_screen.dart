import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../app/theme/colors.dart';
import '../../../../app/theme/spacing.dart';
import '../../../../app/theme/typography.dart';
import '../../../../core/utils/logger.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key, this.initialQuery});

  final String? initialQuery;

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen>
    with SingleTickerProviderStateMixin {
  final _ctrl = TextEditingController();
  final _focus = FocusNode();
  Timer? _debounce;

  late final TabController _tabs;

  List<Map<String, dynamic>> _users = [];
  List<Map<String, dynamic>> _echoes = [];
  bool _isSearching = false;
  bool _hasSearched = false;
  String _lastQuery = '';
  String? _errorMessage;
  int _searchGeneration = 0;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 3, vsync: this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focus.requestFocus();
      final initial = widget.initialQuery?.trim();
      if (initial != null && initial.isNotEmpty) {
        _ctrl.text = initial;
        _ctrl.selection = TextSelection.collapsed(offset: initial.length);
        _search(initial);
      }
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _ctrl.dispose();
    _focus.dispose();
    _tabs.dispose();
    super.dispose();
  }

  void _search(String query) {
    final q = query.trim();
    _debounce?.cancel();
    _searchGeneration++;

    if (q.length < 2) {
      setState(() {
        _lastQuery = q;
        _users = [];
        _echoes = [];
        _isSearching = false;
        _hasSearched = false;
        _errorMessage = null;
      });
      return;
    }

    setState(() {
      _lastQuery = q;
      _errorMessage = null;
    });

    _debounce = Timer(
      const Duration(milliseconds: 260),
      () => _runSearch(q),
    );
  }

  Future<void> _runSearch(String query) async {
    final q = query.trim();
    final generation = ++_searchGeneration;
    final pattern = _ilikePattern(q);

    setState(() => _isSearching = true);

    try {
      final client = Supabase.instance.client;

      final usersRes = await client
          .from('users_public')
          .select(
              'id, username, display_name, avatar_url, trust_tier, is_public, bio, is_pro')
          .or('username.ilike.$pattern,display_name.ilike.$pattern,bio.ilike.$pattern')
          .eq('is_public', true)
          .eq('is_suspended', false)
          .limit(20);

      final echoesRes = await client
          .from('echoes')
          .select(
            'id, user_id, title, content, category, status, media_urls, '
            'support_count, challenge_count, reply_count, created_at, '
            'users_public!inner(username, display_name, trust_tier, avatar_url, is_pro, is_public)',
          )
          .or('title.ilike.$pattern,content.ilike.$pattern')
          .not('status', 'in', '("hidden","rejected")')
          .eq('users_public.is_public', true)
          .order('created_at', ascending: false)
          .limit(20);

      if (!mounted || generation != _searchGeneration) return;

      setState(() {
        _users = List<Map<String, dynamic>>.from(usersRes as List);
        _echoes = List<Map<String, dynamic>>.from(echoesRes as List);
        _isSearching = false;
        _hasSearched = true;
        _errorMessage = null;
      });
    } catch (e) {
      AppLogger.error('search: failed $e');
      if (mounted && generation == _searchGeneration) {
        setState(() {
          _isSearching = false;
          _hasSearched = true;
          _errorMessage = 'Search failed. Please try again.';
        });
      }
    }
  }

  String _ilikePattern(String query) {
    final cleaned = query
        .replaceAll(RegExp(r'[%_,()]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    return '%$cleaned%';
  }

  void _applySuggestion(String value) {
    _ctrl.text = value;
    _ctrl.selection = TextSelection.collapsed(offset: value.length);
    _search(value);
  }

  @override
  Widget build(BuildContext context) {
    final isEmpty = _ctrl.text.trim().isEmpty;
    final isTooShort = !isEmpty && _ctrl.text.trim().length < 2;

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => context.pop(),
          color: AppColors.charcoal,
        ),
        title: _SearchField(
          ctrl: _ctrl,
          focus: _focus,
          onChanged: _search,
        ),
        bottom: TabBar(
          controller: _tabs,
          labelColor: AppColors.charcoal,
          unselectedLabelColor: AppColors.textTertiary,
          indicatorColor: AppColors.charcoal,
          indicatorWeight: 1.5,
          labelStyle: GoogleFonts.josefinSans(
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
          unselectedLabelStyle: GoogleFonts.josefinSans(fontSize: 13),
          tabs: [
            const Tab(text: 'Top'),
            Tab(text: 'People ${_users.length}'),
            Tab(text: 'Echoes ${_echoes.length}'),
          ],
        ),
      ),
      body: AnimatedSwitcher(
        duration: const Duration(milliseconds: 180),
        child: isEmpty || isTooShort
            ? _EmptySearch(
                key: const ValueKey('empty-search'),
                isTooShort: isTooShort,
                onSuggestion: _applySuggestion,
              )
            : Stack(
                key: const ValueKey('search-results'),
                children: [
                  if (_errorMessage != null)
                    _SearchError(message: _errorMessage!)
                  else
                    TabBarView(
                      controller: _tabs,
                      children: [
                        _TopResults(
                          users: _users,
                          echoes: _echoes,
                          query: _lastQuery,
                          hasSearched: _hasSearched,
                          onPeopleTap: () => _tabs.animateTo(1),
                          onEchoesTap: () => _tabs.animateTo(2),
                        ),
                        _UserResults(users: _users, query: _lastQuery),
                        _EchoResults(echoes: _echoes, query: _lastQuery),
                      ],
                    ),
                  if (_isSearching)
                    const Positioned(
                      left: 0,
                      right: 0,
                      top: 0,
                      child: LinearProgressIndicator(
                        minHeight: 2,
                        color: AppColors.fernGreen,
                        backgroundColor: Colors.transparent,
                      ),
                    ),
                ],
              ),
      ),
    );
  }
}

class _SearchField extends StatefulWidget {
  const _SearchField({
    required this.ctrl,
    required this.focus,
    required this.onChanged,
  });
  final TextEditingController ctrl;
  final FocusNode focus;
  final void Function(String) onChanged;

  @override
  State<_SearchField> createState() => _SearchFieldState();
}

class _SearchFieldState extends State<_SearchField> {
  @override
  void initState() {
    super.initState();
    widget.ctrl.addListener(() => setState(() {}));
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 40,
      decoration: BoxDecoration(
        color: const Color(0xFFF0F4F2),
        borderRadius: BorderRadius.circular(12),
      ),
      child: TextField(
        controller: widget.ctrl,
        focusNode: widget.focus,
        onChanged: widget.onChanged,
        style: GoogleFonts.josefinSans(
          fontSize: 14,
          color: AppColors.charcoal,
        ),
        decoration: InputDecoration(
          hintText: 'Search people or echoes...',
          hintStyle: GoogleFonts.josefinSans(
            fontSize: 14,
            color: AppColors.textTertiary,
          ),
          prefixIcon: const Icon(
            Icons.search_rounded,
            size: 18,
            color: AppColors.textTertiary,
          ),
          suffixIcon: widget.ctrl.text.isNotEmpty
              ? IconButton(
                  icon: const Icon(
                    Icons.close_rounded,
                    size: 16,
                    color: AppColors.textTertiary,
                  ),
                  onPressed: () {
                    widget.ctrl.clear();
                    widget.onChanged('');
                  },
                )
              : null,
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(vertical: 10),
        ),
      ),
    );
  }
}

class _UserResults extends StatelessWidget {
  const _UserResults({
    required this.users,
    required this.query,
  });
  final List<Map<String, dynamic>> users;
  final String query;

  @override
  Widget build(BuildContext context) {
    if (users.isEmpty) {
      return _NoResults(
        icon: Icons.person_search_rounded,
        title: 'No people found',
        message: 'Try a username, display name, or profile bio.',
        query: query,
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.only(top: AppSpacing.sm, bottom: 96),
      itemCount: users.length,
      separatorBuilder: (_, __) => const Divider(
        height: 1,
        indent: 72,
      ),
      itemBuilder: (_, i) {
        return _AnimatedResult(
          index: i,
          child: _UserResultTile(
            user: users[i],
            query: query,
          ),
        );
      },
    );
  }
}

class _TopResults extends StatelessWidget {
  const _TopResults({
    required this.users,
    required this.echoes,
    required this.query,
    required this.hasSearched,
    required this.onPeopleTap,
    required this.onEchoesTap,
  });

  final List<Map<String, dynamic>> users;
  final List<Map<String, dynamic>> echoes;
  final String query;
  final bool hasSearched;
  final VoidCallback onPeopleTap;
  final VoidCallback onEchoesTap;

  @override
  Widget build(BuildContext context) {
    if (!hasSearched) {
      return const Center(
        child: CircularProgressIndicator(
          strokeWidth: 2,
          color: AppColors.fernGreen,
        ),
      );
    }

    if (users.isEmpty && echoes.isEmpty) {
      return _NoResults(
        icon: Icons.search_off_rounded,
        title: 'No results found',
        message: 'Try fewer words, a username, or a phrase from the echo.',
        query: query,
      );
    }

    var index = 0;
    return ListView(
      padding: const EdgeInsets.only(top: AppSpacing.sm, bottom: 96),
      children: [
        if (users.isNotEmpty) ...[
          _SearchSectionHeader(
            title: 'People',
            actionLabel: users.length > 3 ? 'View all' : null,
            onAction: users.length > 3 ? onPeopleTap : null,
          ),
          ...users.take(3).map(
                (user) => _AnimatedResult(
                  index: index++,
                  child: _UserResultTile(user: user, query: query),
                ),
              ),
        ],
        if (echoes.isNotEmpty) ...[
          _SearchSectionHeader(
            title: 'Echoes',
            actionLabel: echoes.length > 5 ? 'View all' : null,
            onAction: echoes.length > 5 ? onEchoesTap : null,
          ),
          ...echoes.take(5).map(
                (echo) => _AnimatedResult(
                  index: index++,
                  child: _EchoResultCard(echo: echo, query: query),
                ),
              ),
        ],
      ],
    );
  }
}

class _UserResultTile extends StatelessWidget {
  const _UserResultTile({
    required this.user,
    required this.query,
  });

  final Map<String, dynamic> user;
  final String query;

  @override
  Widget build(BuildContext context) {
    final username = user['username'] as String? ?? '';
    final displayName = user['display_name'] as String?;
    final avatarUrl = user['avatar_url'] as String?;
    final trustTier = user['trust_tier'] as String? ?? 'unverified';
    final bio = user['bio'] as String?;
    final title = displayName?.trim().isNotEmpty == true
        ? displayName!.trim()
        : '@$username';

    return Material(
      color: Colors.white,
      child: InkWell(
        onTap: username.isEmpty
            ? null
            : () => context.push('/profile/${Uri.encodeComponent(username)}'),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.lg,
            vertical: AppSpacing.md,
          ),
          child: Row(
            children: [
              CircleAvatar(
                radius: 23,
                backgroundColor: AppColors.softSand,
                backgroundImage: (avatarUrl != null && avatarUrl.isNotEmpty)
                    ? NetworkImage(avatarUrl)
                    : null,
                child: (avatarUrl == null || avatarUrl.isEmpty)
                    ? const Icon(
                        Icons.person_outline,
                        size: 20,
                        color: AppColors.textTertiary,
                      )
                    : null,
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _HighlightedText(
                      text: title,
                      query: query,
                      baseStyle: GoogleFonts.josefinSans(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: AppColors.charcoal,
                      ),
                      maxLines: 1,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '@$username',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.josefinSans(
                        fontSize: 12,
                        color: AppColors.textTertiary,
                      ),
                    ),
                    if (bio != null && bio.trim().isNotEmpty) ...[
                      const SizedBox(height: 3),
                      _HighlightedText(
                        text: bio.trim(),
                        query: query,
                        baseStyle: GoogleFonts.josefinSans(
                          fontSize: 12,
                          color: AppColors.textSecondary,
                          height: 1.25,
                        ),
                        maxLines: 2,
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              _TierBadge(tier: trustTier),
            ],
          ),
        ),
      ),
    );
  }
}

class _EchoResults extends StatelessWidget {
  const _EchoResults({
    required this.echoes,
    required this.query,
  });
  final List<Map<String, dynamic>> echoes;
  final String query;

  @override
  Widget build(BuildContext context) {
    if (echoes.isEmpty) {
      return _NoResults(
        icon: Icons.search_off_rounded,
        title: 'No echoes found',
        message: 'Try words from the title or the echo body.',
        query: query,
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.only(top: AppSpacing.sm, bottom: 96),
      itemCount: echoes.length,
      itemBuilder: (_, i) {
        return _AnimatedResult(
          index: i,
          child: _EchoResultCard(
            echo: echoes[i],
            query: query,
          ),
        );
      },
    );
  }
}

class _EchoResultCard extends StatelessWidget {
  const _EchoResultCard({
    required this.echo,
    required this.query,
  });

  final Map<String, dynamic> echo;
  final String query;

  @override
  Widget build(BuildContext context) {
    final user = echo['users_public'] as Map<String, dynamic>? ?? {};
    final echoId = echo['id'] as String;
    final title = echo['title'] as String? ?? '';
    final content = echo['content'] as String? ?? '';
    final support = (echo['support_count'] as num?)?.toInt() ?? 0;
    final challenge = (echo['challenge_count'] as num?)?.toInt() ?? 0;
    final replies = (echo['reply_count'] as num?)?.toInt() ?? 0;
    final status = echo['status'] as String? ?? 'active';
    final username = user['username'] as String? ?? 'unknown';
    final displayName =
        (user['display_name'] as String?)?.trim().isNotEmpty == true
            ? user['display_name'] as String
            : username;
    final avatarUrl = user['avatar_url'] as String?;
    final tierStr = user['trust_tier'] as String? ?? 'unverified';
    final mediaUrls = (echo['media_urls'] as List?)?.cast<String>() ?? const [];

    return GestureDetector(
      onTap: () => context.push('/feed/echo/$echoId'),
      child: Container(
        margin: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.xs,
        ),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(AppSpacing.echoCardRadius),
          border: Border.all(
            color: _borderColor(status),
            width: 1.2,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg,
                AppSpacing.md,
                AppSpacing.lg,
                AppSpacing.xs,
              ),
              child: Row(
                children: [
                  _SmallAvatar(
                    avatarUrl: avatarUrl,
                    isVerified: false,
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          displayName,
                          style: AppTypography.textTheme.titleSmall,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          '@$username · ${echo['category'] as String? ?? ''}',
                          style: AppTypography.textTheme.labelMedium,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  _TierBadge(tier: tierStr),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.lg,
                vertical: AppSpacing.sm,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (title.isNotEmpty) ...[
                    _HighlightedText(
                      text: title,
                      query: query,
                      baseStyle: AppTypography.textTheme.titleMedium!,
                      maxLines: 2,
                    ),
                    const SizedBox(height: AppSpacing.xs),
                  ],
                  _HighlightedText(
                    text: content,
                    query: query,
                    baseStyle: AppTypography.textTheme.bodyMedium!,
                    maxLines: 3,
                  ),
                  if (mediaUrls.isNotEmpty) ...[
                    const SizedBox(height: AppSpacing.sm),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.image_outlined,
                            size: 13, color: AppColors.textTertiary),
                        const SizedBox(width: 4),
                        Text(
                          '${mediaUrls.length} media',
                          style: AppTypography.textTheme.labelMedium,
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg,
                0,
                AppSpacing.lg,
                AppSpacing.md,
              ),
              child: Row(
                children: [
                  _SigPill(
                    label: '$support support',
                    color: AppColors.fernGreen,
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  _SigPill(
                    label: '$challenge challenge',
                    color: AppColors.sunsetCoral,
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  _SigPill(
                    label: '$replies replies',
                    color: AppColors.textTertiary,
                  ),
                  const Spacer(),
                  _StatusChip(status: status),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Color _borderColor(String status) {
    return switch (status) {
      'verified' => AppColors.fernGreen.withValues(alpha: 0.35),
      'disputed' => AppColors.sunsetCoral.withValues(alpha: 0.35),
      'controversial' => AppColors.statusControversial.withValues(alpha: 0.35),
      'under_review' => AppColors.statusUnderReview.withValues(alpha: 0.25),
      _ => AppColors.borderSubtle,
    };
  }
}

// highlights query occurrences within text
class _HighlightedText extends StatelessWidget {
  const _HighlightedText({
    required this.text,
    required this.query,
    required this.baseStyle,
    this.maxLines = 3,
  });

  final String text;
  final String query;
  final TextStyle baseStyle;
  final int maxLines;

  @override
  Widget build(BuildContext context) {
    if (query.isEmpty) {
      return Text(
        text,
        style: baseStyle,
        maxLines: maxLines,
        overflow: TextOverflow.ellipsis,
      );
    }

    final lowerText = text.toLowerCase();
    final lowerQuery = query.toLowerCase();
    final spans = <TextSpan>[];
    int start = 0;

    while (true) {
      final index = lowerText.indexOf(lowerQuery, start);
      if (index == -1) {
        if (start < text.length) {
          spans.add(TextSpan(text: text.substring(start)));
        }
        break;
      }
      if (index > start) {
        spans.add(TextSpan(text: text.substring(start, index)));
      }
      spans.add(TextSpan(
        text: text.substring(index, index + query.length),
        style: baseStyle.copyWith(
          backgroundColor: AppColors.fernGreen.withValues(alpha: 0.18),
          color: AppColors.fernGreenDark,
          fontWeight: FontWeight.w700,
        ),
      ));
      start = index + query.length;
    }

    return Text.rich(
      TextSpan(children: spans, style: baseStyle),
      maxLines: maxLines,
      overflow: TextOverflow.ellipsis,
    );
  }
}

class _SmallAvatar extends StatelessWidget {
  const _SmallAvatar({
    required this.avatarUrl,
    required this.isVerified,
  });
  final String? avatarUrl;
  final bool isVerified;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 36,
      height: 36,
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
          backgroundColor: AppColors.softSand,
          backgroundImage: (avatarUrl != null && avatarUrl!.isNotEmpty)
              ? NetworkImage(avatarUrl!)
              : null,
          child: (avatarUrl == null || avatarUrl!.isEmpty)
              ? const Icon(
                  Icons.person_outline,
                  size: 16,
                  color: AppColors.textTertiary,
                )
              : null,
        ),
      ),
    );
  }
}

class _SigPill extends StatelessWidget {
  const _SigPill({required this.label, required this.color});
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: GoogleFonts.josefinSans(
          fontSize: 10,
          color: color,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status});
  final String status;

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (status) {
      'verified' => ('Verified', AppColors.fernGreen),
      'disputed' => ('Disputed', AppColors.sunsetCoral),
      'controversial' => ('Controversial', AppColors.statusControversial),
      'under_review' => ('Under Review', AppColors.statusUnderReview),
      'pending_verification' => ('Pending', AppColors.textTertiary),
      _ => ('Active', AppColors.textTertiary),
    };

    if (status == 'active' || status == 'pending_verification') {
      return const SizedBox.shrink();
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Text(
        label,
        style: GoogleFonts.josefinSans(
          fontSize: 10,
          color: color,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _TierBadge extends StatelessWidget {
  const _TierBadge({required this.tier});
  final String tier;

  @override
  Widget build(BuildContext context) {
    final isHighTrust = tier == 'elite' || tier == 'high';
    final color =
        isHighTrust ? AppColors.fernGreenDark : AppColors.textTertiary;
    final bg = isHighTrust ? AppColors.fernGreenLight : AppColors.softSand;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        tier,
        style: GoogleFonts.josefinSans(
          fontSize: 10,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }
}

class _AnimatedResult extends StatelessWidget {
  const _AnimatedResult({
    required this.index,
    required this.child,
  });

  final int index;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final stagger = index < 0 ? 0 : (index > 8 ? 8 : index);
    final duration = Duration(milliseconds: 220 + (stagger * 28));

    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: duration,
      curve: Curves.easeOutCubic,
      builder: (context, value, child) {
        return Opacity(
          opacity: value,
          child: Transform.translate(
            offset: Offset(0, (1 - value) * 10),
            child: child,
          ),
        );
      },
      child: child,
    );
  }
}

class _SearchSectionHeader extends StatelessWidget {
  const _SearchSectionHeader({
    required this.title,
    this.actionLabel,
    this.onAction,
  });

  final String title;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.lg,
        AppSpacing.lg,
        AppSpacing.xs,
      ),
      child: Row(
        children: [
          Text(
            title,
            style: GoogleFonts.josefinSans(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: AppColors.charcoal,
            ),
          ),
          const Spacer(),
          if (actionLabel != null && onAction != null)
            TextButton(
              onPressed: onAction,
              child: Text(
                actionLabel!,
                style: GoogleFonts.josefinSans(
                  fontSize: 12,
                  color: AppColors.fernGreen,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _NoResults extends StatelessWidget {
  const _NoResults({
    required this.icon,
    required this.title,
    required this.message,
    required this.query,
  });

  final IconData icon;
  final String title;
  final String message;
  final String query;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: 1),
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOutCubic,
        builder: (context, value, child) {
          return Opacity(
            opacity: value,
            child: Transform.scale(
              scale: 0.98 + (value * 0.02),
              child: child,
            ),
          );
        },
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xxl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 48, color: AppColors.textTertiary),
              const SizedBox(height: AppSpacing.md),
              Text(
                title,
                textAlign: TextAlign.center,
                style: GoogleFonts.josefinSans(
                  color: AppColors.charcoal,
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                message,
                textAlign: TextAlign.center,
                style: GoogleFonts.josefinSans(
                  color: AppColors.textTertiary,
                  fontSize: 12,
                  height: 1.35,
                ),
              ),
              if (query.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.sm),
                Text(
                  '"$query"',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.josefinSans(
                    color: AppColors.textSecondary,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _SearchError extends StatelessWidget {
  const _SearchError({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    return _NoResults(
      icon: Icons.error_outline_rounded,
      title: message,
      message: 'The search request could not complete.',
      query: '',
    );
  }
}

class _EmptySearch extends StatelessWidget {
  const _EmptySearch({
    super.key,
    required this.isTooShort,
    required this.onSuggestion,
  });

  final bool isTooShort;
  final ValueChanged<String> onSuggestion;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.search_rounded,
            size: 48,
            color: AppColors.textTertiary,
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            isTooShort ? 'Keep typing' : 'Search Echoproof',
            style: GoogleFonts.josefinSans(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: AppColors.charcoal,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            isTooShort
                ? 'Type at least 2 characters'
                : 'Find people, echo titles, and proof-backed claims.',
            textAlign: TextAlign.center,
            style: GoogleFonts.josefinSans(
              fontSize: 12,
              color: AppColors.textTertiary,
              height: 1.35,
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              _SuggestionChip(label: 'tech', onTap: onSuggestion),
              _SuggestionChip(label: 'news', onTap: onSuggestion),
              _SuggestionChip(label: 'proof', onTap: onSuggestion),
            ],
          ),
        ],
      ),
    );
  }
}

class _SuggestionChip extends StatelessWidget {
  const _SuggestionChip({
    required this.label,
    required this.onTap,
  });

  final String label;
  final ValueChanged<String> onTap;

  @override
  Widget build(BuildContext context) {
    return ActionChip(
      label: Text(
        label,
        style: GoogleFonts.josefinSans(
          fontSize: 12,
          color: AppColors.charcoal,
          fontWeight: FontWeight.w600,
        ),
      ),
      avatar: const Icon(Icons.north_west_rounded, size: 14),
      backgroundColor: AppColors.softSand,
      side: const BorderSide(color: AppColors.borderSubtle),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppSpacing.radiusFull),
      ),
      onPressed: () => onTap(label),
    );
  }
}
