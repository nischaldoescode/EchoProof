import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../../app/theme/colors.dart';
import '../../../../app/theme/spacing.dart';
import '../../../../app/theme/typography.dart';
import '../../../../core/localization/app_copy.dart';
import '../../domain/entities/echo_status.dart';
import '../../domain/entities/echo_entity.dart';
import '../../domain/entities/feed_filter.dart';

Future<FeedFilter?> showFeedFilterSheet(
  BuildContext context,
  FeedFilter current,
) {
  return showModalBottomSheet<FeedFilter>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    useRootNavigator: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    backgroundColor: Colors.transparent,
    builder: (_) => _FeedFilterSheet(current: current),
  );
}

class _FeedFilterSheet extends StatefulWidget {
  const _FeedFilterSheet({required this.current});
  final FeedFilter current;

  @override
  State<_FeedFilterSheet> createState() => _FeedFilterSheetState();
}

class _FeedFilterSheetState extends State<_FeedFilterSheet> {
  late Set<EchoStatus> _statuses;
  late Set<EchoCategory> _categories;
  late FeedSortBy _sortBy;
  late bool _verifiedOnly;
  late bool _unverifiedOnly;

  @override
  void initState() {
    super.initState();
    _statuses = Set.from(widget.current.statuses);
    _categories = Set.from(widget.current.categories);
    _sortBy = widget.current.sortBy;
    _verifiedOnly = widget.current.showVerifiedOnly;
    _unverifiedOnly = widget.current.showUnverifiedOnly;
  }

  void _toggleStatus(EchoStatus s) {
    HapticFeedback.selectionClick();
    setState(() {
      if (_statuses.contains(s)) {
        _statuses.remove(s);
      } else {
        _statuses.add(s);
      }
    });
  }

  void _toggleCategory(EchoCategory c) {
    HapticFeedback.selectionClick();
    setState(() {
      if (_categories.contains(c)) {
        _categories.remove(c);
      } else {
        _categories.add(c);
      }
    });
  }

  void _reset() {
    HapticFeedback.lightImpact();
    setState(() {
      _statuses = {};
      _categories = {};
      _sortBy = FeedSortBy.trending;
      _verifiedOnly = false;
      _unverifiedOnly = false;
    });
  }

