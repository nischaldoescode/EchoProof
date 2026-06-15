// echo signal game
// @params none

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:provider/provider.dart';

import '../../../../app/theme/colors.dart';
import '../../../../app/theme/spacing.dart';
import '../../../../app/theme/typography.dart';
import '../../../../core/services/ad_service.dart';
import '../../../../core/utils/app_haptics.dart';
import '../../../../shared/widgets/app_banner_ad.dart';
import '../../../../shared/widgets/rating_prompt.dart';
import '../../../subscription/presentation/services/subscription_service.dart';
import '../services/signal_drift_score_service.dart';

const _fieldBase = Color(0xFFFCFBF7);
const _fieldInk = Color(0xFF284F43);
const _fieldSignal = Color(0xFF477665);
const _fieldHighlight = Color(0xFFB88A4A);
const _fieldDanger = Color(0xFFC97967);
const _fieldMist = Color(0xFFEFF5EF);

class _SignalFieldTheme {
  const _SignalFieldTheme({
    required this.name,
    required this.unlockAt,
    required this.base,
    required this.mist,
    required this.ink,
    required this.signal,
    required this.highlight,
    required this.danger,
    required this.text,
    required this.dark,
  });

  final String name;
  final int unlockAt;
  final Color base;
  final Color mist;
  final Color ink;
  final Color signal;
  final Color highlight;
  final Color danger;
  final Color text;
  final bool dark;
}

const _fieldThemes = [
  _SignalFieldTheme(
    name: 'quiet field',
    unlockAt: 0,
    base: _fieldBase,
    mist: _fieldMist,
    ink: _fieldInk,
    signal: _fieldSignal,
    highlight: _fieldHighlight,
    danger: _fieldDanger,
    text: _fieldInk,
    dark: false,
  ),
  _SignalFieldTheme(
    name: 'forest archive',
    unlockAt: 80,
    base: Color(0xFFF3F7F1),
    mist: Color(0xFFE2EBE2),
    ink: Color(0xFF24493F),
    signal: Color(0xFF66816F),
    highlight: Color(0xFFA7864B),
    danger: Color(0xFFC17869),
    text: Color(0xFF233F38),
    dark: false,
  ),
  _SignalFieldTheme(
    name: 'night signal',
    unlockAt: 180,
    base: Color(0xFF101A18),
    mist: Color(0xFF182724),
    ink: Color(0xFFDDE8E1),
    signal: Color(0xFF86A99A),
    highlight: Color(0xFFC4A76D),
    danger: Color(0xFFD08476),
    text: Color(0xFFEAF2EE),
    dark: true,
  ),
  _SignalFieldTheme(
    name: 'deep archive',
    unlockAt: 320,
    base: Color(0xFF0E0E0C),
    mist: Color(0xFF1B1A14),
    ink: Color(0xFFE8DFBD),
    signal: Color(0xFFD0B66E),
    highlight: Color(0xFFF0D58A),
    danger: Color(0xFFC97967),
    text: Color(0xFFF4EBC8),
    dark: true,
  ),
];

// keeps the game close to echoproof without using the main app green exactly
class EchoSignalGameScreen extends StatefulWidget {
  const EchoSignalGameScreen({super.key});

  @override
  State<EchoSignalGameScreen> createState() => _EchoSignalGameScreenState();
}

