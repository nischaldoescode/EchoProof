// small social action used by feed cards and reply rows
// @params icon inactive action icon
// @params activeIcon optional icon shown after optimistic state updates

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../app/theme/colors.dart';
import '../../app/theme/spacing.dart';
import '../../app/theme/typography.dart';
import '../../core/utils/app_haptics.dart';

/// renders an optimistic social action with a compact perspective pulse.
///
/// the button keeps the animation local to the tapped action so high-volume
/// lists can update one visible row without rebuilding the whole feed.
class SocialActionButton extends StatefulWidget {
  const SocialActionButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    this.activeIcon,
    this.active = false,
    this.compact = false,
    this.activeColor = AppColors.fernGreen,
    this.inactiveColor = AppColors.textTertiary,
    this.minWidth = 36,
    this.showBurst = false,
  });

  final IconData icon;
  final IconData? activeIcon;
  final String label;
  final VoidCallback onTap;
  final bool active;
  final bool compact;
  final Color activeColor;
  final Color inactiveColor;
  final double minWidth;
  final bool showBurst;

  @override
  State<SocialActionButton> createState() => _SocialActionButtonState();
}

class _SocialActionButtonState extends State<SocialActionButton>
    with TickerProviderStateMixin {
  late final AnimationController _pressController;
  late final AnimationController _stateController;
  late final Animation<double> _pressScale;
  int _burst = 0;
  bool _lastBurstWasActive = false;

  @override
  void initState() {
    super.initState();
    _pressController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 90),
      reverseDuration: const Duration(milliseconds: 80),
    );
    _stateController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 340),
    );
    _pressScale = Tween<double>(begin: 1, end: 0.94).animate(
      CurvedAnimation(parent: _pressController, curve: Curves.easeOutCubic),
    );
  }

  @override
  void didUpdateWidget(covariant SocialActionButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.active == widget.active) return;

    _lastBurstWasActive = widget.active;
    _stateController.forward(from: 0);
    if (widget.showBurst && widget.active) {
      setState(() {
        _burst++;
      });
    }
  }

  @override
  void dispose() {
    _pressController.dispose();
    _stateController.dispose();
    super.dispose();
  }

  Future<void> _handleTap() async {
    AppHaptics.selection(key: 'social_${widget.icon.codePoint}');
    await _pressController.forward();
    await _pressController.reverse();
    if (!mounted) return;
    widget.onTap();
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.active ? widget.activeColor : widget.inactiveColor;
    final icon = widget.active ? widget.activeIcon ?? widget.icon : widget.icon;

    return Semantics(
      button: true,
      selected: widget.active,
      label: widget.label.isEmpty ? null : widget.label,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _handleTap,
        child: ScaleTransition(
          scale: _pressScale,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minWidth: widget.minWidth,
              minHeight: widget.compact ? 30 : 36,
            ),
            child: Stack(
              clipBehavior: Clip.none,
              alignment: Alignment.center,
              children: [
                AnimatedBuilder(
                  animation: _stateController,
                  builder: (context, child) {
                    final progress = Curves.easeOutCubic.transform(
                      _stateController.value,
                    );
                    final arc = math.sin(progress * math.pi);
                    final activeDirection = widget.active ? -1.0 : 1.0;
                    final scale = 1.0 + arc * (widget.active ? 0.07 : 0.04);
                    final transform = Matrix4.identity()
                      ..setEntry(3, 2, 0.001)
                      ..rotateY(arc * 0.16 * activeDirection)
                      ..rotateX(arc * 0.05 * activeDirection)
                      ..scaleByDouble(scale, scale, scale, 1);

                    return Transform(
                      alignment: Alignment.center,
                      transform: transform,
                      child: child,
                    );
                  },
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 170),
                        switchInCurve: Curves.easeOutCubic,
                        switchOutCurve: Curves.easeInCubic,
                        transitionBuilder: (child, animation) {
                          return ScaleTransition(
                            scale: Tween<double>(
                              begin: 0.90,
                              end: 1,
                            ).animate(animation),
                            child: FadeTransition(
                              opacity: animation,
                              child: child,
                            ),
                          );
                        },
                        child: Icon(
                          icon,
                          key: ValueKey('${icon.codePoint}-${widget.active}'),
                          size: widget.compact ? 17 : 18,
                          color: color,
                          shadows: widget.active
                              ? [
                                  Shadow(
                                    color: widget.activeColor.withValues(
                                      alpha: 0.12,
                                    ),
                                    blurRadius: 4,
                                  ),
                                ]
                              : null,
                        ),
                      ),
                      if (widget.label.isNotEmpty) ...[
                        const SizedBox(width: 5),
                        Flexible(
                          child: AnimatedSwitcher(
                            duration: const Duration(milliseconds: 180),
                            switchInCurve: Curves.easeOutCubic,
                            switchOutCurve: Curves.easeInCubic,
                            transitionBuilder: (child, animation) {
                              return AnimatedBuilder(
                                animation: animation,
                                child: child,
                                builder: (context, child) {
                                  final value = animation.value
                                      .clamp(0.0, 1.0)
                                      .toDouble();
                                  final lift = (1 - value) * 3;
                                  final transform = Matrix4.identity()
                                    ..setEntry(3, 2, 0.001)
                                    ..rotateX((1 - value) * 0.20)
                                    ..translateByDouble(0.0, lift, 0.0, 1);

                                  return Opacity(
                                    opacity: value,
                                    child: Transform(
                                      alignment: Alignment.center,
                                      transform: transform,
                                      child: child,
                                    ),
                                  );
                                },
                              );
                            },
                            child: Text(
                              widget.label,
                              key: ValueKey(widget.label),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: widget.compact ? 11.5 : 12.5,
                                fontWeight: widget.active
                                    ? FontWeight.w800
                                    : FontWeight.w600,
                                color: color,
                                fontFamily: AppTypography.fontFamily,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                if (_burst > 0 && widget.showBurst && _lastBurstWasActive)
                  _SocialActionBurst(
                    key: ValueKey(_burst),
                    color: _lastBurstWasActive
                        ? widget.activeColor
                        : widget.inactiveColor,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SocialActionBurst extends StatelessWidget {
  const _SocialActionBurst({super.key, required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: 1),
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOutCubic,
        builder: (context, value, child) {
          final opacity = (1 - value).clamp(0.0, 1.0).toDouble();
          final ringScale = 0.92 + value * 0.28;
          return Opacity(
            opacity: opacity,
            child: Transform.scale(
              scale: ringScale,
              child: SizedBox(
                width: 30,
                height: 30,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    for (var i = 0; i < 4; i++)
                      _BurstParticle(
                        color: color,
                        angle: (math.pi * 2 / 4) * i,
                        progress: value,
                      ),
                    Container(
                      width: 22 + value * 7,
                      height: 22 + value * 7,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: color.withValues(alpha: 0.12 * opacity),
                          width: 0.9,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _BurstParticle extends StatelessWidget {
  const _BurstParticle({
    required this.color,
    required this.angle,
    required this.progress,
  });

  final Color color;
  final double angle;
  final double progress;

  @override
  Widget build(BuildContext context) {
    final distance = 6 + progress * 8;
    return Transform.translate(
      offset: Offset(math.cos(angle) * distance, math.sin(angle) * distance),
      child: Container(
        width: 2.8,
        height: 2.8,
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.38),
          borderRadius: BorderRadius.circular(AppSpacing.radiusFull),
        ),
      ),
    );
  }
}
