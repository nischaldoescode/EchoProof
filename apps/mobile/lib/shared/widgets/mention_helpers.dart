// mention helpers shared by echo composers
// @params none

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_mentions/flutter_mentions.dart';
import '../../app/theme/colors.dart';
import '../../app/theme/spacing.dart';
import '../../app/theme/typography.dart';
import 'avatar_image_provider.dart';

const int mentionMinQueryLength = 2;
const int _mentionSuggestionLimit = 8;
const double _minUsableSuggestionHeight = 72;
const double _suggestionPanelMaxWidth = 420;
const double _suggestionPanelHorizontalInset = 24;
const double _suggestionRowHeight = 64;

/// returns filtered mention rows with presentation metadata for the compact panel.
/// the inserted mention still uses the username stored in display, while the
/// optional name field lets the row show a twitter-like name and handle pair.
List<Map<String, dynamic>> visibleMentionUsers(
  String query,
  List<Map<String, dynamic>> users,
) {
  final clean = query.trim().replaceFirst('@', '').toLowerCase();
  if (clean.length < mentionMinQueryLength) return const [];

  final prefixMatches = <Map<String, dynamic>>[];
  final containsMatches = <Map<String, dynamic>>[];
  for (final user in users) {
    final username = _stringValue(user['display']).toLowerCase();
    final name = _stringValue(user['name']).toLowerCase();
    final matchesPrefix = username.startsWith(clean) || name.startsWith(clean);
    final matchesInside = username.contains(clean) || name.contains(clean);
    if (matchesPrefix) {
      prefixMatches.add(user);
    } else if (matchesInside) {
      containsMatches.add(user);
    }
  }

  final ordered = [
    ...prefixMatches,
    ...containsMatches,
  ].take(_mentionSuggestionLimit).toList(growable: false);
  return [
    for (var i = 0; i < ordered.length; i++)
      {
        ...ordered[i],
        '_suggestion_index': i,
        '_suggestion_count': ordered.length,
      },
  ];
}

/// chooses the side where the mention panel can open without clipping.
///
/// create echo can stay fully adaptive because it is usually in the page body.
/// reply inputs are docked at the bottom, so they pass forceTop to keep the
/// panel above the field even when a small amount of bottom space exists.
SuggestionPosition adaptiveMentionSuggestionPosition(
  BuildContext context, {
  required double listHeight,
  bool preferTopWhenCrowded = false,
  bool forceTop = false,
}) {
  final metrics = _mentionAnchorMetrics(context);
  if (metrics == null) {
    return forceTop || preferTopWhenCrowded
        ? SuggestionPosition.Top
        : SuggestionPosition.Bottom;
  }
  if (forceTop && metrics.spaceAbove >= _minUsableSuggestionHeight) {
    return SuggestionPosition.Top;
  }
  final tightEnoughForTop =
      preferTopWhenCrowded &&
      metrics.spaceAbove >= math.min(listHeight, _minUsableSuggestionHeight);
  if (tightEnoughForTop && metrics.spaceBelow < listHeight) {
    return SuggestionPosition.Top;
  }
  if (metrics.spaceBelow >= listHeight) return SuggestionPosition.Bottom;
  if (metrics.spaceAbove > metrics.spaceBelow) return SuggestionPosition.Top;
  return SuggestionPosition.Bottom;
}

double adaptiveMentionSuggestionHeight(
  BuildContext context, {
  required SuggestionPosition position,
  required double maxHeight,
}) {
  final metrics = _mentionAnchorMetrics(context);
  if (metrics == null) return maxHeight;
  final available = position == SuggestionPosition.Top
      ? metrics.spaceAbove
      : metrics.spaceBelow;
  final paddedAvailable = math.max(0.0, available - AppSpacing.xs);
  if (paddedAvailable <= 0) return _minUsableSuggestionHeight;
  return paddedAvailable
      .clamp(_minUsableSuggestionHeight, maxHeight)
      .toDouble();
}

BoxDecoration mentionSuggestionDecoration(SuggestionPosition _) {
  return const BoxDecoration(color: Colors.transparent);
}

void hideMentionSuggestions(GlobalKey<FlutterMentionsState> mentionKey) {
  mentionKey.currentState?.showSuggestions.value = false;
}

