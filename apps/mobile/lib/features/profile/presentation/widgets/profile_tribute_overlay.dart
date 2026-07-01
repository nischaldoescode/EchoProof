// hidden own-profile tribute overlay
// keeps the profile easter egg isolated from profile layout and data loading

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../../../app/theme/colors.dart';
import '../../../../app/theme/typography.dart';

enum ProfileTributeMood { warm, bright, quiet }

const _tributeRouteTransitionDuration = Duration(milliseconds: 460);
const _tributeExitDuration = Duration(milliseconds: 760);

class ProfileTributeSpec {
  const ProfileTributeSpec({
    required this.username,
    required this.name,
    required this.message,
    required this.caption,
    required this.mood,
    this.storyLine = '',
    this.showKissStory = false,
    this.kissEmoji = '',
  });

  final String username;
  final String name;
  final String message;
  final String caption;
  final ProfileTributeMood mood;

  /// optional one-line phrase shown under the main message.
  ///
  /// this is intentionally separate from the shared message so bips can have
  /// the long personal line without changing the isha123 tribute.
  final String storyLine;

  /// enables the romantic kiss-story composition for selected profiles only.
  ///
  /// keeping this explicit avoids future warm or bright tribute entries
  /// accidentally receiving the private kiss svg and emoji sequence.
  final bool showKissStory;

  /// emoji rendered beside the long line and inside the kiss-story motion.
  ///
  /// the glyph is supplied by the spec so the svg story can stay reusable while
  /// the visible emotion can be changed without editing the drawing layer.
  final String kissEmoji;
}

/// returns a private tribute only for supported own-profile usernames.
///
/// usernames are matched after trimming, lowercasing, and removing a leading
/// at-sign so the guard is stable for route params, display handles, and tests.
ProfileTributeSpec? profileTributeSpecForUsername(String? username) {
  final normalized = username
      ?.trim()
      .replaceFirst(RegExp(r'^@+'), '')
      .toLowerCase();
  return switch (normalized) {
    'bips' => const ProfileTributeSpec(
      username: 'bips',
      name: 'bipuu',
      message: 'my girl, i love u so so much',
      storyLine: 'myyyyyyyyyy bipuuuuuuuuuuuuuuuuu',
      caption: 'a soft little scene, just for you',
      mood: ProfileTributeMood.warm,
      showKissStory: true,
      kissEmoji: '💋',
    ),
    'isha123' => const ProfileTributeSpec(
      username: 'isha123',
      name: 'garuu, mayaluu',
      message: 'my girl, i love u so so much',
      caption: 'a bright little scene, just for you',
      mood: ProfileTributeMood.bright,
      showKissStory: true,
      kissEmoji: '💋',
    ),
    'hulk' => const ProfileTributeSpec(
      username: 'hulk',
      name: 'hulk',
      message: "it's not gonna change for you always a loser",
      caption: 'a quiet scene for a heavy kind of day',
      mood: ProfileTributeMood.quiet,
    ),
    _ => null,
  };
}

/// converts the tap burst into display time.
///
/// three taps is the minimum reveal and long tap bursts are capped so the
/// profile never feels trapped behind a hidden animation.
Duration profileTributeDurationForTapCount(int tapCount) {
  final seconds = tapCount.clamp(3, 10).toInt();
  return Duration(seconds: seconds);
}

Future<void> showProfileTributeOverlay(
  BuildContext context, {
  required ProfileTributeSpec spec,
  required Duration duration,
}) {
  return showGeneralDialog<void>(
    context: context,
    useRootNavigator: true,
    barrierDismissible: false,
    barrierLabel: 'profile tribute',
    barrierColor: Colors.transparent,
    transitionDuration: _tributeRouteTransitionDuration,
    pageBuilder: (context, animation, secondaryAnimation) {
      return ProfileTributeOverlay(spec: spec, duration: duration);
    },
    transitionBuilder: (context, animation, secondaryAnimation, child) {
      final reduceMotion = MediaQuery.disableAnimationsOf(context);
      final fade = CurvedAnimation(
        parent: animation,
        curve: reduceMotion ? Curves.linear : Curves.easeOutCubic,
        reverseCurve: reduceMotion ? Curves.linear : Curves.easeInCubic,
      );
      if (reduceMotion) return FadeTransition(opacity: fade, child: child);
      return FadeTransition(
        opacity: fade,
        child: ScaleTransition(
          scale: Tween<double>(begin: 1.018, end: 1).animate(fade),
          child: child,
        ),
      );
    },
  );
}

class ProfileTributeOverlay extends StatefulWidget {
  const ProfileTributeOverlay({
    super.key,
    required this.spec,
    required this.duration,
  });

  final ProfileTributeSpec spec;
  final Duration duration;

  @override
  State<ProfileTributeOverlay> createState() => _ProfileTributeOverlayState();
}

