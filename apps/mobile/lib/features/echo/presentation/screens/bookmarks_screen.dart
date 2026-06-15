// bookmarks screen
// @params none
// shows echoes the current user saved from feed or detail

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../../../../app/theme/colors.dart';
import '../../../../app/theme/spacing.dart';
import '../../../../app/theme/typography.dart';
import '../../domain/entities/echo_entity.dart';
import '../services/bookmark_service.dart';
import '../widgets/echo_card.dart';

class BookmarksScreen extends StatefulWidget {
  const BookmarksScreen({super.key});

  @override
  State<BookmarksScreen> createState() => _BookmarksScreenState();
}

class _BookmarksScreenState extends State<BookmarksScreen> {
  late Future<List<EchoEntity>> _future;

  @override
  void initState() {
    super.initState();
    _future = context.read<BookmarkService>().fetchBookmarkedEchoes();
  }

  Future<void> _refresh() async {
    setState(() {
      _future = context.read<BookmarkService>().fetchBookmarkedEchoes();
    });
    await _future;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.white,
      appBar: AppBar(
        backgroundColor: AppColors.white,
        foregroundColor: AppColors.charcoal,
        elevation: 0,
        scrolledUnderElevation: 0.5,
        shadowColor: AppColors.borderSubtle,
        title: Text('Bookmarks', style: AppTypography.textTheme.titleLarge),
      ),
      body: RefreshIndicator(
        color: AppColors.fernGreen,
        onRefresh: _refresh,
        child: FutureBuilder<List<EchoEntity>>(
          future: _future,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const _BookmarkSkeleton();
            }
            final echoes = snapshot.data ?? const <EchoEntity>[];
            if (echoes.isEmpty) {
              return const _BookmarksEmpty();
            }
            return ListView.builder(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: EdgeInsets.only(
                bottom: AppSpacing.xl + MediaQuery.paddingOf(context).bottom,
              ),
              itemCount: echoes.length,
              itemBuilder: (context, index) {
                final echo = echoes[index];
                return TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0, end: 1),
                  duration: Duration(
                    milliseconds: 220 + index.clamp(0, 6) * 40,
                  ),
                  curve: Curves.easeOutCubic,
                  builder: (context, value, child) => Opacity(
                    opacity: value,
                    child: Transform.translate(
                      offset: Offset(0, 10 * (1 - value)),
                      child: child,
                    ),
                  ),
                  child: EchoCard(
                    echo: echo,
                    showReplyPreview: false,
                    showContextPreview: false,
                    onTap: () => context.push('/feed/echo/${echo.id}'),
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }
}

class _BookmarksEmpty extends StatelessWidget {
  const _BookmarksEmpty();

  @override
  Widget build(BuildContext context) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: EdgeInsets.fromLTRB(
        AppSpacing.xl,
        120,
        AppSpacing.xl,
        AppSpacing.xl + MediaQuery.paddingOf(context).bottom,
      ),
      children: [
        Icon(
          Icons.bookmark_border_rounded,
          size: 44,
          color: AppColors.fernGreen.withValues(alpha: 0.75),
        ),
        const SizedBox(height: AppSpacing.lg),
        Text(
          'No bookmarks yet',
          textAlign: TextAlign.center,
          style: AppTypography.textTheme.headlineSmall?.copyWith(
            color: AppColors.charcoal,
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          'Save echoes you want to revisit later.',
          textAlign: TextAlign.center,
          style: GoogleFonts.josefinSans(
            fontSize: 14,
            color: AppColors.textSecondary,
          ),
        ),
      ],
    );
  }
}

class _BookmarkSkeleton extends StatelessWidget {
  const _BookmarkSkeleton();

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.xl,
        AppSpacing.lg,
        AppSpacing.xl,
        AppSpacing.xl,
      ),
      itemBuilder: (context, index) => DecoratedBox(
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: AppColors.borderSubtle)),
        ),
        child: const Padding(
          padding: EdgeInsets.symmetric(vertical: AppSpacing.lg),
          child: Row(
            children: [
              CircleAvatar(radius: 16, backgroundColor: AppColors.softSand),
              SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _SkeletonLine(width: 180),
                    SizedBox(height: AppSpacing.sm),
                    _SkeletonLine(width: double.infinity),
                    SizedBox(height: AppSpacing.xs),
                    _SkeletonLine(width: 220),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
      separatorBuilder: (context, index) => const SizedBox.shrink(),
      itemCount: 4,
    );
  }
}

class _SkeletonLine extends StatelessWidget {
  const _SkeletonLine({required this.width});

  final double width;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: 12,
      decoration: BoxDecoration(
        color: AppColors.softSand,
        borderRadius: BorderRadius.circular(8),
      ),
    );
  }
}
