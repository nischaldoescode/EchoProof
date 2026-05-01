import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../app/theme/colors.dart';
import '../../../../app/theme/spacing.dart';
import '../../../../app/theme/typography.dart';
import '../../../../core/utils/logger.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen>
    with SingleTickerProviderStateMixin {
  final _ctrl = TextEditingController();
  final _focus = FocusNode();

  late final TabController _tabs;

  List<Map<String, dynamic>> _users = [];
  List<Map<String, dynamic>> _echoes = [];
  bool _isSearching = false;
  String _lastQuery = '';

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focus.requestFocus();
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _focus.dispose();
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _search(String query) async {
    final q = query.trim();
    _lastQuery = q;

    if (q.length < 2) {
      setState(() {
        _users = [];
        _echoes = [];
      });
      return;
    }

    setState(() => _isSearching = true);

    try {
      final client = Supabase.instance.client;

      final usersRes = await client
          .from('users_public')
          .select('id, username, avatar_url, trust_tier, is_public, bio')
          .ilike('username', '%$q%')
          .limit(20);

      final echoesRes = await client
          .from('echoes')
          .select(
            'id, title, content, category, status, '
            'support_count, challenge_count, created_at, '
            'users_public!inner(username, trust_tier, avatar_url, is_identity_verified)',
          )
          .or('title.ilike.%$q%,content.ilike.%$q%')
          .not('status', 'in', '("hidden","rejected")')
          .order('created_at', ascending: false)
          .limit(20);

      if (!mounted) return;

      setState(() {
        _users = List<Map<String, dynamic>>.from(usersRes as List);
        _echoes = List<Map<String, dynamic>>.from(echoesRes as List);
        _isSearching = false;
      });
    } catch (e) {
      AppLogger.error('search: failed $e');
      if (mounted) setState(() => _isSearching = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEmpty = _ctrl.text.trim().isEmpty;

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
            Tab(text: 'People (${_users.length})'),
            Tab(text: 'Echoes (${_echoes.length})'),
          ],
        ),
      ),
      body: isEmpty
          ? _EmptySearch()
          : _isSearching
              ? const Center(
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: AppColors.fernGreen,
                  ),
                )
              : TabBarView(
                  controller: _tabs,
                  children: [
                    _UserResults(users: _users),
                    _EchoResults(echoes: _echoes, query: _lastQuery),
                  ],
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
  const _UserResults({required this.users});
  final List<Map<String, dynamic>> users;

  @override
  Widget build(BuildContext context) {
    if (users.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.person_search_rounded,
              size: 48,
              color: AppColors.textTertiary,
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              'No people found',
              style: GoogleFonts.josefinSans(
                color: AppColors.textTertiary,
                fontSize: 14,
              ),
            ),
          ],
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      itemCount: users.length,
      separatorBuilder: (_, __) => const Divider(
        height: 1,
        indent: 72,
      ),
      itemBuilder: (_, i) {
        final u = users[i];
        final username = u['username'] as String? ?? '';
        final avatarUrl = u['avatar_url'] as String?;
        final trustTier = u['trust_tier'] as String? ?? 'unverified';
        final bio = u['bio'] as String?;

        return ListTile(
          onTap: () => context.push('/profile/$username'),
          leading: CircleAvatar(
            radius: 22,
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
          title: Text(
            '@$username',
            style: GoogleFonts.josefinSans(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: AppColors.charcoal,
            ),
          ),
          subtitle: (bio != null && bio.isNotEmpty)
              ? Text(
                  bio,
                  style: GoogleFonts.josefinSans(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                )
              : null,
          trailing: _TierBadge(tier: trustTier),
        );
      },
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
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.search_off_rounded,
              size: 48,
              color: AppColors.textTertiary,
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              'No echoes found',
              style: GoogleFonts.josefinSans(
                color: AppColors.textTertiary,
                fontSize: 14,
              ),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      itemCount: echoes.length,
      itemBuilder: (_, i) {
        final e = echoes[i];
        final user = e['users_public'] as Map<String, dynamic>? ?? {};
        final echoId = e['id'] as String;
        final title = e['title'] as String? ?? '';
        final content = e['content'] as String? ?? '';
        final support = (e['support_count'] as num?)?.toInt() ?? 0;
        final challenge = (e['challenge_count'] as num?)?.toInt() ?? 0;
        final status = e['status'] as String? ?? 'active';
        final username = user['username'] as String? ?? 'unknown';
        final avatarUrl = user['avatar_url'] as String?;
        final isVerified = user['is_identity_verified'] as bool? ?? false;
        final tierStr = user['trust_tier'] as String? ?? 'unverified';

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
                // header — same layout as EchoCard header
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
                        isVerified: isVerified,
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '@$username',
                              style: AppTypography.textTheme.titleSmall,
                              overflow: TextOverflow.ellipsis,
                            ),
                            Text(
                              e['category'] as String? ?? '',
                              style: AppTypography.textTheme.labelMedium,
                            ),
                          ],
                        ),
                      ),
                      _TierBadge(tier: tierStr),
                    ],
                  ),
                ),

                // highlighted content
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
                    ],
                  ),
                ),

                // interaction counts — same as echo card bottom
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
                      const Spacer(),
                      _StatusChip(status: status),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
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

class _EmptySearch extends StatelessWidget {
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
            'Search for people or echoes',
            style: GoogleFonts.josefinSans(
              fontSize: 14,
              color: AppColors.textTertiary,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Type at least 2 characters',
            style: GoogleFonts.josefinSans(
              fontSize: 12,
              color: AppColors.borderMedium,
            ),
          ),
        ],
      ),
    );
  }
}