class _ProfileTributeOverlayState extends State<ProfileTributeOverlay>
    with TickerProviderStateMixin {
  late final AnimationController _sceneCtrl;
  late final AnimationController _exitCtrl;
  Timer? _closeTimer;
  bool _closing = false;

  @override
  void initState() {
    super.initState();
    _sceneCtrl = AnimationController(vsync: this, duration: widget.duration);
    _exitCtrl = AnimationController(
      vsync: this,
      duration: _tributeExitDuration,
    );
    _closeTimer = Timer(widget.duration, () => unawaited(_beginClose()));
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    if (reduceMotion) {
      _sceneCtrl.value = 1;
      if (_closing) _exitCtrl.value = 1;
      return;
    }
    if (!_sceneCtrl.isAnimating && _sceneCtrl.value == 0) {
      _sceneCtrl.forward();
    }
  }

  @override
  void dispose() {
    _closeTimer?.cancel();
    _sceneCtrl.dispose();
    _exitCtrl.dispose();
    super.dispose();
  }

  Future<void> _beginClose() async {
    if (_closing || !mounted) return;
    _closing = true;
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (reduceMotion) {
      _exitCtrl.value = 1;
    } else {
      await _exitCtrl.forward();
    }
    if (!mounted) return;
    Navigator.of(context, rootNavigator: true).pop();
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final palette = _TributePalette.forMood(widget.spec.mood);

    return PopScope(
      canPop: false,
      child: AnimatedBuilder(
        animation: Listenable.merge([_sceneCtrl, _exitCtrl]),
        builder: (context, _) {
          final exit = _exitCtrl.value.clamp(0, 1).toDouble();
          final exitEase = Curves.easeInOutCubic.transform(exit);
          final romantic = widget.spec.mood != ProfileTributeMood.quiet;
          final sceneScale = romantic
              ? 1.0 + exitEase * 0.018
              : 1.0 - exitEase * 0.012;

          return Opacity(
            opacity: (1.0 - exitEase).clamp(0, 1).toDouble(),
            child: Transform.scale(
              scale: sceneScale,
              child: Material(
                color: Colors.transparent,
                child: CustomPaint(
                  painter: _TributeBackdropPainter(
                    progress: _sceneCtrl.value,
                    exitProgress: exit,
                    palette: palette,
                    mood: widget.spec.mood,
                    reduceMotion: media.disableAnimations,
                  ),
                  child: SafeArea(
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final compact =
                            constraints.maxWidth < 380 ||
                            constraints.maxHeight < 600;
                        final tightHeight = constraints.maxHeight < 520;
                        final padding = EdgeInsets.symmetric(
                          horizontal: constraints.maxWidth < 360 ? 16 : 24,
                          vertical: tightHeight ? 14 : 24,
                        );
                        return Center(
                          child: SingleChildScrollView(
                            physics: const ClampingScrollPhysics(),
                            padding: padding,
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 560),
                              child: _TributeMessageCard(
                                spec: widget.spec,
                                palette: palette,
                                progress: _sceneCtrl.value,
                                exitProgress: exit,
                                compact: compact,
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _TributeMessageCard extends StatelessWidget {
  const _TributeMessageCard({
    required this.spec,
    required this.palette,
    required this.progress,
    required this.exitProgress,
    required this.compact,
  });

  final ProfileTributeSpec spec;
  final _TributePalette palette;
  final double progress;
  final double exitProgress;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final reveal = Curves.easeOutCubic.transform(
      progress.clamp(0, 1).toDouble(),
    );
    final exit = Curves.easeInOutCubic.transform(
      exitProgress.clamp(0, 1).toDouble(),
    );
    final romantic =
        spec.showKissStory && spec.mood != ProfileTributeMood.quiet;
    final textColor = spec.mood == ProfileTributeMood.quiet
        ? AppColors.white.withValues(alpha: 0.90)
        : AppColors.white;
    final scale =
        (0.94 + reveal * 0.06) *
        (romantic ? 1.0 + exit * 0.045 : 1.0 - exit * 0.035);
    final offset = Offset(
      0,
      (1.0 - reveal) * 18 + (romantic ? -34 * exit : 22 * exit),
    );
    final opacity = (reveal * (1.0 - exit)).clamp(0, 1).toDouble();

    return Opacity(
      opacity: opacity,
      child: Transform.translate(
        offset: offset,
        child: Transform.scale(
          scale: scale,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: Colors.white.withValues(
                alpha: spec.mood == ProfileTributeMood.quiet ? 0.055 : 0.075,
              ),
              borderRadius: BorderRadius.circular(compact ? 26 : 32),
              border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
              boxShadow: [
                BoxShadow(
                  color: palette.glow.withValues(alpha: romantic ? 0.30 : 0.18),
                  blurRadius: romantic ? 56 : 38,
                  spreadRadius: romantic ? 4 : 1,
                ),
              ],
            ),
            child: Padding(
              padding: EdgeInsets.symmetric(
                horizontal: compact ? 24 : 34,
                vertical: compact ? 28 : 38,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (romantic)
                    _RomanticStoryScene(
                      mood: spec.mood,
                      progress: progress,
                      exitProgress: exitProgress,
                      compact: compact,
                      kissEmoji: spec.kissEmoji,
                    )
                  else
                    _TributeHaloIcon(
                      palette: palette,
                      mood: spec.mood,
                      progress: progress,
                      exitProgress: exitProgress,
                    ),
                  SizedBox(height: compact ? 22 : 28),
                  Text(
                    spec.name,
                    textAlign: TextAlign.center,
                    style: AppTypography.josefin(
                      size: compact ? 30 : 38,
                      weight: FontWeight.w900,
                      color: textColor,
                      height: 1.05,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    spec.message,
                    textAlign: TextAlign.center,
                    style: AppTypography.josefin(
                      size: compact ? 21 : 26,
                      weight: FontWeight.w800,
                      color: textColor.withValues(alpha: 0.96),
                      height: 1.22,
                    ),
                  ),
                  if (spec.storyLine.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    _TributeStoryLine(
                      text: spec.storyLine,
                      palette: palette,
                      progress: progress,
                      exitProgress: exitProgress,
                      compact: compact,
                      kissEmoji: spec.kissEmoji,
                    ),
                  ],
                  SizedBox(height: compact ? 18 : 24),
                  Text(
                    spec.caption,
                    textAlign: TextAlign.center,
                    style: AppTypography.josefin(
                      size: 14,
                      weight: FontWeight.w600,
                      color: textColor.withValues(alpha: 0.68),
                      height: 1.35,
                    ),
                  ),
                  const SizedBox(height: 22),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(99),
                    child: LinearProgressIndicator(
                      minHeight: 3,
                      value: progress.clamp(0, 1).toDouble(),
                      backgroundColor: Colors.white.withValues(alpha: 0.10),
                      valueColor: AlwaysStoppedAnimation<Color>(palette.glow),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _RomanticStoryScene extends StatelessWidget {
  const _RomanticStoryScene({
    required this.mood,
    required this.progress,
    required this.exitProgress,
    required this.compact,
    required this.kissEmoji,
  });

  final ProfileTributeMood mood;
  final double progress;
  final double exitProgress;
  final bool compact;
  final String kissEmoji;

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final p = progress.clamp(0, 1).toDouble();
    final exit = Curves.easeInOutCubic.transform(
      exitProgress.clamp(0, 1).toDouble(),
    );
    final reveal = Curves.easeOutCubic.transform(p);
    final sway = reduceMotion ? 0.0 : math.sin(p * math.pi * 3.2) * 4;
    final kissLift = reduceMotion ? 0.0 : math.sin(p * math.pi * 4.5) * 5;
    final kissPulse = reduceMotion
        ? 1.0
        : 1.0 + math.sin(p * math.pi * 5.4).abs() * 0.08;
    final kissReveal = Curves.easeOutCubic.transform((p * 1.3).clamp(0, 1));
    final width = compact ? 260.0 : 330.0;
    final height = compact ? 130.0 : 158.0;
    final emoji = kissEmoji.isEmpty ? '💋' : kissEmoji;

    return SizedBox(
      width: double.infinity,
      height: height,
      child: Stack(
        alignment: Alignment.center,
        clipBehavior: Clip.none,
        children: [
          // the scene uses separate svg layers so the hand-hold, kiss frame,
          // kiss mark, and emoji can move independently without relayout.
          // this keeps the cinematic effect smooth on small screens because
          // only transforms and opacity change after the first layout pass.
          Transform.translate(
            offset: Offset(sway * 0.18, 10 * (1 - reveal) + exit * 18),
            child: Transform.scale(
              scale: (0.94 + reveal * 0.06) * (1 - exit * 0.04),
              child: Opacity(
                opacity: (reveal * (1 - exit)).clamp(0, 1).toDouble(),
                child: SizedBox(
                  width: width,
                  height: height,
                  child: SvgPicture.string(
                    _romanticStorySvg(mood),
                    key: const ValueKey('profile_tribute_romantic_story'),
                    fit: BoxFit.contain,
                    excludeFromSemantics: true,
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            left: compact ? 16 : 24,
            bottom: compact ? 4 : 6,
            child: Transform.translate(
              offset: Offset(sway * 0.34, (1 - kissReveal) * 12 + exit * 20),
              child: Transform.scale(
                scale: (0.9 + kissReveal * 0.1) * kissPulse,
                child: Opacity(
                  opacity: (kissReveal * (1 - exit)).clamp(0, 1).toDouble(),
                  child: SvgPicture.string(
                    _romanticKissStorySvg(mood),
                    key: const ValueKey('profile_tribute_kiss_story'),
                    width: compact ? 118 : 146,
                    height: compact ? 54 : 66,
                    fit: BoxFit.contain,
                    excludeFromSemantics: true,
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            top: compact ? 8 : 10,
            child: Transform.translate(
              offset: Offset(sway * -0.24, -kissLift - exit * 28),
              child: Transform.scale(
                scale:
                    0.86 +
                    reveal * 0.18 +
                    (reduceMotion ? 0 : kissLift.abs() * 0.004),
                child: Opacity(
                  opacity: (0.84 * reveal * (1 - exit)).clamp(0, 1).toDouble(),
                  child: SvgPicture.string(
                    _romanticKissSvg(mood),
                    width: compact ? 72 : 88,
                    height: compact ? 42 : 50,
                    fit: BoxFit.contain,
                    excludeFromSemantics: true,
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            right: compact ? 30 : 40,
            top: compact ? 20 : 24,
            child: Transform.translate(
              offset: Offset(sway * -0.2, -kissLift * 0.7 - exit * 22),
              child: Transform.rotate(
                angle: reduceMotion ? 0 : math.sin(p * math.pi * 2.8) * 0.12,
                child: Opacity(
                  opacity: (0.9 * kissReveal * (1 - exit)).clamp(0, 1),
                  child: Text(
                    emoji,
                    style: TextStyle(
                      fontSize: compact ? 25 : 31,
                      height: 1,
                      shadows: [
                        Shadow(
                          color: Colors.black.withValues(alpha: 0.20),
                          blurRadius: 12,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
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

class _TributeStoryLine extends StatelessWidget {
  const _TributeStoryLine({
    required this.text,
    required this.palette,
    required this.progress,
    required this.exitProgress,
    required this.compact,
    required this.kissEmoji,
  });

  final String text;
  final _TributePalette palette;
  final double progress;
  final double exitProgress;
  final bool compact;
  final String kissEmoji;

  @override
  Widget build(BuildContext context) {
    final reveal = Curves.easeOutCubic.transform(
      progress.clamp(0, 1).toDouble(),
    );
    final exit = Curves.easeInOutCubic.transform(
      exitProgress.clamp(0, 1).toDouble(),
    );
    final opacity = (reveal * (1 - exit)).clamp(0, 1).toDouble();
    final lift = (1 - reveal) * 8 + exit * 10;
    final emoji = kissEmoji.isEmpty ? '💋' : kissEmoji;

    // this line can be intentionally long, so it is wrapped inside a flexible
    // pill and ellipsized instead of letting one word stretch the overlay.
    return Opacity(
      opacity: opacity,
      child: Transform.translate(
        offset: Offset(0, lift),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.11),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: palette.glow.withValues(alpha: 0.28)),
          ),
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: compact ? 12 : 16,
              vertical: compact ? 7 : 8,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  emoji,
                  style: TextStyle(fontSize: compact ? 15 : 17, height: 1),
                ),
                const SizedBox(width: 7),
                Flexible(
                  child: Text(
                    text,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    softWrap: false,
                    textAlign: TextAlign.center,
                    style: AppTypography.josefin(
                      size: compact ? 13 : 15,
                      weight: FontWeight.w900,
                      color: Colors.white.withValues(alpha: 0.94),
                      height: 1.15,
                    ),
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

String _romanticStorySvg(ProfileTributeMood mood) {
  final warm = mood == ProfileTributeMood.warm;
  final glow = warm ? '#FF9AB8' : '#75E0A8';
  final accent = warm ? '#FFD166' : '#FFB3D1';
  final deep = warm ? '#3A1022' : '#0D2E25';
  final soft = warm ? '#FFE3ED' : '#DDFBEA';
  final dressLeft = warm ? '#FF6F9D' : '#58D99A';
  final dressRight = warm ? '#FFC2D6' : '#FF9FC7';

  // the svg is intentionally inline so the hidden scene ships with the widget
  // and never depends on a separate asset path or generated file.
  return '''
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 360 170">
  <defs>
    <linearGradient id="sky" x1="0" y1="0" x2="360" y2="170" gradientUnits="userSpaceOnUse">
      <stop stop-color="$deep" stop-opacity="0.92"/>
      <stop offset="1" stop-color="#000000" stop-opacity="0.10"/>
    </linearGradient>
    <radialGradient id="glow" cx="0" cy="0" r="1" gradientUnits="userSpaceOnUse" gradientTransform="translate(180 82) rotate(90) scale(118 178)">
      <stop stop-color="$glow" stop-opacity="0.55"/>
      <stop offset="0.62" stop-color="$accent" stop-opacity="0.16"/>
      <stop offset="1" stop-color="$glow" stop-opacity="0"/>
    </radialGradient>
  </defs>
  <rect width="360" height="170" rx="34" fill="url(#sky)" opacity="0.62"/>
  <ellipse cx="180" cy="90" rx="146" ry="82" fill="url(#glow)"/>
  <path d="M46 139C88 117 127 121 162 137C201 155 248 147 314 126" stroke="$soft" stroke-opacity="0.18" stroke-width="10" stroke-linecap="round"/>
  <path d="M61 128C118 104 159 111 203 132C236 148 280 145 322 119" stroke="$glow" stroke-opacity="0.26" stroke-width="3" stroke-linecap="round"/>

  <g opacity="0.92">
    <circle cx="126" cy="69" r="15" fill="#FFE0C8"/>
    <path d="M109 67C114 47 134 46 142 62C136 58 128 56 118 61C115 64 112 66 109 67Z" fill="#24121A"/>
    <path d="M116 86C109 101 104 120 99 142H157C153 119 148 101 140 86C134 91 123 91 116 86Z" fill="$dressLeft"/>
    <path d="M116 87C126 96 137 94 142 86" stroke="$soft" stroke-opacity="0.42" stroke-width="3" stroke-linecap="round"/>
    <path d="M115 104C101 112 89 122 78 135" stroke="#FFE0C8" stroke-width="8" stroke-linecap="round"/>
    <path d="M140 104C154 112 166 120 178 130" stroke="#FFE0C8" stroke-width="8" stroke-linecap="round"/>
    <circle cx="180" cy="130" r="7" fill="#FFE0C8"/>
  </g>

  <g opacity="0.94">
    <circle cx="235" cy="68" r="15" fill="#F7C7AA"/>
    <path d="M218 66C222 47 244 45 251 63C246 59 239 57 230 60C225 62 222 65 218 66Z" fill="#261520"/>
    <path d="M225 86C216 103 211 122 207 142H265C260 120 254 101 245 86C239 92 230 92 225 86Z" fill="$dressRight"/>
    <path d="M224 87C233 96 243 95 247 86" stroke="$soft" stroke-opacity="0.42" stroke-width="3" stroke-linecap="round"/>
    <path d="M223 104C209 112 195 120 182 130" stroke="#F7C7AA" stroke-width="8" stroke-linecap="round"/>
    <path d="M247 103C263 110 275 120 286 135" stroke="#F7C7AA" stroke-width="8" stroke-linecap="round"/>
    <circle cx="180" cy="130" r="5.5" fill="#F7C7AA"/>
  </g>

  <path d="M147 49C155 37 168 39 174 51C180 38 195 37 202 49C210 64 186 80 174 91C162 80 139 64 147 49Z" fill="$glow" fill-opacity="0.58"/>
  <path d="M93 45C98 39 104 39 108 45C112 39 119 39 123 45C128 55 113 64 108 69C102 64 88 55 93 45Z" fill="$accent" fill-opacity="0.46"/>
  <path d="M257 43C262 37 268 38 272 44C277 38 284 38 288 45C292 54 278 63 272 68C266 63 252 54 257 43Z" fill="$accent" fill-opacity="0.48"/>
  <circle cx="69" cy="79" r="2.5" fill="$soft" opacity="0.7"/>
  <circle cx="297" cy="81" r="2.5" fill="$soft" opacity="0.7"/>
  <circle cx="183" cy="36" r="2" fill="$soft" opacity="0.8"/>
</svg>
''';
}

String _romanticKissStorySvg(ProfileTributeMood mood) {
  final warm = mood == ProfileTributeMood.warm;
  final glow = warm ? '#FF9AB8' : '#75E0A8';
  final accent = warm ? '#FFD166' : '#FFB3D1';
  final shadow = warm ? '#3A1022' : '#0D2E25';

  // this mini svg reads as a tiny story frame: two faces leaning toward a kiss,
  // a shared blush glow, and a soft ribbon that matches the main scene.
  return '''
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 160 74">
  <defs>
    <radialGradient id="kissGlow" cx="0" cy="0" r="1" gradientUnits="userSpaceOnUse" gradientTransform="translate(80 37) rotate(90) scale(42 70)">
      <stop stop-color="$glow" stop-opacity="0.48"/>
      <stop offset="1" stop-color="$glow" stop-opacity="0"/>
    </radialGradient>
  </defs>
  <rect x="8" y="8" width="144" height="58" rx="29" fill="#FFFFFF" fill-opacity="0.08"/>
  <rect x="9" y="9" width="142" height="56" rx="28" stroke="#FFFFFF" stroke-opacity="0.16" fill="none"/>
  <ellipse cx="80" cy="37" rx="66" ry="34" fill="url(#kissGlow)"/>
  <path d="M28 52C48 43 66 43 80 52C95 43 114 43 134 52" stroke="$accent" stroke-opacity="0.38" stroke-width="4" stroke-linecap="round"/>

  <g transform="translate(34 18) rotate(-5 24 24)">
    <circle cx="25" cy="22" r="13" fill="#FFE0C8"/>
    <path d="M14 20C17 8 31 7 36 18C31 15 25 14 19 17C17 18 15 19 14 20Z" fill="$shadow"/>
    <path d="M33 29C40 32 46 36 52 43" stroke="#FFE0C8" stroke-width="6" stroke-linecap="round"/>
    <circle cx="30" cy="23" r="1.8" fill="$shadow" fill-opacity="0.72"/>
    <path d="M34 29C38 29 41 28 44 26" stroke="$glow" stroke-width="2" stroke-linecap="round"/>
  </g>

  <g transform="translate(84 18) rotate(5 24 24)">
    <circle cx="25" cy="22" r="13" fill="#F7C7AA"/>
    <path d="M14 20C17 8 31 7 36 18C31 15 25 14 19 17C17 18 15 19 14 20Z" fill="$shadow"/>
    <path d="M17 29C10 32 4 36 -2 43" stroke="#F7C7AA" stroke-width="6" stroke-linecap="round"/>
    <circle cx="20" cy="23" r="1.8" fill="$shadow" fill-opacity="0.72"/>
    <path d="M16 29C12 29 9 28 6 26" stroke="$glow" stroke-width="2" stroke-linecap="round"/>
  </g>

  <path d="M70 25C74 20 79 21 82 26C86 21 92 20 95 26C99 34 87 42 82 46C77 42 66 34 70 25Z" fill="$glow" fill-opacity="0.82"/>
  <path d="M75 44C80 46 85 46 90 44" stroke="#FFFFFF" stroke-opacity="0.64" stroke-width="2" stroke-linecap="round"/>
</svg>
''';
}

String _romanticKissSvg(ProfileTributeMood mood) {
  final warm = mood == ProfileTributeMood.warm;
  final glow = warm ? '#FF9AB8' : '#75E0A8';
  final accent = warm ? '#FFD166' : '#FFB3D1';

  return '''
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 110 64">
  <path d="M19 36C31 22 46 23 55 36C64 23 80 22 91 36C78 45 66 49 55 48C44 49 31 45 19 36Z" fill="$glow" fill-opacity="0.70"/>
  <path d="M24 35C36 39 45 40 55 39C65 40 74 39 86 35" stroke="#FFFFFF" stroke-opacity="0.58" stroke-width="3" stroke-linecap="round"/>
  <path d="M52 13C57 7 63 8 67 14C72 8 80 8 83 15C88 24 73 34 67 39C61 34 47 24 52 13Z" fill="$accent" fill-opacity="0.82"/>
  <circle cx="20" cy="17" r="2.4" fill="#FFFFFF" opacity="0.72"/>
  <circle cx="91" cy="19" r="2.4" fill="#FFFFFF" opacity="0.72"/>
</svg>
''';
}

class _TributeHaloIcon extends StatelessWidget {
  const _TributeHaloIcon({
    required this.palette,
    required this.mood,
    required this.progress,
    required this.exitProgress,
  });

  final _TributePalette palette;
  final ProfileTributeMood mood;
  final double progress;
  final double exitProgress;

  @override
  Widget build(BuildContext context) {
    final p = progress.clamp(0, 1).toDouble();
    final exit = Curves.easeInOutCubic.transform(
      exitProgress.clamp(0, 1).toDouble(),
    );
    final romantic = mood != ProfileTributeMood.quiet;
    final pulse = romantic
        ? math.sin(p * math.pi * 6) * 0.055
        : math.sin(p * math.pi * 2) * 0.025;
    final scale =
        (1.0 + pulse) * (romantic ? 1 + exit * 0.08 : 1 - exit * 0.04);
    final rotation = romantic ? math.sin(p * math.pi * 2) * 0.08 : -exit * 0.08;
    final icon = mood == ProfileTributeMood.quiet
        ? Icons.nightlight_round
        : Icons.favorite_rounded;

    return Transform.rotate(
      angle: rotation,
      child: Transform.scale(
        scale: scale,
        child: Stack(
          alignment: Alignment.center,
          children: [
            Container(
              width: 118,
              height: 118,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    palette.glow.withValues(alpha: romantic ? 0.62 : 0.38),
                    palette.accent.withValues(alpha: romantic ? 0.18 : 0.12),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
            Container(
              width: 76,
              height: 76,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(alpha: 0.10),
                border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
              ),
              child: Icon(icon, color: palette.glow, size: 36),
            ),
          ],
        ),
      ),
    );
  }
}

class _TributeBackdropPainter extends CustomPainter {
  const _TributeBackdropPainter({
    required this.progress,
    required this.exitProgress,
    required this.palette,
    required this.mood,
    required this.reduceMotion,
  });

  final double progress;
  final double exitProgress;
  final _TributePalette palette;
  final ProfileTributeMood mood;
  final bool reduceMotion;

  @override
  void paint(Canvas canvas, Size size) {
    final p = progress.clamp(0, 1).toDouble();
    final exit = Curves.easeInOutCubic.transform(
      exitProgress.clamp(0, 1).toDouble(),
    );
    final rect = Offset.zero & size;
    final background = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Colors.black, palette.deep, Colors.black],
        stops: const [0, 0.54, 1],
      ).createShader(rect);
    canvas.drawRect(rect, background);

    _drawGlow(canvas, size, p, exit);
    if (mood == ProfileTributeMood.quiet) {
      _drawQuietMoon(canvas, size, p, exit);
      _drawRain(canvas, size, p, exit);
      _drawQuietOrbit(canvas, size, p, exit);
      _drawParticles(canvas, size, p, exit);
    } else {
      _drawAurora(canvas, size, p, exit);
      _drawParticles(canvas, size, p, exit);
      _drawHearts(canvas, size, p, exit);
    }
    _drawVignette(canvas, size);
  }

  void _drawGlow(Canvas canvas, Size size, double p, double exit) {
    final romantic = mood != ProfileTributeMood.quiet;
    final center = Offset(
      size.width * (romantic ? 0.52 : 0.48),
      size.height * (romantic ? 0.46 - exit * 0.03 : 0.50 + exit * 0.03),
    );
    final radius =
        math.max(size.width, size.height) *
        (romantic ? 0.34 + p * 0.12 + exit * 0.08 : 0.28 + p * 0.08);
    final paint = Paint()
      ..shader = RadialGradient(
        colors: [
          palette.glow.withValues(alpha: romantic ? 0.34 : 0.20),
          palette.accent.withValues(alpha: romantic ? 0.13 : 0.08),
          Colors.transparent,
        ],
      ).createShader(Rect.fromCircle(center: center, radius: radius));
    canvas.drawCircle(center, radius, paint);
  }

  void _drawAurora(Canvas canvas, Size size, double p, double exit) {
    final rect = Offset.zero & size;
    for (var i = 0; i < 3; i++) {
      final yBase = size.height * (0.24 + i * 0.15);
      final wave = reduceMotion ? 0.0 : math.sin(p * 4.6 + i) * 24;
      final lift = reduceMotion ? 0.0 : exit * (24 + i * 10);
      final path = Path()
        ..moveTo(-size.width * 0.12, yBase + wave - lift)
        ..cubicTo(
          size.width * 0.20,
          yBase - 76 + wave,
          size.width * 0.46,
          yBase + 82 - wave,
          size.width * 0.78,
          yBase + wave * 0.3 - lift,
        )
        ..cubicTo(
          size.width * 1.02,
          yBase - 58 - wave,
          size.width * 1.12,
          yBase + 28 + wave,
          size.width * 1.22,
          yBase - lift,
        );
      final alpha = (0.12 - i * 0.022) * (1.0 - exit * 0.70);
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = 44 - i * 8
        ..shader = LinearGradient(
          colors: [
            palette.glow.withValues(alpha: alpha.clamp(0, 1).toDouble()),
            palette.accent.withValues(
              alpha: (alpha * 0.9).clamp(0, 1).toDouble(),
            ),
            Colors.white.withValues(
              alpha: (alpha * 0.34).clamp(0, 1).toDouble(),
            ),
          ],
        ).createShader(rect)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 18);
      canvas.drawPath(path, paint);
    }
  }

  void _drawParticles(Canvas canvas, Size size, double p, double exit) {
    final paint = Paint()..style = PaintingStyle.fill;
    final quiet = mood == ProfileTributeMood.quiet;
    final count = size.shortestSide < 380 ? 28 : 44;
    for (var i = 0; i < count; i++) {
      final baseX = ((i * 73) % 100) / 100;
      final baseY = ((i * 41) % 100) / 100;
      final drift = reduceMotion ? 0.0 : math.sin((p * 5.4) + i) * 12;
      final travel = reduceMotion
          ? 0.0
          : p * (18 + (i % 5) * 8) + exit * (quiet ? 26 : 48);
      final offset = Offset(
        size.width * baseX + drift,
        quiet ? size.height * baseY + travel : size.height * baseY - travel,
      );
      final visible = quiet
          ? (0.10 + (i % 5) * 0.022) * (1 - exit * 0.45)
          : (0.20 + (i % 5) * 0.035) * (1 - exit * 0.40);
      paint.color = (i.isEven ? palette.glow : palette.accent).withValues(
        alpha: visible.clamp(0, 0.34).toDouble(),
      );
      canvas.drawCircle(
        offset,
        quiet ? 1.1 + (i % 3) * 0.45 : 1.4 + (i % 4) * 0.7,
        paint,
      );
    }
  }

  void _drawHearts(Canvas canvas, Size size, double p, double exit) {
    final paint = Paint()
      ..style = PaintingStyle.fill
      ..color = palette.glow.withValues(
        alpha: (0.24 * (1 - exit)).clamp(0, 1).toDouble(),
      );
    final count = size.shortestSide < 380 ? 9 : 14;
    for (var i = 0; i < count; i++) {
      final x = size.width * (0.10 + ((i * 19) % 80) / 100);
      final y =
          size.height * (0.18 + ((i * 17) % 68) / 100) -
          (reduceMotion ? 0 : p * (28 + i * 4) + exit * (58 + i * 5));
      final scale = 0.48 + (i % 5) * 0.13 + exit * 0.18;
      canvas.save();
      canvas.translate(x, y);
      canvas.rotate(reduceMotion ? 0 : math.sin(p * 3.2 + i) * 0.16);
      canvas.scale(scale);
      canvas.drawPath(_heartPath(), paint);
      canvas.restore();
    }
  }

  void _drawQuietMoon(Canvas canvas, Size size, double p, double exit) {
    final center = Offset(
      size.width * 0.78,
      size.height * 0.18 +
          (reduceMotion ? 0 : math.sin(p * 2.2) * 5 + exit * 18),
    );
    final radius = math.min(size.width, size.height) * 0.075;
    final glowPaint = Paint()
      ..shader = RadialGradient(
        colors: [palette.glow.withValues(alpha: 0.22), Colors.transparent],
      ).createShader(Rect.fromCircle(center: center, radius: radius * 3.2));
    canvas.drawCircle(center, radius * 3.2, glowPaint);
    canvas.drawCircle(
      center,
      radius,
      Paint()..color = palette.glow.withValues(alpha: 0.32),
    );
    canvas.drawCircle(
      center + Offset(radius * 0.38, -radius * 0.10),
      radius * 0.92,
      Paint()..color = palette.deep.withValues(alpha: 0.94),
    );
  }

  void _drawRain(Canvas canvas, Size size, double p, double exit) {
    final paint = Paint()
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 1.15
      ..color = palette.glow.withValues(alpha: 0.16 * (1 - exit * 0.35));
    final count = size.shortestSide < 380 ? 24 : 38;
    for (var i = 0; i < count; i++) {
      final x = size.width * (((i * 31) % 100) / 100);
      final base = size.height * (((i * 47) % 100) / 100);
      final fall = reduceMotion
          ? 0.0
          : (p * (95 + (i % 6) * 16)) % (size.height + 80);
      final start = Offset(
        x,
        (base + fall + exit * 30) % (size.height + 80) - 40,
      );
      canvas.drawLine(start, start + const Offset(-8, 24), paint);
    }
  }

  void _drawQuietOrbit(Canvas canvas, Size size, double p, double exit) {
    final center = Offset(size.width * 0.50, size.height * 0.54);
    final radius = math.min(size.width, size.height) * (0.28 + exit * 0.05);
    final rect = Rect.fromCircle(center: center, radius: radius);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..color = palette.accent.withValues(alpha: 0.22 * (1 - exit * 0.5));
    for (var i = 0; i < 3; i++) {
      final start = p * math.pi * 0.45 + i * math.pi * 0.68;
      canvas.drawArc(rect.inflate(i * 18), start, math.pi * 0.42, false, paint);
    }
  }

  void _drawVignette(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final paint = Paint()
      ..shader = RadialGradient(
        colors: [Colors.transparent, Colors.black.withValues(alpha: 0.46)],
        stops: const [0.55, 1],
      ).createShader(rect);
    canvas.drawRect(rect, paint);
  }

  Path _heartPath() {
    return Path()
      ..moveTo(0, 8)
      ..cubicTo(-20, -8, -31, 12, -16, 28)
      ..cubicTo(-8, 36, -1, 42, 0, 43)
      ..cubicTo(1, 42, 8, 36, 16, 28)
      ..cubicTo(31, 12, 20, -8, 0, 8)
      ..close();
  }

  @override
  bool shouldRepaint(covariant _TributeBackdropPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.exitProgress != exitProgress ||
        oldDelegate.palette != palette ||
        oldDelegate.mood != mood ||
        oldDelegate.reduceMotion != reduceMotion;
  }
}

class _TributePalette {
  const _TributePalette({
    required this.deep,
    required this.glow,
    required this.accent,
  });

  final Color deep;
  final Color glow;
  final Color accent;

  static _TributePalette forMood(ProfileTributeMood mood) {
    return switch (mood) {
      ProfileTributeMood.warm => const _TributePalette(
        deep: Color(0xFF190811),
        glow: Color(0xFFFF9AB8),
        accent: Color(0xFFFFD166),
      ),
      ProfileTributeMood.bright => const _TributePalette(
        deep: Color(0xFF071B15),
        glow: Color(0xFF75E0A8),
        accent: Color(0xFFFFB3D1),
      ),
      ProfileTributeMood.quiet => const _TributePalette(
        deep: Color(0xFF101622),
        glow: Color(0xFF9BB8FF),
        accent: Color(0xFF646B7A),
      ),
    };
  }
}