class _EchoSignalGameScreenState extends State<EchoSignalGameScreen>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  static const _kGameRoundsSinceAd = 'signal_drift_rounds_since_ad';
  static const _kGameLastAdMs = 'signal_drift_last_ad_ms';
  static const _kGameReviewSeen = 'signal_drift_review_seen';
  static const _kSignalFragments = 'signal_drift_fragments';
  static const _kDailyDonePrefix = 'signal_drift_daily_done_';
  static const _gameAdEveryRounds = 2;
  static const _gameAdCooldown = Duration(minutes: 4);

  late final AnimationController _ticker;
  late final SignalDriftScoreService _scoreService;
  final _rng = math.Random();
  final List<Offset> _trail = [];
  final List<_GameParticle> _particles = [];
  final List<_SignalReflector> _reflectors = [];
  final List<_SignalReflectorPlan> _reflectorPlans = [];

  Size _arena = Size.zero;
  Offset _signal = Offset.zero;
  Offset _velocity = Offset.zero;
  double _paddleCenter = 0.5;
  int _score = 0;
  int _combo = 0;
  int _perfectStreak = 0;
  int _highScore = 0;
  int _focus = 0;
  int _fragments = 0;
  int _fragmentsEarned = 0;
  bool _started = false;
  bool _ended = false;
  bool _paused = false;
  bool _submittingScore = false;
  bool _reviewCompleted = true;
  bool _scoreSubmitted = false;
  bool _dailyCompletedThisRun = false;
  bool _liteMode = false;
  int _runToken = 0;
  int _slowFrameScore = 0;
  DateTime? _lastTick;
  DateTime? _runStartedAt;
  DateTime? _lastFeedbackAt;
  String? _fieldNote;
  String? _unlockedFieldThisRun;
  DateTime? _fieldNoteUntil;
  DateTime? _focusModeUntil;
  DateTime? _hitFlashUntil;
  DateTime? _shakeUntil;
  bool _nearMissMarked = false;
  SignalDriftScoreResult? _lastScoreResult;

  bool get _isPlaying => _started && !_ended && !_paused;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _scoreService = SignalDriftScoreService();
    _highScore = _scoreService.localHighScore;
    unawaited(_loadScoreState());
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _prepareGameBreakAd();
    });
    _ticker =
        AnimationController(
            vsync: this,
            duration: const Duration(milliseconds: 1000),
          )
          ..addListener(_tick)
          ..repeat();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _ticker.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed && _isPlaying) {
      setState(() {
        _paused = true;
        _lastTick = null;
      });
    }
  }

  Future<void> _loadScoreState() async {
    final reviewCompleted = await RatingPrompt.hasCompletedReview();
    final best = await _scoreService.loadBestScore();
    final fragments =
        Hive.box('app_settings').get(_kSignalFragments, defaultValue: 0) as int;
    if (!mounted) return;
    setState(() {
      _reviewCompleted = reviewCompleted;
      _highScore = best;
      _fragments = fragments;
    });
  }

  void _trackFrameHealth(double dt) {
    if (dt >= 0.028) {
      _slowFrameScore = math.min(40, _slowFrameScore + 2);
    } else {
      _slowFrameScore = math.max(0, _slowFrameScore - 1);
    }
    if (_slowFrameScore >= 18) {
      _liteMode = true;
    }
  }

  double _arenaDifficulty(Size size) {
    if (size == Size.zero) return 1;
    final widthFactor = ((size.width - 390) / 390).clamp(0.0, 1.0).toDouble();
    final heightFactor = ((size.height - 640) / 360).clamp(0.0, 1.0).toDouble();
    return 1 + widthFactor * 0.14 + heightFactor * 0.10;
  }

  double _speedDifficulty(Size size) {
    if (size == Size.zero) return 1;
    final compactWidth = ((390 - size.width) / 120).clamp(0.0, 1.0).toDouble();
    final compactHeight = ((640 - size.height) / 220)
        .clamp(0.0, 1.0)
        .toDouble();
    final widePressure = ((size.width - 520) / 360).clamp(0.0, 1.0).toDouble();
    final tallPressure = ((size.height - 780) / 420).clamp(0.0, 1.0).toDouble();
    return (_arenaDifficulty(size) +
            compactWidth * 0.28 +
            compactHeight * 0.16 +
            widePressure * 0.56 +
            tallPressure * 0.38)
        .clamp(1.22, 2.24)
        .toDouble();
  }

  List<_SignalReflectorPlan> _createReflectorPlans(Size size) {
    final difficulty = _speedDifficulty(size);
    final largeShift = ((difficulty - 1) * 16).round();
    final wideArena = size.width >= 520 || size.height >= 760;
    const patterns = <List<Offset>>[
      [
        Offset(0.31, 0.43),
        Offset(0.69, 0.61),
        Offset(0.50, 0.34),
        Offset(0.53, 0.53),
      ],
      [
        Offset(0.57, 0.39),
        Offset(0.28, 0.58),
        Offset(0.71, 0.47),
        Offset(0.45, 0.66),
      ],
      [
        Offset(0.42, 0.52),
        Offset(0.72, 0.37),
        Offset(0.30, 0.66),
        Offset(0.58, 0.55),
      ],
      [
        Offset(0.66, 0.49),
        Offset(0.35, 0.34),
        Offset(0.52, 0.64),
        Offset(0.76, 0.58),
      ],
    ];
    final pattern = patterns[_rng.nextInt(patterns.length)];
    final mirror = _rng.nextBool();

    _SignalReflectorPlan plan({
      required int id,
      required int baseUnlock,
      required int variance,
      required Offset anchor,
      required double widthFactor,
      required double maxWidth,
      required double drift,
    }) {
      final jitter = _rng.nextInt(variance + 1);
      final unlock = math.max(3, baseUnlock + jitter - largeShift);
      final baseX = mirror ? 1 - anchor.dx : anchor.dx;
      return _SignalReflectorPlan(
        id: id,
        unlockScore: unlock,
        x: (baseX + (_rng.nextDouble() - 0.5) * 0.16)
            .clamp(0.22, 0.78)
            .toDouble(),
        y: (anchor.dy + (_rng.nextDouble() - 0.5) * 0.14)
            .clamp(0.30, 0.70)
            .toDouble(),
        widthFactor: widthFactor,
        maxWidth: maxWidth,
        drift: drift * (0.88 + _rng.nextDouble() * 0.38),
      );
    }

    return [
      plan(
        id: 1,
        baseUnlock: 3,
        variance: 6,
        anchor: pattern[0],
        widthFactor: 0.27,
        maxWidth: 144,
        drift: 0.024,
      ),
      plan(
        id: 2,
        baseUnlock: 10,
        variance: 7,
        anchor: pattern[1],
        widthFactor: 0.24,
        maxWidth: 128,
        drift: 0.026,
      ),
      plan(
        id: 3,
        baseUnlock: 19,
        variance: 9,
        anchor: pattern[2],
        widthFactor: 0.20,
        maxWidth: 112,
        drift: 0.021,
      ),
      if (wideArena)
        plan(
          id: 4,
          baseUnlock: 14,
          variance: 11,
          anchor: pattern[3],
          widthFactor: 0.18,
          maxWidth: 106,
          drift: 0.019,
        ),
    ];
  }

  void _start(Size size) {
    if (size.width <= 0 || size.height <= 0) return;
    unawaited(AppHaptics.gameStart());
    final difficulty = _speedDifficulty(size);
    setState(() {
      _arena = size;
      _runToken++;
      _signal = Offset(size.width * 0.5, size.height * 0.34);
      _velocity = Offset(
        (_rng.nextBool() ? 1 : -1) *
            (252 + _rng.nextDouble() * 112) *
            difficulty,
        -364 * difficulty,
      );
      _paddleCenter = 0.5;
      _score = 0;
      _combo = 0;
      _perfectStreak = 0;
      _focus = 0;
      _fragmentsEarned = 0;
      _started = true;
      _ended = false;
      _paused = false;
      _submittingScore = false;
      _scoreSubmitted = false;
      _dailyCompletedThisRun = false;
      _liteMode = false;
      _slowFrameScore = 0;
      _lastScoreResult = null;
      _unlockedFieldThisRun = null;
      _fieldNote = _dailyCompleted ? _fieldName : _dailyPrompt;
      _fieldNoteUntil = DateTime.now().add(const Duration(milliseconds: 1400));
      _focusModeUntil = null;
      _hitFlashUntil = null;
      _shakeUntil = null;
      _nearMissMarked = false;
      _trail.clear();
      _particles.clear();
      _reflectors.clear();
      _reflectorPlans
        ..clear()
        ..addAll(_createReflectorPlans(size));
      _runStartedAt = DateTime.now();
      _lastTick = DateTime.now();
    });
    _prepareGameBreakAd();
  }

  void _prepareGameBreakAd() {
    final subscription = context.read<SubscriptionService>();
    final adService = context.read<AdService>();
    if (subscription.isPro || adService.isAdFreeActive) return;
    adService.loadRewardedInterstitial();
  }

  // advances physics and keeps active play free of heavy hud noise
  void _tick() {
    if (!_isPlaying || _arena == Size.zero) {
      _lastTick = DateTime.now();
      return;
    }

    final now = DateTime.now();
    final last = _lastTick ?? now;
    _lastTick = now;
    final dt = (now.difference(last).inMicroseconds / 1000000)
        .clamp(0.0, 0.032)
        .toDouble();
    if (dt <= 0) return;
    _trackFrameHealth(dt);
    final focusActive = _isFocusActiveAt(now);
    final effectiveDt = focusActive ? dt * 0.86 : dt;

    final radius = _signalRadius;
    final paddleWidth = _paddleWidth(_arena.width);
    final paddleY = _arena.height - 76;
    final paddleX = _paddleCenter * _arena.width;
    var velocity = _velocity;
    var signal = _signal;
    var score = _score;
    var combo = _combo;
    var perfectStreak = _perfectStreak;
    var focus = _focus;
    var ended = false;

    _syncReflectors(score);

    if (score >= 45) {
      final drift = math.sin(now.millisecondsSinceEpoch / 210.0) * 13 * dt;
      velocity = Offset(velocity.dx + drift, velocity.dy);
    }

    final physics = _advanceSignal(
      now: now,
      signal: signal,
      velocity: velocity,
      dt: effectiveDt,
      radius: radius,
    );
    signal = physics.signal;
    velocity = physics.velocity;
    if (physics.hit) {
      _softClick();
      unawaited(AppHaptics.gameReflector());
    }

    final paddleHit =
        velocity.dy > 0 &&
        _signal.dy <= paddleY &&
        signal.dy + radius >= paddleY &&
        (signal.dx - paddleX).abs() <= paddleWidth / 2 + radius;
    final crossedPaddle =
        velocity.dy > 0 &&
        _signal.dy <= paddleY &&
        signal.dy + radius >= paddleY;

    if (paddleHit) {
      final offset = ((signal.dx - paddleX) / (paddleWidth / 2))
          .clamp(-1.0, 1.0)
          .toDouble();
      final isPerfect = offset.abs() <= 0.16;
      combo = isPerfect ? combo + 1 : math.max(0, combo - 1);
      perfectStreak = isPerfect ? perfectStreak + 1 : 0;
      focus = math.min(100, focus + (isPerfect ? 24 : 7));
      final focusBonus = focusActive ? 2 : 0;
      score += 1 + (isPerfect ? 1 : 0) + (combo >= 4 ? 1 : 0) + focusBonus;
      final difficulty = _speedDifficulty(_arena);
      final speedUp = math.min(
        1.38 + score * 0.016 + (difficulty - 1) * 0.62,
        2.24,
      );
      velocity = _capVelocity(
        Offset(
          offset * (318 + score * 10.4) * math.min(difficulty, 1.34),
          -velocity.dy.abs() * speedUp,
        ),
      );
      signal = Offset(signal.dx, paddleY - radius - 1);
      _burst(signal, isPerfect: isPerfect);
      _syncReflectors(score);
      _maybeFieldNote(score, combo, perfectStreak, isPerfect, focus);
      _hitFlashUntil = DateTime.now().add(const Duration(milliseconds: 90));
      _nearMissMarked = false;
      if (focus >= 100 && !focusActive) {
        _focusModeUntil = now.add(const Duration(seconds: 10));
        _shakeUntil = now.add(const Duration(milliseconds: 160));
        _setFieldNote('focus mode');
        unawaited(AppHaptics.gameFocus());
      }
      if (isPerfect || combo >= 4) {
        _shakeUntil = now.add(const Duration(milliseconds: 110));
      }
      _softClick();
      unawaited(AppHaptics.gamePaddle(perfect: isPerfect, combo: combo));
    } else if (crossedPaddle && !_nearMissMarked) {
      final edgeDistance = (signal.dx - paddleX).abs() - (paddleWidth / 2);
      if (edgeDistance > radius && edgeDistance <= radius + 7) {
        _nearMissMarked = true;
        _setFieldNote('close');
        unawaited(AppHaptics.gameNearMiss());
      }
    }

    if (signal.dy > _arena.height + radius) {
      ended = true;
      _softAlert();
      unawaited(AppHaptics.gameOver());
    }

    if (!ended) {
      velocity = _capVelocity(velocity);
    }

    setState(() {
      _signal = signal;
      _velocity = velocity;
      _score = score;
      _combo = combo;
      _perfectStreak = perfectStreak;
      _focus = focusActive && !ended ? focus : focus.clamp(0, 100).toInt();
      _ended = ended;
      _highScore = math.max(_highScore, score);
      _trail.add(signal);
      if (_trail.length > 12) _trail.removeAt(0);
      _ageParticles(dt);
      if (_fieldNoteUntil != null && now.isAfter(_fieldNoteUntil!)) {
        _fieldNote = null;
        _fieldNoteUntil = null;
      }
      if (_focusModeUntil != null && now.isAfter(_focusModeUntil!)) {
        _focusModeUntil = null;
        _focus = 0;
      }
      if (_hitFlashUntil != null && now.isAfter(_hitFlashUntil!)) {
        _hitFlashUntil = null;
      }
      if (_shakeUntil != null && now.isAfter(_shakeUntil!)) {
        _shakeUntil = null;
      }
    });

    if (ended && !_scoreSubmitted) {
      _scoreSubmitted = true;
      unawaited(_finishRun());
    }
  }

  void _syncReflectors(int score) {
    if (_arena == Size.zero) return;

    final width = _arena.width;
    final height = _arena.height;
    final barHeight = width < 390 ? 9.0 : 11.0;
    final targets = <_SignalReflectorSpec>[];
    if (_reflectorPlans.isEmpty) {
      _reflectorPlans.addAll(_createReflectorPlans(_arena));
    }
    final seconds = DateTime.now().millisecondsSinceEpoch / 1000.0;

    Offset center(double x, double y) {
      return Offset(
        (width * x).clamp(58.0, width - 58).toDouble(),
        (height * y).clamp(112.0, height - 148).toDouble(),
      );
    }

    for (final plan in _reflectorPlans) {
      if (score < plan.unlockScore) continue;
      if (plan.id == 3 && width < 340) continue;
      final liveShift = ((score - plan.unlockScore + 1) / 8)
          .clamp(0.0, 1.0)
          .toDouble();
      final phase = seconds * 0.45 + plan.id * 1.7;
      final dx = math.sin(phase) * plan.drift * liveShift;
      final dy = math.cos(phase * 0.8) * plan.drift * 0.45 * liveShift;
      targets.add(
        _SignalReflectorSpec(
          id: plan.id,
          unlockScore: plan.unlockScore,
          center: center(plan.x + dx, plan.y + dy),
          size: Size(
            math.min(width * plan.widthFactor, plan.maxWidth),
            barHeight,
          ),
        ),
      );
    }

    final previousCount = _reflectors.length;
    final activeIds = targets.map((target) => target.id).toSet();
    _reflectors.removeWhere((reflector) => !activeIds.contains(reflector.id));

    for (final target in targets) {
      var targetCenter = target.center;
      if ((targetCenter - _signal).distance < 58) {
        targetCenter = Offset(
          targetCenter.dx,
          (targetCenter.dy - 52).clamp(112.0, height - 148).toDouble(),
        );
      }

      _SignalReflector? existing;
      for (final reflector in _reflectors) {
        if (reflector.id == target.id) {
          existing = reflector;
          break;
        }
      }

      if (existing == null) {
        _reflectors.add(
          _SignalReflector(
            id: target.id,
            unlockScore: target.unlockScore,
            center: targetCenter,
            size: target.size,
          ),
        );
      } else {
        existing.center = targetCenter;
        existing.size = target.size;
      }
    }

    if (_reflectors.length > previousCount && _started && !_ended) {
      _setFieldNote(
        _reflectors.length == 1 ? 'field reflects' : 'field shifts',
      );
    }
  }

  _ReflectorHit _advanceSignal({
    required DateTime now,
    required Offset signal,
    required Offset velocity,
    required double dt,
    required double radius,
  }) {
    final travel = velocity.distance * dt;
    final maxStep = math.max(0.65, radius * 0.055);
    final stepCap = _liteMode ? 140 : 220;
    final steps = travel <= maxStep
        ? 1
        : math.min(stepCap, math.max(2, (travel / maxStep).ceil()));
    final stepDt = dt / steps;
    var currentSignal = signal;
    var currentVelocity = velocity;
    var didHit = false;

    // small steps stop fast frames from skipping thin reflectors
    for (var i = 0; i < steps; i++) {
      final previous = currentSignal;
      currentSignal = previous + currentVelocity * stepDt;

      if (currentSignal.dx <= radius) {
        currentSignal = Offset(radius, currentSignal.dy);
        currentVelocity = Offset(currentVelocity.dx.abs(), currentVelocity.dy);
      } else if (currentSignal.dx >= _arena.width - radius) {
        currentSignal = Offset(_arena.width - radius, currentSignal.dy);
        currentVelocity = Offset(-currentVelocity.dx.abs(), currentVelocity.dy);
      }

      if (currentSignal.dy <= radius) {
        currentSignal = Offset(currentSignal.dx, radius);
        currentVelocity = Offset(currentVelocity.dx, currentVelocity.dy.abs());
      }

      final reflectorHit = _resolveReflectorHit(
        now: now,
        previous: previous,
        signal: currentSignal,
        velocity: currentVelocity,
        radius: radius,
      );
      currentSignal = reflectorHit.signal;
      currentVelocity = reflectorHit.velocity;
      didHit = didHit || reflectorHit.hit;
    }

    return _ReflectorHit(
      signal: currentSignal,
      velocity: currentVelocity,
      hit: didHit,
    );
  }

  _ReflectorHit _resolveReflectorHit({
    required DateTime now,
    required Offset previous,
    required Offset signal,
    required Offset velocity,
    required double radius,
  }) {
    for (final reflector in _reflectors) {
      final lastHit = reflector.lastHitAt;
      if (lastHit != null && now.difference(lastHit).inMilliseconds < 20) {
        final stillSeparating = reflector.rect
            .inflate(radius + 14)
            .contains(previous);
        final movingBackIn = _movingTowardRect(
          previous,
          velocity,
          reflector.rect,
        );
        if (!stillSeparating || movingBackIn) {
          reflector.lastHitAt = null;
        }
      }
      if (lastHit != null &&
          reflector.lastHitAt != null &&
          now.difference(lastHit).inMilliseconds < 20) {
        continue;
      }

      final rect = reflector.rect;
      final expandedRect = rect.inflate(radius + 18);
      final sweepHit =
          _segmentRectHit(previous, signal, expandedRect) ??
          _segmentBandHit(previous, signal, expandedRect);
      final hitPath = expandedRect.contains(signal) || sweepHit != null;
      if (!hitPath) continue;

      var nextSignal = signal;
      var nextVelocity = velocity;
      final hitNormal = sweepHit?.normal;

      if (hitNormal != null && hitNormal.dy < 0) {
        nextSignal = Offset(
          previous.dx + (signal.dx - previous.dx) * sweepHit!.time,
          rect.top - radius - 1,
        );
        nextVelocity = Offset(velocity.dx, -velocity.dy.abs());
      } else if (hitNormal != null && hitNormal.dy > 0) {
        nextSignal = Offset(
          previous.dx + (signal.dx - previous.dx) * sweepHit!.time,
          rect.bottom + radius + 1,
        );
        nextVelocity = Offset(velocity.dx, velocity.dy.abs());
      } else if (hitNormal != null && hitNormal.dx < 0) {
        nextSignal = Offset(
          rect.left - radius - 1,
          previous.dy + (signal.dy - previous.dy) * sweepHit!.time,
        );
        nextVelocity = Offset(-velocity.dx.abs(), velocity.dy);
      } else if (hitNormal != null && hitNormal.dx > 0) {
        nextSignal = Offset(
          rect.right + radius + 1,
          previous.dy + (signal.dy - previous.dy) * sweepHit!.time,
        );
        nextVelocity = Offset(velocity.dx.abs(), velocity.dy);
      } else {
        final xWeight = ((signal.dx - rect.center.dx).abs() / (rect.width / 2))
            .toDouble();
        final yWeight = ((signal.dy - rect.center.dy).abs() / (rect.height / 2))
            .toDouble();
        if (yWeight >= xWeight) {
          final direction = signal.dy < rect.center.dy ? -1.0 : 1.0;
          nextSignal = Offset(
            signal.dx,
            direction < 0 ? rect.top - radius - 1 : rect.bottom + radius + 1,
          );
          nextVelocity = Offset(
            velocity.dx,
            direction < 0 ? -velocity.dy.abs() : velocity.dy.abs(),
          );
        } else {
          final direction = signal.dx < rect.center.dx ? -1.0 : 1.0;
          nextSignal = Offset(
            direction < 0 ? rect.left - radius - 1 : rect.right + radius + 1,
            signal.dy,
          );
          nextVelocity = Offset(
            direction < 0 ? -velocity.dx.abs() : velocity.dx.abs(),
            velocity.dy,
          );
        }
      }

      final bias = ((signal.dx - rect.center.dx) / (rect.width / 2))
          .clamp(-1.0, 1.0)
          .toDouble();
      nextVelocity = _capVelocity(
        Offset(nextVelocity.dx + bias * 72, nextVelocity.dy),
      );
      reflector.lastHitAt = now;
      reflector.hitUntil = now.add(const Duration(milliseconds: 150));
      _reflectorBurst(nextSignal);
      if (_fieldNote == null) {
        _setFieldNote('deflected');
      }
      return _ReflectorHit(
        signal: nextSignal,
        velocity: nextVelocity,
        hit: true,
      );
    }

    return _ReflectorHit(signal: signal, velocity: velocity, hit: false);
  }

  _SegmentRectHit? _segmentRectHit(Offset start, Offset end, Rect rect) {
    final delta = end - start;
    var tMin = 0.0;
    var tMax = 1.0;
    var normal = Offset.zero;

    bool axis({
      required double startValue,
      required double deltaValue,
      required double min,
      required double max,
      required Offset nearNormal,
      required Offset farNormal,
    }) {
      if (deltaValue.abs() < 0.0001) {
        return startValue >= min && startValue <= max;
      }

      var near = (min - startValue) / deltaValue;
      var far = (max - startValue) / deltaValue;
      var nearSide = nearNormal;
      var farSide = farNormal;
      if (near > far) {
        final tmp = near;
        near = far;
        far = tmp;
        final tmpSide = nearSide;
        nearSide = farSide;
        farSide = tmpSide;
      }

      if (near > tMin) {
        tMin = near;
        normal = nearSide;
      }
      if (far < tMax) {
        tMax = far;
      }
      return tMin <= tMax;
    }

    final hitX = axis(
      startValue: start.dx,
      deltaValue: delta.dx,
      min: rect.left,
      max: rect.right,
      nearNormal: const Offset(-1, 0),
      farNormal: const Offset(1, 0),
    );
    if (!hitX) return null;
    final hitY = axis(
      startValue: start.dy,
      deltaValue: delta.dy,
      min: rect.top,
      max: rect.bottom,
      nearNormal: const Offset(0, -1),
      farNormal: const Offset(0, 1),
    );
    if (!hitY || tMin < 0 || tMin > 1) return null;
    return _SegmentRectHit(tMin, normal);
  }

  _SegmentRectHit? _segmentBandHit(Offset start, Offset end, Rect rect) {
    final delta = end - start;
    _SegmentRectHit? best;

    void consider(double t, Offset normal) {
      if (t < 0 || t > 1) return;
      final point = start + delta * t;
      if (!rect.contains(point)) return;
      if (best == null || t < best!.time) {
        best = _SegmentRectHit(t, normal);
      }
    }

    // fallback for very fast frames crossing a thin reflector band
    if (delta.dy.abs() > 0.0001) {
      consider((rect.top - start.dy) / delta.dy, const Offset(0, -1));
      consider((rect.bottom - start.dy) / delta.dy, const Offset(0, 1));
    }
    if (delta.dx.abs() > 0.0001) {
      consider((rect.left - start.dx) / delta.dx, const Offset(-1, 0));
      consider((rect.right - start.dx) / delta.dx, const Offset(1, 0));
    }
    return best;
  }

  bool _movingTowardRect(Offset point, Offset velocity, Rect rect) {
    final nearest = Offset(
      point.dx.clamp(rect.left, rect.right).toDouble(),
      point.dy.clamp(rect.top, rect.bottom).toDouble(),
    );
    final toRect = nearest - point;
    if (toRect.distanceSquared <= 0.01) return true;
    return velocity.dx * toRect.dx + velocity.dy * toRect.dy > 0;
  }

  Offset _capVelocity(Offset velocity) {
    final difficulty = _speedDifficulty(_arena);
    final baseMaxSpeed = _liteMode ? 820.0 : 1020.0;
    final maxSpeed = math.min(
      baseMaxSpeed * difficulty,
      _liteMode ? 1040.0 : 1480.0,
    );
    final speed = velocity.distance;
    var capped = speed > maxSpeed ? velocity * (maxSpeed / speed) : velocity;
    final minVertical = 224.0 * math.min(difficulty, 1.36);
    if (capped.dy.abs() < minVertical) {
      final direction = capped.dy < 0 ? -1.0 : 1.0;
      capped = Offset(capped.dx, direction * minVertical);
    }
    return capped;
  }

  void _ageParticles(double dt) {
    for (final particle in _particles) {
      particle.age += dt;
      particle.position += particle.velocity * dt;
      particle.velocity *= 0.94;
    }
    _particles.removeWhere((particle) => particle.age >= particle.life);
  }

  void _burst(Offset origin, {required bool isPerfect}) {
    final amount = _liteMode
        ? isPerfect
              ? 4
              : 2
        : isPerfect
        ? 8
        : 4;
    final color = isPerfect ? _fieldTheme.highlight : _accent;
    for (var i = 0; i < amount; i++) {
      final angle = _rng.nextDouble() * math.pi * 2;
      final speed = (isPerfect ? 92 : 58) + _rng.nextDouble() * 70;
      _particles.add(
        _GameParticle(
          position: origin,
          velocity: Offset(math.cos(angle) * speed, math.sin(angle) * speed),
          color: color,
          life: isPerfect ? 0.58 : 0.38,
          size: isPerfect ? 3.0 : 2.2,
        ),
      );
    }
  }

  void _reflectorBurst(Offset origin) {
    if (_liteMode) return;
    for (var i = 0; i < 3; i++) {
      final angle = -math.pi / 2 + (i - 1) * 0.55;
      final speed = 42 + _rng.nextDouble() * 38;
      _particles.add(
        _GameParticle(
          position: origin,
          velocity: Offset(math.cos(angle) * speed, math.sin(angle) * speed),
          color: _fieldTheme.signal,
          life: 0.28,
          size: 2.0,
        ),
      );
    }
  }

  void _maybeFieldNote(
    int score,
    int combo,
    int perfectStreak,
    bool isPerfect,
    int focus,
  ) {
    if (focus >= 100 && !_isFocusActiveAt(DateTime.now())) {
      _setFieldNote('focus mode');
    } else if (perfectStreak >= 7) {
      _setFieldNote('impossible');
    } else if (perfectStreak >= 5) {
      _setFieldNote('on fire');
    } else if (perfectStreak >= 3) {
      _setFieldNote('locked in');
    } else if (perfectStreak == 2) {
      _setFieldNote('perfect x2');
    } else if (combo >= 6) {
      _setFieldNote('locked in');
    } else if (score == 14) {
      _setFieldNote('field tightens');
    } else if (score == 25) {
      _setFieldNote('smaller signal');
    } else if (score == 45) {
      _setFieldNote('quiet drift');
    } else if (isPerfect) {
      _setFieldNote('perfect');
    }
  }

  void _setFieldNote(String note) {
    _fieldNote = note;
    _fieldNoteUntil = DateTime.now().add(const Duration(milliseconds: 900));
  }

  bool _isFocusActiveAt(DateTime now) {
    final until = _focusModeUntil;
    return until != null && now.isBefore(until);
  }

  void _softClick() {
    if (!_canPlayFeedback()) return;
    unawaited(SystemSound.play(SystemSoundType.click));
  }

  void _softAlert() {
    if (!_canPlayFeedback(minGapMs: 180)) return;
    unawaited(SystemSound.play(SystemSoundType.alert));
  }

  bool _canPlayFeedback({int minGapMs = 80}) {
    final now = DateTime.now();
    final last = _lastFeedbackAt;
    final gap = _liteMode ? math.max(minGapMs, 140) : minGapMs;
    if (last != null && now.difference(last).inMilliseconds < gap) {
      return false;
    }
    _lastFeedbackAt = now;
    return true;
  }

  // stores local progression while the server validates only the best score
  Future<void> _awardProgress(int score, int token) async {
    if (score <= 0) return;

    final box = Hive.box('app_settings');
    final todayKey = '$_kDailyDonePrefix$_dailyKey';
    final dailyWasDone = box.get(todayKey, defaultValue: false) as bool;
    final completedDaily = !dailyWasDone && score >= _dailyTarget;
    final previousFragments =
        box.get(_kSignalFragments, defaultValue: 0) as int;
    final oldField = _fieldThemeForFragments(previousFragments);
    final earned = math.max(1, score ~/ 5) + (completedDaily ? 50 : 0);
    final fragments = previousFragments + earned;
    final newField = _fieldThemeForFragments(fragments);

    await box.put(_kSignalFragments, fragments);
    if (completedDaily) {
      await box.put(todayKey, true);
    }
    if (!mounted) return;

    setState(() {
      _fragments = fragments;
      if (token == _runToken) {
        _fragmentsEarned = earned;
        _dailyCompletedThisRun = completedDaily;
        _unlockedFieldThisRun = oldField.name == newField.name
            ? null
            : newField.name;
      }
    });
  }

  Future<void> _finishRun() async {
    final token = _runToken;
    final score = _score;
    final started = _runStartedAt;
    final runMs = started == null
        ? 0
        : DateTime.now().difference(started).inMilliseconds;
    setState(() => _submittingScore = true);
    await _awardProgress(score, token);
    final result = await _scoreService.submitScore(score: score, runMs: runMs);
    if (!mounted || token != _runToken) return;
    setState(() {
      _lastScoreResult = result;
      _highScore = math.max(_highScore, result.highScore);
      _submittingScore = false;
    });
    unawaited(_maybeShowGameBreakAd());
  }

  Future<void> _maybeShowGameBreakAd() async {
    // ads are only attempted after a completed round
    await Future<void>.delayed(const Duration(milliseconds: 650));
    if (!mounted || !_ended) return;
    final route = ModalRoute.of(context);
    if (route != null && !route.isCurrent) return;

    final subscription = context.read<SubscriptionService>();
    final adService = context.read<AdService>();
    if (subscription.isPro || adService.isAdFreeActive) return;

    final box = Hive.box('app_settings');
    final rounds = (box.get(_kGameRoundsSinceAd, defaultValue: 0) as int) + 1;
    final lastAdMs = box.get(_kGameLastAdMs) as int?;
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    await box.put(_kGameRoundsSinceAd, rounds);

    final recentlyShown =
        lastAdMs != null && nowMs - lastAdMs < _gameAdCooldown.inMilliseconds;
    if (rounds < _gameAdEveryRounds || recentlyShown) {
      adService.loadRewardedInterstitial();
      return;
    }

    if (!adService.canShowInterstitial) {
      adService.loadRewardedInterstitial();
      return;
    }

    final shown = await adService.showRewardedInterstitial(
      grantAdFreeReward: false,
      onRewarded: () {},
    );
    if (shown) {
      await box.put(_kGameRoundsSinceAd, 0);
      await box.put(_kGameLastAdMs, nowMs);
    }
  }

  void _setPaddle(Offset localPosition) {
    if (_arena.width <= 0) return;
    if (_ended) return;
    if (!_started) {
      _start(_arena);
    }
    setState(() {
      _paddleCenter = (localPosition.dx / _arena.width)
          .clamp(0.08, 0.92)
          .toDouble();
    });
  }

  Future<void> _handleBackIntent() async {
    // active runs pause before navigation
    if (!_isPlaying) {
      Navigator.of(context).maybePop();
      return;
    }

    setState(() => _paused = true);
    final leave = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: Colors.white,
      builder: (context) => _ExitSheet(
        onResume: () => Navigator.pop(context, false),
        onLeave: () => Navigator.pop(context, true),
      ),
    );

    if (!mounted) return;
    if (leave == true) {
      Navigator.of(context).maybePop();
    } else if (_started && !_ended) {
      setState(() {
        _paused = false;
        _lastTick = DateTime.now();
      });
    }
  }

  Future<void> _reviewApp() async {
    final box = Hive.box('app_settings');
    await box.put(_kGameReviewSeen, true);
    if (!mounted) return;
    await RatingPrompt.showNow(context);
    final completed = await RatingPrompt.hasCompletedReview();
    if (!mounted) return;
    setState(() => _reviewCompleted = completed);
  }

  double get _signalRadius {
    if (_score >= 45) return 10.5;
    if (_score >= 25) return 11.5;
    return 13;
  }

  double _paddleWidth(double width) {
    final base = width.clamp(320.0, 760.0).toDouble() * 0.25;
    final difficulty = _arena == Size.zero
        ? 1.0
        : _arenaDifficulty(Size(width, _arena.height));
    final scoreScale = switch (_score) {
      >= 65 => 0.64,
      >= 44 => 0.70,
      >= 26 => 0.76,
      >= 14 => 0.84,
      >= 6 => 0.92,
      _ => 1.0,
    };
    final fieldEase = _fragments >= 180 ? 0.03 : 0.0;
    final largeScreenPenalty = 1 - (difficulty - 1) * 0.82;
    return base *
        math.min(0.98, scoreScale + fieldEase) *
        largeScreenPenalty.clamp(0.80, 1.0).toDouble();
  }

  int get _phase {
    if (_score >= 29) return 2;
    if (_score >= 13) return 1;
    return 0;
  }

  Color get _accent {
    final theme = _fieldTheme;
    if (_isFocusActiveAt(DateTime.now())) return theme.highlight;
    if (_phase == 2) return theme.signal;
    if (_phase == 1) return theme.signal;
    return theme.ink;
  }

  _SignalFieldTheme get _fieldTheme => _fieldThemeForFragments(_fragments);

  _SignalFieldTheme _fieldThemeForFragments(int fragments) {
    var active = _fieldThemes.first;
    for (final theme in _fieldThemes) {
      if (fragments >= theme.unlockAt) {
        active = theme;
      }
    }
    return active;
  }

  String get _dailyKey {
    final now = DateTime.now();
    final month = now.month.toString().padLeft(2, '0');
    final day = now.day.toString().padLeft(2, '0');
    return '${now.year}$month$day';
  }

  int get _dailyTarget {
    final now = DateTime.now();
    final seed = now.year * 10000 + now.month * 100 + now.day;
    return 18 + (seed % 5) * 3;
  }

  bool get _dailyCompleted {
    final box = Hive.box('app_settings');
    return box.get('$_kDailyDonePrefix$_dailyKey', defaultValue: false) as bool;
  }

  String get _dailyPrompt => 'today: reach $_dailyTarget';

  String get _fieldName {
    return _fieldTheme.name;
  }

  String get _nextFieldText {
    for (final theme in _fieldThemes) {
      if (_fragments < theme.unlockAt) {
        return '${theme.unlockAt - _fragments} fragments to ${theme.name}';
      }
    }
    return 'all fields unlocked';
  }

  double get _hitPulse {
    final until = _hitFlashUntil;
    if (until == null) return 0;
    final remaining = until.difference(DateTime.now()).inMilliseconds;
    return (remaining / 90).clamp(0.0, 1.0).toDouble();
  }

  Offset get _screenShakeOffset {
    final until = _shakeUntil;
    if (until == null) return Offset.zero;
    final remaining = until.difference(DateTime.now()).inMilliseconds;
    final strength = (remaining / 160).clamp(0.0, 1.0).toDouble();
    final wave = math.sin(_ticker.value * math.pi * 18);
    return Offset(wave * 2.2 * strength, math.cos(wave) * 1.4 * strength);
  }

  bool get _showReviewButton {
    final box = Hive.box('app_settings');
    final seen = box.get(_kGameReviewSeen, defaultValue: false) as bool;
    return !_reviewCompleted && !seen && _score >= 10;
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_isPlaying,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        await _handleBackIntent();
      },
      child: Scaffold(
        backgroundColor: AppColors.white,
        body: SafeArea(
          child: Column(
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 260),
                curve: Curves.easeOutCubic,
                height: _isPlaying ? 0 : 58,
                child: ClipRect(
                  child: _GameTopBar(
                    onBack: () => Navigator.of(context).maybePop(),
                    onReset: _arena == Size.zero ? null : () => _start(_arena),
                  ),
                ),
              ),
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final width = math.min(constraints.maxWidth, 780.0);
                    final height = constraints.maxHeight.isFinite
                        ? constraints.maxHeight
                        : MediaQuery.sizeOf(context).height - 160;
                    final arenaSize = Size(width, math.max(height, 420));
                    final reduceMotion = MediaQuery.disableAnimationsOf(
                      context,
                    );
                    final renderLite = reduceMotion || _liteMode || width < 380;
                    final theme = _fieldTheme;
                    if (_arena != arenaSize && arenaSize.width > 0) {
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        if (!mounted) return;
                        setState(() {
                          _arena = arenaSize;
                          if (!_started || _ended) {
                            _signal = Offset(
                              arenaSize.width * 0.5,
                              arenaSize.height * 0.34,
                            );
                          }
                        });
                      });
                    }

                    return Center(
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onPanDown: (details) =>
                            _setPaddle(details.localPosition),
                        onPanUpdate: (details) =>
                            _setPaddle(details.localPosition),
                        onTap: () {
                          if (!_started) _start(arenaSize);
                        },
                        child: SizedBox(
                          width: width,
                          height: arenaSize.height,
                          child: Transform.translate(
                            offset: renderLite
                                ? Offset.zero
                                : _screenShakeOffset,
                            child: Stack(
                              children: [
                                Positioned.fill(
                                  child: CustomPaint(
                                    painter: _SignalGamePainter(
                                      signal: _signal,
                                      trail: _trail,
                                      particles: _particles,
                                      reflectors: _reflectors,
                                      paddleCenter: _paddleCenter,
                                      paddleWidth: _paddleWidth(width),
                                      accent: _accent,
                                      started: _started,
                                      ended: _ended,
                                      paused: _paused,
                                      score: _score,
                                      combo: _combo,
                                      phase: _phase,
                                      time: _ticker.value,
                                      hitPulse: renderLite ? 0 : _hitPulse,
                                      focusActive: _isFocusActiveAt(
                                        DateTime.now(),
                                      ),
                                      signalRadius: _signalRadius,
                                      theme: theme,
                                      renderLite: renderLite,
                                    ),
                                  ),
                                ),
                                if (_isPlaying)
                                  Positioned(
                                    left: AppSpacing.sm,
                                    top: AppSpacing.sm,
                                    child: _GhostBackButton(
                                      onTap: _handleBackIntent,
                                    ),
                                  ),
                                Positioned(
                                  left: AppSpacing.lg,
                                  top: AppSpacing.lg + (_isPlaying ? 42 : 0),
                                  child: _GamePill(
                                    label: 'score',
                                    value: '$_score',
                                    color: _accent,
                                    strong: true,
                                  ),
                                ),
                                if (_isPlaying)
                                  Positioned(
                                    right: AppSpacing.lg,
                                    top: AppSpacing.lg,
                                    child: _GamePill(
                                      label: 'best',
                                      value: '$_highScore',
                                      color: _fieldTheme.highlight,
                                    ),
                                  ),
                                if (_isPlaying)
                                  Positioned(
                                    left: width * 0.5 - 70,
                                    top: AppSpacing.xl,
                                    child: _FocusMeter(
                                      value: _focus,
                                      active: _isFocusActiveAt(DateTime.now()),
                                      color: _accent,
                                    ),
                                  )
                                else
                                  Positioned(
                                    right: AppSpacing.lg,
                                    top: AppSpacing.lg,
                                    child: _GamePill(
                                      label: 'best',
                                      value: '$_highScore',
                                      color: AppColors.charcoal,
                                    ),
                                  ),
                                if (_isPlaying && _fieldNote != null)
                                  Center(
                                    child: _ComboBurst(
                                      note: _fieldNote!,
                                      color: _accent,
                                    ),
                                  ),
                                if (!_started || _ended || _paused)
                                  Center(
                                    child: AnimatedSwitcher(
                                      duration: const Duration(
                                        milliseconds: 240,
                                      ),
                                      child: _GamePrompt(
                                        key: ValueKey('$_ended$_paused$_score'),
                                        ended: _ended,
                                        paused: _paused && !_ended,
                                        score: _score,
                                        highScore: _highScore,
                                        submitting: _submittingScore,
                                        result: _lastScoreResult,
                                        showReviewButton: _showReviewButton,
                                        fragments: _fragments,
                                        fragmentsEarned: _fragmentsEarned,
                                        dailyPrompt: _dailyPrompt,
                                        dailyCompletedThisRun:
                                            _dailyCompletedThisRun,
                                        fieldName: _fieldName,
                                        nextFieldText: _nextFieldText,
                                        unlockedField: _unlockedFieldThisRun,
                                        theme: theme,
                                        onRestart: () => _start(arenaSize),
                                        onResume: () {
                                          setState(() {
                                            _paused = false;
                                            _lastTick = DateTime.now();
                                          });
                                        },
                                        onReview: _reviewApp,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
              const AppBannerAd(),
            ],
          ),
        ),
      ),
    );
  }
}

class _GameParticle {
  _GameParticle({
    required this.position,
    required this.velocity,
    required this.color,
    required this.life,
    required this.size,
  });

  Offset position;
  Offset velocity;
  final Color color;
  final double life;
  final double size;
  double age = 0;
}

class _SignalReflectorPlan {
  const _SignalReflectorPlan({
    required this.id,
    required this.unlockScore,
    required this.x,
    required this.y,
    required this.widthFactor,
    required this.maxWidth,
    required this.drift,
  });

  final int id;
  final int unlockScore;
  final double x;
  final double y;
  final double widthFactor;
  final double maxWidth;
  final double drift;
}

class _SignalReflectorSpec {
  const _SignalReflectorSpec({
    required this.id,
    required this.unlockScore,
    required this.center,
    required this.size,
  });

  final int id;
  final int unlockScore;
  final Offset center;
  final Size size;
}

class _SignalReflector {
  _SignalReflector({
    required this.id,
    required this.unlockScore,
    required this.center,
    required this.size,
  });

  final int id;
  final int unlockScore;
  Offset center;
  Size size;
  DateTime? lastHitAt;
  DateTime? hitUntil;

  Rect get rect =>
      Rect.fromCenter(center: center, width: size.width, height: size.height);
}

class _ReflectorHit {
  const _ReflectorHit({
    required this.signal,
    required this.velocity,
    required this.hit,
  });

  final Offset signal;
  final Offset velocity;
  final bool hit;
}

class _SegmentRectHit {
  const _SegmentRectHit(this.time, this.normal);

  final double time;
  final Offset normal;
}

// paints a calm field with brief feedback instead of constant arcade glow
class _SignalGamePainter extends CustomPainter {
  const _SignalGamePainter({
    required this.signal,
    required this.trail,
    required this.particles,
    required this.reflectors,
    required this.paddleCenter,
    required this.paddleWidth,
    required this.accent,
    required this.started,
    required this.ended,
    required this.paused,
    required this.score,
    required this.combo,
    required this.phase,
    required this.time,
    required this.hitPulse,
    required this.focusActive,
    required this.signalRadius,
    required this.theme,
    required this.renderLite,
  });

  final Offset signal;
  final List<Offset> trail;
  final List<_GameParticle> particles;
  final List<_SignalReflector> reflectors;
  final double paddleCenter;
  final double paddleWidth;
  final Color accent;
  final bool started;
  final bool ended;
  final bool paused;
  final int score;
  final int combo;
  final int phase;
  final double time;
  final double hitPulse;
  final bool focusActive;
  final double signalRadius;
  final _SignalFieldTheme theme;
  final bool renderLite;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final bg = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          theme.base,
          focusActive ? theme.highlight.withValues(alpha: 0.16) : theme.mist,
          theme.dark ? theme.base : Colors.white,
        ],
      ).createShader(rect);
    canvas.drawRect(rect, bg);

    final pulse = 0.5 + math.sin(time * math.pi * 2) * 0.5;
    if (!renderLite) {
      final topMist = Paint()
        ..shader =
            RadialGradient(
              colors: [
                accent.withValues(alpha: focusActive ? 0.11 : 0.06),
                Colors.transparent,
              ],
            ).createShader(
              Rect.fromCircle(
                center: Offset(size.width * 0.5, size.height * 0.22),
                radius: size.shortestSide * 0.72,
              ),
            );
      canvas.drawRect(rect, topMist);
    }

    final dangerPaint = Paint()
      ..color = theme.danger.withValues(alpha: ended ? 0.22 : 0.10)
      ..strokeWidth = 1.6;
    canvas.drawLine(
      Offset(24, size.height - 44),
      Offset(size.width - 24, size.height - 44),
      dangerPaint,
    );

    for (final reflector in reflectors) {
      final reflectorRect = reflector.rect;
      final hitActive =
          reflector.hitUntil != null &&
          DateTime.now().isBefore(reflector.hitUntil!);
      final reflectorShape = RRect.fromRectAndRadius(
        reflectorRect,
        const Radius.circular(12),
      );
      final fillAlpha = hitActive
          ? (theme.dark ? 0.20 : 0.16)
          : (theme.dark ? 0.12 : 0.08);
      canvas.drawRRect(
        reflectorShape.inflate(hitActive && !renderLite ? 2 : 0),
        Paint()..color = theme.signal.withValues(alpha: fillAlpha),
      );
      canvas.drawRRect(
        reflectorShape,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = hitActive ? 1.4 : 1
          ..color = theme.ink.withValues(alpha: hitActive ? 0.24 : 0.14),
      );
      if (!renderLite) {
        canvas.drawLine(
          Offset(reflectorRect.left + 10, reflectorRect.center.dy),
          Offset(reflectorRect.right - 10, reflectorRect.center.dy),
          Paint()
            ..strokeWidth = 1
            ..strokeCap = StrokeCap.round
            ..color = theme.highlight.withValues(
              alpha: hitActive ? 0.24 : 0.12,
            ),
        );
      }
    }

    final trailStart = renderLite ? math.max(0, trail.length - 6) : 0;
    for (var i = trailStart; i < trail.length; i++) {
      final point = trail[i];
      final alpha = (i + 1) / trail.length;
      canvas.drawCircle(
        point,
        renderLite ? 3 + alpha * 4 : 3 + alpha * 7,
        Paint()
          ..color = accent.withValues(
            alpha: alpha * (renderLite ? 0.05 : 0.08),
          ),
      );
    }

    if (!renderLite) {
      for (final particle in particles) {
        final alpha = (1 - particle.age / particle.life).clamp(0.0, 1.0);
        canvas.drawCircle(
          particle.position,
          particle.size * (0.8 + alpha),
          Paint()..color = particle.color.withValues(alpha: alpha * 0.28),
        );
      }
    }

    if (focusActive && !renderLite) {
      final focusRing = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4
        ..color = theme.highlight.withValues(alpha: 0.22);
      canvas.drawCircle(signal, 28 + pulse * 6, focusRing);
    }

    final signalGlow = Paint()
      ..color = accent.withValues(alpha: focusActive ? 0.16 : 0.10);
    canvas.drawCircle(signal, 19 + pulse * 2, signalGlow);
    final signalPaint = Paint()
      ..color = paused
          ? (theme.dark
                ? theme.text.withValues(alpha: 0.54)
                : AppColors.textTertiary)
          : accent;
    final squashX = 1 + hitPulse * 0.28;
    final squashY = 1 - hitPulse * 0.18;
    final signalRect = Rect.fromCenter(
      center: signal,
      width: signalRadius * 2 * squashX,
      height: signalRadius * 2 * squashY,
    );
    canvas.drawOval(signalRect, signalPaint);
    canvas.drawCircle(
      signal.translate(-4, -4),
      3.8,
      Paint()..color = Colors.white.withValues(alpha: 0.70),
    );

    final paddleY = size.height - 76;
    final paddleRect = Rect.fromCenter(
      center: Offset(paddleCenter * size.width, paddleY),
      width: paddleWidth,
      height: 12,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        paddleRect.inflate(focusActive ? 13 : 8),
        const Radius.circular(16),
      ),
      Paint()
        ..color = accent.withValues(
          alpha: focusActive || combo >= 4 ? 0.13 : 0.07,
        ),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(paddleRect, const Radius.circular(10)),
      Paint()
        ..color = started && !ended && !paused
            ? accent
            : AppColors.textTertiary,
    );
  }

  @override
  bool shouldRepaint(covariant _SignalGamePainter oldDelegate) {
    return signal != oldDelegate.signal ||
        trail != oldDelegate.trail ||
        particles != oldDelegate.particles ||
        reflectors != oldDelegate.reflectors ||
        paddleCenter != oldDelegate.paddleCenter ||
        accent != oldDelegate.accent ||
        started != oldDelegate.started ||
        ended != oldDelegate.ended ||
        paused != oldDelegate.paused ||
        score != oldDelegate.score ||
        combo != oldDelegate.combo ||
        phase != oldDelegate.phase ||
        time != oldDelegate.time ||
        hitPulse != oldDelegate.hitPulse ||
        focusActive != oldDelegate.focusActive ||
        signalRadius != oldDelegate.signalRadius ||
        theme != oldDelegate.theme ||
        renderLite != oldDelegate.renderLite;
  }
}