class CompactMentionSuggestions extends StatefulWidget {
  const CompactMentionSuggestions({
    super.key,
    required this.visible,
    required this.position,
    required this.suggestionHeight,
    required this.suggestions,
    required this.mentionKey,
    required this.child,
    this.onSelected,
  });

  final bool visible;
  final SuggestionPosition position;
  final double suggestionHeight;
  final List<Map<String, dynamic>> suggestions;
  final GlobalKey<FlutterMentionsState> mentionKey;
  final ValueChanged<Map<String, dynamic>>? onSelected;
  final Widget child;

  @override
  State<CompactMentionSuggestions> createState() =>
      _CompactMentionSuggestionsState();
}

class _CompactMentionSuggestionsState extends State<CompactMentionSuggestions> {
  final _anchorKey = GlobalKey();
  double? _anchorWidth;
  bool _measureScheduled = false;

  void _scheduleAnchorMeasure() {
    if (_measureScheduled) return;
    _measureScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _measureScheduled = false;
      if (!mounted) return;
      final renderObject = _anchorKey.currentContext?.findRenderObject();
      if (renderObject is! RenderBox || !renderObject.hasSize) return;
      final width = renderObject.size.width;
      if ((_anchorWidth ?? -1) == width) return;
      setState(() => _anchorWidth = width);
    });
  }

  @override
  Widget build(BuildContext context) {
    _scheduleAnchorMeasure();
    return LayoutBuilder(
      builder: (context, constraints) {
        final showPanel = widget.visible && widget.suggestions.isNotEmpty;
        final direction = Directionality.of(context);
        final isRtl = direction == TextDirection.rtl;
        final opensBelow = widget.position == SuggestionPosition.Bottom;
        final childAnchor = opensBelow
            ? (isRtl ? Alignment.bottomRight : Alignment.bottomLeft)
            : (isRtl ? Alignment.topRight : Alignment.topLeft);
        final portalAnchor = opensBelow
            ? (isRtl ? Alignment.topRight : Alignment.topLeft)
            : (isRtl ? Alignment.bottomRight : Alignment.bottomLeft);
        final panelWidth = _mentionSuggestionPanelWidth(
          context,
          constraints: constraints,
          anchorWidth: _anchorWidth,
        );

        return PortalEntry(
          visible: showPanel,
          childAnchor: childAnchor,
          portalAnchor: portalAnchor,
          portal: _MentionSuggestionPanel(
            position: widget.position,
            width: panelWidth,
            height: widget.suggestionHeight,
            suggestions: widget.suggestions,
            onSelected: (data) {
              widget.mentionKey.currentState?.addMention(data);
              hideMentionSuggestions(widget.mentionKey);
              widget.onSelected?.call(data);
            },
          ),
          child: KeyedSubtree(key: _anchorKey, child: widget.child),
        );
      },
    );
  }
}

class _MentionSuggestionPanel extends StatelessWidget {
  const _MentionSuggestionPanel({
    required this.position,
    required this.width,
    required this.height,
    required this.suggestions,
    required this.onSelected,
  });

  final SuggestionPosition position;
  final double width;
  final double height;
  final List<Map<String, dynamic>> suggestions;
  final ValueChanged<Map<String, dynamic>> onSelected;