  void _apply() {
    Navigator.pop(
      context,
      FeedFilter(
        statuses: _statuses,
        categories: _categories,
        sortBy: _sortBy,
        showVerifiedOnly: _verifiedOnly,
        showUnverifiedOnly: _unverifiedOnly,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bottomPad = MediaQuery.of(context).padding.bottom;

    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.only(bottom: bottomPad),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // handle
          Center(
            child: Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(top: 12, bottom: 4),
              decoration: BoxDecoration(
                color: AppColors.borderMedium,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          // header
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.xl,
              vertical: AppSpacing.sm,
            ),
            child: Row(
              children: [
                Text(context.l('Filter feed'),
                    style: AppTypography.textTheme.titleMedium),
                const Spacer(),
                TextButton(
                  onPressed: _reset,
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.sunsetCoral,
                    padding: EdgeInsets.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: GoogleFonts.josefinSans(
                    fontSize: 13,
                    color: AppColors.sunsetCoral,
                    fontWeight: FontWeight.w600,
                  ).toString().isEmpty
                      ? Text(context.l('Reset'),
                          style: GoogleFonts.josefinSans(
                            fontSize: 13,
                            color: AppColors.sunsetCoral,
                            fontWeight: FontWeight.w600,
                          ))
                      : Text(context.l('Reset'),
                          style: GoogleFonts.josefinSans(
                            fontSize: 13,
                            color: AppColors.sunsetCoral,
                            fontWeight: FontWeight.w600,
                          )),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(AppSpacing.xl),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // sort by
                  _SectionTitle(context.l('Sort by')),
                  const SizedBox(height: AppSpacing.sm),
                  Wrap(
                    spacing: AppSpacing.sm,
                    runSpacing: AppSpacing.sm,
                    children: FeedSortBy.values.map((s) {
                      final active = _sortBy == s;
                      return _FilterChip(
                        label: context.l(s.label),
                        active: active,
                        activeColor: AppColors.charcoal,
                        onTap: () => setState(() => _sortBy = s),
                      );
                    }).toList(),
                  ),

                  const SizedBox(height: AppSpacing.xl),

                  // quick filters
                  _SectionTitle(context.l('Quick filters')),
                  const SizedBox(height: AppSpacing.sm),
                  Row(
                    children: [
                      Expanded(
                        child: _ToggleTile(
                          label: context.l('Verified only'),
                          icon: Icons.verified_outlined,
                          color: AppColors.fernGreen,
                          value: _verifiedOnly,
                          onChanged: (v) => setState(() {
                            _verifiedOnly = v;
                            if (v) _unverifiedOnly = false;
                          }),
                        ),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: _ToggleTile(
                          label: context.l('Unverified only'),
                          icon: Icons.hourglass_empty_rounded,
                          color: const Color(0xFF6B4FA0),
                          value: _unverifiedOnly,
                          onChanged: (v) => setState(() {
                            _unverifiedOnly = v;
                            if (v) _verifiedOnly = false;
                          }),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: AppSpacing.xl),

                  // status filters
                  _SectionTitle(context.l('Status')),
                  const SizedBox(height: AppSpacing.sm),
                  Wrap(
                    spacing: AppSpacing.sm,
                    runSpacing: AppSpacing.sm,
                    children: _statusOptions.map((opt) {
                      final active = _statuses.contains(opt.status);
                      return _FilterChip(
                        label: context.l(opt.label),
                        active: active,
                        activeColor: opt.color,
                        onTap: () => _toggleStatus(opt.status),
                      );
                    }).toList(),
                  ),

                  const SizedBox(height: AppSpacing.xl),

                  // category filters
                  _SectionTitle(context.l('Categories')),
                  const SizedBox(height: AppSpacing.sm),
                  Wrap(
                    spacing: AppSpacing.sm,
                    runSpacing: AppSpacing.sm,
                    children: EchoCategory.values.map((cat) {
                      final active = _categories.contains(cat);
                      return _FilterChip(
                        label: context.l(cat.displayName),
                        active: active,
                        activeColor: AppColors.charcoal,
                        onTap: () => _toggleCategory(cat),
                      );
                    }).toList(),
                  ),

                  const SizedBox(height: AppSpacing.xxl),
                ],
              ),
            ),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(
              16,
              16,
              16,
              16 + MediaQuery.of(context).padding.bottom,
            ),
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _apply,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.charcoal,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  elevation: 0,
                ),
                child: Text(
                  context.l('Apply filters'),
                  style: GoogleFonts.josefinSans(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: GoogleFonts.josefinSans(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: AppColors.charcoal,
        letterSpacing: 0.3,
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.active,
    required this.activeColor,
    required this.onTap,
  });

  final String label;
  final bool active;
  final Color activeColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color:
              active ? activeColor.withValues(alpha: 0.1) : AppColors.softSand,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: active
                ? activeColor.withValues(alpha: 0.5)
                : AppColors.borderSubtle,
            width: active ? 1.5 : 1,
          ),
        ),
        child: Text(
          label,
          style: GoogleFonts.josefinSans(
            fontSize: 12,
            fontWeight: active ? FontWeight.w600 : FontWeight.w400,
            color: active ? activeColor : AppColors.textSecondary,
          ),
        ),
      ),
    );
  }
}

class _ToggleTile extends StatelessWidget {
  const _ToggleTile({
    required this.label,
    required this.icon,
    required this.color,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final IconData icon;
  final Color color;
  final bool value;
  final void Function(bool) onChanged;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => onChanged(!value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: value ? color.withValues(alpha: 0.08) : AppColors.softSand,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color:
                value ? color.withValues(alpha: 0.4) : AppColors.borderSubtle,
            width: value ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            Icon(icon, size: 16, color: value ? color : AppColors.textTertiary),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                label,
                style: GoogleFonts.josefinSans(
                  fontSize: 12,
                  fontWeight: value ? FontWeight.w600 : FontWeight.w400,
                  color: value ? color : AppColors.textSecondary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

const _statusOptions = [
  (
    status: EchoStatus.verified,
    label: 'Verified',
    color: AppColors.fernGreen,
  ),
  (
    status: EchoStatus.active,
    label: 'Active',
    color: Color(0xFF1A6DB5),
  ),
  (
    status: EchoStatus.pendingVerification,
    label: 'Pending',
    color: Color(0xFF6B4FA0),
  ),
  (
    status: EchoStatus.controversial,
    label: 'Controversial',
    color: Color(0xFFE8A000),
  ),
  (
    status: EchoStatus.disputed,
    label: 'Disputed',
    color: AppColors.sunsetCoral,
  ),
  (
    status: EchoStatus.underReview,
    label: 'Under review',
    color: Color(0xFFF5A623),
  ),
];