class _GameTopBar extends StatelessWidget {
  const _GameTopBar({required this.onBack, required this.onReset});

  final VoidCallback onBack;
  final VoidCallback? onReset;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
      child: Row(
        children: [
          IconButton(
            tooltip: 'Back',
            icon: const Icon(Icons.arrow_back_rounded),
            onPressed: onBack,
          ),
          Expanded(
            child: Text(
              'Signal drift',
              style: AppTypography.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w800,
                color: AppColors.charcoal,
              ),
              textAlign: TextAlign.center,
            ),
          ),
          IconButton(
            tooltip: 'Reset',
            icon: const Icon(Icons.refresh_rounded),
            onPressed: onReset,
          ),
        ],
      ),
    );
  }
}

class _GhostBackButton extends StatelessWidget {
  const _GhostBackButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white.withValues(alpha: 0.52),
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: const SizedBox(
          width: 36,
          height: 36,
          child: Icon(Icons.arrow_back_rounded, size: 18),
        ),
      ),
    );
  }
}

class _GamePill extends StatelessWidget {
  const _GamePill({
    required this.label,
    required this.value,
    required this.color,
    this.strong = false,
  });

  final String label;
  final String value;
  final Color color;
  final bool strong;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.88),
        borderRadius: BorderRadius.circular(AppSpacing.radiusFull),
        border: Border.all(
          color: color.withValues(alpha: strong ? 0.26 : 0.16),
        ),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: strong ? 0.10 : 0.05),
            blurRadius: strong ? 20 : 12,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: AppTypography.textTheme.labelSmall?.copyWith(
              color: AppColors.textTertiary,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(width: 6),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 160),
            child: Text(
              value,
              key: ValueKey(value),
              style: AppTypography.textTheme.labelMedium?.copyWith(
                color: color,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FocusMeter extends StatelessWidget {
  const _FocusMeter({
    required this.value,
    required this.active,
    required this.color,
  });

  final int value;
  final bool active;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final progress = active ? 1.0 : (value.clamp(0, 100) / 100).toDouble();
    return IgnorePointer(
      child: SizedBox(
        width: 140,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.72),
            borderRadius: BorderRadius.circular(AppSpacing.radiusFull),
            border: Border.all(color: color.withValues(alpha: 0.14)),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(AppSpacing.radiusFull),
            child: LinearProgressIndicator(
              minHeight: 5,
              value: progress,
              color: active ? _fieldHighlight : color,
              backgroundColor: _fieldMist,
            ),
          ),
        ),
      ),
    );
  }
}