  @override
  Widget build(BuildContext context) {
    final opensAbove = position == SuggestionPosition.Top;
    final maxHeight = math.min(
      height,
      suggestions.length * _suggestionRowHeight,
    );

    // the panel is deliberately narrower than wide composers, matching social
    // mention pickers that stay close to the active text instead of becoming a
    // full-width sheet.
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: 1),
      duration: const Duration(milliseconds: 170),
      curve: Curves.easeOutCubic,
      builder: (context, value, child) {
        return Opacity(
          opacity: value,
          child: Transform.translate(
            offset: Offset(0, (opensAbove ? 8 : -8) * (1 - value)),
            child: child,
          ),
        );
      },
      child: Padding(
        padding: EdgeInsets.only(
          top: opensAbove ? 0 : AppSpacing.xs,
          bottom: opensAbove ? AppSpacing.xs : 0,
        ),
        child: Material(
          key: const ValueKey('mention_suggestion_panel'),
          color: Colors.transparent,
          child: SizedBox(
            width: width,
            height: maxHeight,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: AppColors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppColors.borderSubtle),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.12),
                    blurRadius: 22,
                    offset: Offset(0, opensAbove ? -8 : 8),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(13),
                child: ListView.builder(
                  padding: EdgeInsets.zero,
                  itemExtent: _suggestionRowHeight,
                  itemCount: suggestions.length,
                  itemBuilder: (context, index) {
                    final data = suggestions[index];
                    return InkWell(
                      onTap: () => onSelected(data),
                      child: MentionSuggestionTile(data: data),
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

_MentionAnchorMetrics? _mentionAnchorMetrics(BuildContext context) {
  final renderObject = context.findRenderObject();
  if (renderObject is! RenderBox || !renderObject.hasSize) return null;

  final media = MediaQuery.maybeOf(context);
  if (media == null) return null;

  final offset = renderObject.localToGlobal(Offset.zero);
  final keyboardTop = media.size.height - media.viewInsets.bottom;
  final usableBottom = keyboardTop - AppSpacing.sm;
  final usableTop = media.padding.top + AppSpacing.sm;

  return _MentionAnchorMetrics(
    spaceAbove: (offset.dy - usableTop).clamp(0.0, media.size.height),
    spaceBelow: (usableBottom - offset.dy - renderObject.size.height).clamp(
      0.0,
      media.size.height,
    ),
  );
}

class _MentionAnchorMetrics {
  const _MentionAnchorMetrics({
    required this.spaceAbove,
    required this.spaceBelow,
  });

  final double spaceAbove;
  final double spaceBelow;
}

class MentionSuggestionTile extends StatelessWidget {
  const MentionSuggestionTile({super.key, required this.data});

  final Map<String, dynamic> data;

  @override
  Widget build(BuildContext context) {
    final avatarUrl = data['avatar_url'] as String?;
    final username = _stringValue(data['display']).isEmpty
        ? 'unknown'
        : _stringValue(data['display']);
    final name = _stringValue(data['name']).isEmpty
        ? username
        : _stringValue(data['name']);
    final trustTier = _stringValue(data['trust_tier']);
    final showVerifiedMark = trustTier.isNotEmpty && trustTier != 'unverified';
    final index = data['_suggestion_index'] as int? ?? 0;
    final count = data['_suggestion_count'] as int? ?? 1;
    final isLast = index >= count - 1;
    final avatarProvider = avatarImageProvider(avatarUrl);

    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 140),
      curve: Curves.easeOutCubic,
      builder: (context, value, child) {
        return Opacity(
          opacity: value,
          child: Transform.translate(
            offset: Offset(0, (1 - value) * 6),
            child: child,
          ),
        );
      },
      child: SizedBox(
        height: _suggestionRowHeight,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: AppColors.white,
            border: Border(
              bottom: isLast
                  ? BorderSide.none
                  : const BorderSide(color: AppColors.borderSubtle),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 20,
                  backgroundColor: AppColors.softSand,
                  backgroundImage: avatarProvider,
                  child: avatarProvider == null
                      ? const Icon(
                          Icons.person_outline,
                          size: 18,
                          color: AppColors.textTertiary,
                        )
                      : null,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Flexible(
                            child: Text(
                              name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppTypography.textTheme.labelLarge
                                  ?.copyWith(
                                    color: AppColors.charcoal,
                                    fontWeight: FontWeight.w800,
                                  ),
                            ),
                          ),
                          if (showVerifiedMark) ...[
                            const SizedBox(width: 4),
                            const Icon(
                              Icons.verified_rounded,
                              size: 16,
                              color: AppColors.fernGreen,
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '@$username',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTypography.textTheme.bodyMedium?.copyWith(
                          color: AppColors.textTertiary,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

double _mentionSuggestionPanelWidth(
  BuildContext context, {
  required BoxConstraints constraints,
  double? anchorWidth,
}) {
  final media = MediaQuery.maybeOf(context);
  final width = media?.size.width ?? _suggestionPanelMaxWidth;
  final safePadding = (media?.padding.left ?? 0) + (media?.padding.right ?? 0);
  final available = math.max(
    0.0,
    width - safePadding - _suggestionPanelHorizontalInset,
  );
  final measuredAnchorWidth = anchorWidth != null && anchorWidth > 0
      ? anchorWidth
      : constraints.hasBoundedWidth
      ? constraints.maxWidth
      : _suggestionPanelMaxWidth;
  return math.min(
    _suggestionPanelMaxWidth,
    math.min(available, measuredAnchorWidth),
  );
}

String _stringValue(Object? value) {
  return value is String ? value.trim() : '';
}