class _ComboBurst extends StatelessWidget {
  const _ComboBurst({required this.note, required this.color});

  final String note;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 140),
        transitionBuilder: (child, animation) {
          final scale = Tween<double>(begin: 0.96, end: 1).animate(
            CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
          );
          return FadeTransition(
            opacity: animation,
            child: ScaleTransition(scale: scale, child: child),
          );
        },
        child: Text(
          note,
          key: ValueKey(note),
          style: AppTypography.textTheme.headlineSmall?.copyWith(
            color: color.withValues(alpha: 0.82),
            fontWeight: FontWeight.w900,
          ),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}

class _GamePrompt extends StatelessWidget {
  const _GamePrompt({
    super.key,
    required this.ended,
    required this.paused,
    required this.score,
    required this.highScore,
    required this.submitting,
    required this.result,
    required this.showReviewButton,
    required this.fragments,
    required this.fragmentsEarned,
    required this.dailyPrompt,
    required this.dailyCompletedThisRun,
    required this.fieldName,
    required this.nextFieldText,
    required this.unlockedField,
    required this.theme,
    required this.onRestart,
    required this.onResume,
    required this.onReview,
  });

  final bool ended;
  final bool paused;
  final int score;
  final int highScore;
  final bool submitting;
  final SignalDriftScoreResult? result;
  final bool showReviewButton;
  final int fragments;
  final int fragmentsEarned;
  final String dailyPrompt;
  final bool dailyCompletedThisRun;
  final String fieldName;
  final String nextFieldText;
  final String? unlockedField;
  final _SignalFieldTheme theme;
  final VoidCallback onRestart;
  final VoidCallback onResume;
  final VoidCallback onReview;

  @override
  Widget build(BuildContext context) {
    final title = paused
        ? 'Field paused'
        : ended
        ? 'Signal lost'
        : 'Tap to begin';
    final subtitle = paused
        ? 'Resume when you are ready'
        : ended
        ? _resultText
        : 'slide anywhere to guide the signal';
    final waitingForScore = ended && submitting;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
      padding: const EdgeInsets.all(AppSpacing.lg),
      constraints: const BoxConstraints(maxWidth: 360),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.94),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppColors.borderSubtle),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.07),
            blurRadius: 26,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            title,
            style: AppTypography.textTheme.titleLarge?.copyWith(
              color: AppColors.charcoal,
              fontWeight: FontWeight.w900,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            ended && dailyCompletedThisRun
                ? '$subtitle and daily cleared'
                : subtitle,
            style: AppTypography.textTheme.bodySmall?.copyWith(
              color: AppColors.textSecondary,
            ),
            textAlign: TextAlign.center,
          ),
          if (!ended) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(
              '$fieldName - $dailyPrompt',
              style: AppTypography.textTheme.labelSmall?.copyWith(
                color: theme.dark
                    ? theme.text.withValues(alpha: 0.70)
                    : AppColors.textTertiary,
                fontWeight: FontWeight.w700,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 4),
            Text(
              nextFieldText,
              style: AppTypography.textTheme.labelSmall?.copyWith(
                color: theme.signal.withValues(alpha: 0.86),
                fontWeight: FontWeight.w800,
              ),
              textAlign: TextAlign.center,
            ),
          ],
          if (ended) ...[
            const SizedBox(height: AppSpacing.md),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _ScoreTile(label: 'score', value: '$score'),
                const SizedBox(width: AppSpacing.sm),
                _ScoreTile(label: 'best', value: '$highScore'),
              ],
            ),
            if (fragmentsEarned > 0) ...[
              const SizedBox(height: AppSpacing.sm),
              Text(
                '+$fragmentsEarned fragments - $fragments total',
                style: AppTypography.textTheme.labelSmall?.copyWith(
                  color: theme.signal,
                  fontWeight: FontWeight.w800,
                ),
                textAlign: TextAlign.center,
              ),
            ],
            if (unlockedField != null) ...[
              const SizedBox(height: 4),
              Text(
                'unlocked $unlockedField',
                style: AppTypography.textTheme.labelSmall?.copyWith(
                  color: theme.highlight,
                  fontWeight: FontWeight.w900,
                ),
                textAlign: TextAlign.center,
              ),
            ],
            const SizedBox(height: AppSpacing.sm),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 180),
              child: submitting
                  ? const SizedBox(
                      key: ValueKey('syncing'),
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(
                      _syncLabel,
                      key: ValueKey(_syncLabel),
                      style: AppTypography.textTheme.labelSmall?.copyWith(
                        color: AppColors.textTertiary,
                        fontWeight: FontWeight.w700,
                      ),
                      textAlign: TextAlign.center,
                    ),
            ),
          ],
          const SizedBox(height: AppSpacing.lg),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 220),
            transitionBuilder: (child, animation) {
              final scale = Tween<double>(begin: 0.94, end: 1).animate(
                CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
              );
              return FadeTransition(
                opacity: animation,
                child: ScaleTransition(scale: scale, child: child),
              );
            },
            child: waitingForScore
                ? _SavingScoreAction(
                    key: const ValueKey('saving-action'),
                    theme: theme,
                  )
                : Row(
                    key: ValueKey('action-$ended-$paused'),
                    children: [
                      Expanded(
                        child: ElevatedButton(
                          onPressed: paused ? onResume : onRestart,
                          child: Text(
                            paused
                                ? 'Resume'
                                : ended
                                ? 'Try again'
                                : 'Start',
                          ),
                        ),
                      ),
                      if (ended && showReviewButton) ...[
                        const SizedBox(width: AppSpacing.sm),
                        IconButton.filledTonal(
                          tooltip: 'Review Echoproof',
                          onPressed: onReview,
                          icon: const Icon(Icons.rate_review_outlined),
                        ),
                      ],
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  String get _resultText {
    if (score <= 0) return 'the field is still quiet';
    if (score >= highScore && score > 0) return 'new best signal held';
    return 'bring it back into context';
  }

  String get _syncLabel {
    final item = result;
    if (item == null) return 'saving score';
    if (item.accepted) return 'validated on your account';
    if (item.localOnly) return 'saved locally until sync returns';
    return 'server kept your previous best';
  }
}

class _SavingScoreAction extends StatelessWidget {
  const _SavingScoreAction({super.key, required this.theme});

  final _SignalFieldTheme theme;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            valueColor: AlwaysStoppedAnimation<Color>(theme.signal),
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Text(
          'saving score',
          style: AppTypography.textTheme.labelMedium?.copyWith(
            color: AppColors.textSecondary,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    );
  }
}

class _ScoreTile extends StatelessWidget {
  const _ScoreTile({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 92,
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.surfaceSecondary,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        children: [
          Text(
            value,
            style: AppTypography.textTheme.titleLarge?.copyWith(
              color: AppColors.charcoal,
              fontWeight: FontWeight.w900,
            ),
          ),
          Text(
            label,
            style: AppTypography.textTheme.labelSmall?.copyWith(
              color: AppColors.textTertiary,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _ExitSheet extends StatelessWidget {
  const _ExitSheet({required this.onResume, required this.onLeave});

  final VoidCallback onResume;
  final VoidCallback onLeave;

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.viewPaddingOf(context).bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(22, 8, 22, 28 + bottomInset),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Leave signal drift?',
            style: AppTypography.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w900,
              color: AppColors.charcoal,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'Your current run will stop if you leave now',
            style: AppTypography.textTheme.bodySmall?.copyWith(
              color: AppColors.textSecondary,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AppSpacing.lg),
          ElevatedButton(onPressed: onResume, child: const Text('Resume')),
          TextButton(onPressed: onLeave, child: const Text('Leave')),
        ],
      ),
    );
  }
}
