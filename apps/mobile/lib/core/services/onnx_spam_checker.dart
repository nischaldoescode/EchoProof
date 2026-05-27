// On-device spam classifier for Echo text.
//
// Primary path:
//   BERT WordPiece tokenizer -> DistilBERT ONNX -> logits -> softmax.
//
// Fallback path:
//   Lightweight rules. This keeps publishing stable if the ONNX runtime,
//   external model data, or vocab asset is unavailable on a device.

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:dart_bert_tokenizer/dart_bert_tokenizer.dart';
import 'package:flutter/services.dart';
import 'package:flutter_onnxruntime/flutter_onnxruntime.dart';
import 'package:path_provider/path_provider.dart';

import '../utils/logger.dart';

enum SpamLabel { ham, suspicious, spam }

class SpamCheckResult {
  const SpamCheckResult({
    required this.label,
    required this.score,
    required this.spamProbability,
    required this.hamProbability,
    required this.source,
    required this.tokenCount,
    required this.windowCount,
    this.reason,
  });

  final SpamLabel label;
  final int score;
  final double spamProbability;
  final double hamProbability;
  final String source;
  final int tokenCount;
  final int windowCount;
  final String? reason;

  bool get isSpam => label == SpamLabel.spam;
  bool get isSuspicious => label == SpamLabel.suspicious;
}

class OnnxSpamChecker {
  static const suspiciousThreshold = 60;
  static const blockThreshold = 85;
  static const maxSequenceLength = 256;
  static const _windowOverlap = 64;
  static const _resourceTimeout = Duration(seconds: 4);
  static const _inferenceTimeout = Duration(seconds: 5);
  static const _modelAsset = 'assets/models/spam_model.onnx';
  static const _modelDataAsset = 'assets/models/spam_model.onnx.data';
  static const _vocabAsset = 'assets/models/vocab.txt';
  static const _enableOnDeviceOnnx = bool.fromEnvironment(
    'ECHOPROOF_ENABLE_ONNX_SPAM',
    defaultValue: false,
  );

  static final _runtime = OnnxRuntime();
  static Future<_OnnxSpamResources?>? _resourcesFuture;
  static String? _lastCacheKey;
  static SpamCheckResult? _lastResult;
  static bool _onnxDisabledForSession = false;

  /// Fast local fallback for UI hints before the async model is ready.
  static int quickScore(String title, String content) {
    return _heuristicScore(title, content);
  }

  static bool shouldWarnQuick(String title, String content) {
    return quickScore(title, content) >= suspiciousThreshold;
  }

  static Future<SpamCheckResult> checkText(
    String title,
    String content,
  ) async {
    try {
      final text = _cleanForModel('$title\n$content');
      if (text.isEmpty) {
        return const SpamCheckResult(
          label: SpamLabel.ham,
          score: 0,
          spamProbability: 0,
          hamProbability: 1,
          source: 'empty',
          tokenCount: 0,
          windowCount: 0,
        );
      }

      final cacheKey = sha256.convert(utf8.encode(text)).toString();
      if (_lastCacheKey == cacheKey && _lastResult != null) {
        return _lastResult!;
      }

      if (!_enableOnDeviceOnnx) {
        final result = _fallbackResult(
          title,
          content,
          reason: 'onnx_disabled_for_build',
        );
        _lastCacheKey = cacheKey;
        _lastResult = result;
        return result;
      }

      if (_onnxDisabledForSession) {
        final result = _fallbackResult(
          title,
          content,
          reason: 'onnx_disabled_for_session',
        );
        _lastCacheKey = cacheKey;
        _lastResult = result;
        return result;
      }

      final resources = await _ensureResources().timeout(
        _resourceTimeout,
        onTimeout: () {
          AppLogger.warn('onnx spam: resource load timed out, using fallback');
          _onnxDisabledForSession = true;
          return null;
        },
      );
      final result = resources == null
          ? _fallbackResult(title, content, reason: 'onnx_unavailable')
          : await _runOnnx(resources, text).timeout(
              _inferenceTimeout,
              onTimeout: () {
                AppLogger.warn(
                    'onnx spam: inference timed out, using fallback');
                _onnxDisabledForSession = true;
                return _fallbackResult(
                  title,
                  content,
                  reason: 'onnx_timeout',
                );
              },
            );

      _lastCacheKey = cacheKey;
      _lastResult = result;
      return result;
    } catch (e) {
      AppLogger.error('onnx spam: safety check failed closed to fallback', e);
      _onnxDisabledForSession = true;
      return _fallbackResult(title, content, reason: 'onnx_check_failed');
    }
  }

  static Future<_OnnxSpamResources?> _ensureResources() {
    return _resourcesFuture ??= _loadResources();
  }

  static Future<_OnnxSpamResources?> _loadResources() async {
    try {
      final vocabText = await rootBundle.loadString(_vocabAsset);
      final vocabTokens = vocabText.split(RegExp(r'\r?\n'));
      if (vocabTokens.isNotEmpty && vocabTokens.last.trim().isEmpty) {
        vocabTokens.removeLast();
      }
      if (vocabTokens.length < 1000) {
        throw StateError('BERT vocab is missing or incomplete.');
      }

      final tokenizer = WordPieceTokenizer(
        vocab: Vocabulary.fromTokens(vocabTokens),
      );

      final modelPath = await _copyModelAssetsToSupportDir();
      final session = await _runtime.createSession(
        modelPath,
        options: OrtSessionOptions(
          intraOpNumThreads: 2,
          interOpNumThreads: 1,
          providers: _providersForPlatform(),
          useArena: true,
        ),
      );

      AppLogger.info(
        'onnx spam: loaded model with inputs=${session.inputNames} outputs=${session.outputNames}',
      );
      return _OnnxSpamResources(tokenizer: tokenizer, session: session);
    } catch (e) {
      AppLogger.warn('onnx spam: unavailable, using fallback $e');
      return null;
    }
  }

  static List<OrtProvider> _providersForPlatform() {
    if (Platform.isAndroid) {
      return const [OrtProvider.XNNPACK, OrtProvider.CPU];
    }
    return const [OrtProvider.CPU];
  }

  static Future<String> _copyModelAssetsToSupportDir() async {
    final baseDir = await getApplicationSupportDirectory();
    final modelDir = Directory('${baseDir.path}/echoproof_spam_onnx');
    if (!await modelDir.exists()) {
      await modelDir.create(recursive: true);
    }

    final modelPath = await _copyAssetIfChanged(
      _modelAsset,
      '${modelDir.path}/spam_model.onnx',
    );
    await _copyAssetIfChanged(
      _modelDataAsset,
      '${modelDir.path}/spam_model.onnx.data',
    );
    return modelPath;
  }

  static Future<String> _copyAssetIfChanged(
    String assetKey,
    String filePath,
  ) async {
    final bytes = await rootBundle.load(assetKey);
    final list = bytes.buffer.asUint8List(
      bytes.offsetInBytes,
      bytes.lengthInBytes,
    );
    final file = File(filePath);
    if (await file.exists() && await file.length() == list.length) {
      return file.path;
    }
    await file.writeAsBytes(list, flush: true);
    return file.path;
  }

  static Future<SpamCheckResult> _runOnnx(
    _OnnxSpamResources resources,
    String text,
  ) async {
    try {
      final encoded = resources.tokenizer.encode(
        text,
        addSpecialTokens: false,
      );
      final tokenIds = encoded.ids.toList(growable: false);
      if (tokenIds.isEmpty) {
        return const SpamCheckResult(
          label: SpamLabel.ham,
          score: 0,
          spamProbability: 0,
          hamProbability: 1,
          source: 'onnx_empty_tokens',
          tokenCount: 0,
          windowCount: 0,
        );
      }

      final windows = _createWindows(
        tokenIds,
        maxSequenceLength - 2,
        _windowOverlap,
      );
      var maxSpam = 0.0;
      var matchingHam = 1.0;

      for (final window in windows) {
        final probabilities = await _runWindow(resources, window);
        final ham = probabilities[0];
        final spam = probabilities[1];
        if (spam > maxSpam) {
          maxSpam = spam;
          matchingHam = ham;
        }
      }

      final adjustedSpam = _adjustForVeryShortText(maxSpam, tokenIds.length);
      final score = (adjustedSpam * 100).round().clamp(0, 100).toInt();
      final label = _labelForScore(score);
      return SpamCheckResult(
        label: label,
        score: score,
        spamProbability: adjustedSpam,
        hamProbability: matchingHam,
        source: windows.length == 1 ? 'onnx' : 'onnx_sliding_window',
        tokenCount: tokenIds.length,
        windowCount: windows.length,
      );
    } catch (e) {
      AppLogger.warn('onnx spam: inference failed, using fallback $e');
      _onnxDisabledForSession = true;
      return _fallbackResult('', text, reason: 'onnx_inference_failed');
    }
  }

  static Future<List<double>> _runWindow(
    _OnnxSpamResources resources,
    List<int> window,
  ) async {
    final inputIds = List<int>.filled(maxSequenceLength, 0);
    final attentionMask = List<int>.filled(maxSequenceLength, 0);
    inputIds[0] = resources.tokenizer.vocab.clsTokenId;
    attentionMask[0] = 1;
    for (var i = 0; i < window.length; i++) {
      inputIds[i + 1] = window[i];
      attentionMask[i + 1] = 1;
    }
    final sepIndex = window.length + 1;
    inputIds[sepIndex] = resources.tokenizer.vocab.sepTokenId;
    attentionMask[sepIndex] = 1;

    final inputs = <String, OrtValue>{};
    final createdValues = <OrtValue>[];
    final outputValues = <OrtValue>[];

    try {
      final idsValue = await OrtValue.fromList(
        Int64List.fromList(inputIds),
        const [1, maxSequenceLength],
      );
      final maskValue = await OrtValue.fromList(
        Int64List.fromList(attentionMask),
        const [1, maxSequenceLength],
      );
      createdValues
        ..add(idsValue)
        ..add(maskValue);
      inputs['input_ids'] = idsValue;
      inputs['attention_mask'] = maskValue;

      if (resources.session.inputNames.contains('token_type_ids')) {
        final typeIdsValue = await OrtValue.fromList(
          Int64List(maxSequenceLength),
          const [1, maxSequenceLength],
        );
        createdValues.add(typeIdsValue);
        inputs['token_type_ids'] = typeIdsValue;
      }

      final outputs = await resources.session.run(inputs);
      outputValues.addAll(outputs.values);
      final firstOutputName = resources.session.outputNames.isNotEmpty
          ? resources.session.outputNames.first
          : outputs.keys.first;
      final flat = await outputs[firstOutputName]!.asFlattenedList();
      final logits = flat.map((value) => (value as num).toDouble()).toList();
      if (logits.length < 2) {
        throw StateError('Expected two logits: HAM and SPAM.');
      }
      return _softmax(logits.take(2).toList(growable: false));
    } finally {
      for (final value in outputValues) {
        unawaited(value.dispose());
      }
      for (final value in createdValues) {
        unawaited(value.dispose());
      }
    }
  }

  static List<List<int>> _createWindows(
    List<int> tokens,
    int payloadSize,
    int overlap,
  ) {
    if (tokens.length <= payloadSize) {
      return [tokens];
    }
    final step = math.max(1, payloadSize - overlap);
    final windows = <List<int>>[];
    for (var start = 0; start < tokens.length; start += step) {
      final end = math.min(start + payloadSize, tokens.length);
      windows.add(tokens.sublist(start, end));
      if (end == tokens.length) break;
    }
    return windows;
  }

  static List<double> _softmax(List<double> logits) {
    final maxLogit = logits.reduce(math.max);
    final exps = logits.map((x) => math.exp(x - maxLogit)).toList();
    final sum = exps.reduce((a, b) => a + b);
    return exps.map((e) => e / sum).toList();
  }

  static double _adjustForVeryShortText(double spam, int tokenCount) {
    if (tokenCount >= 3) return spam;
    return spam * 0.85;
  }

  static SpamCheckResult _fallbackResult(
    String title,
    String content, {
    String? reason,
  }) {
    final score = _heuristicScore(title, content);
    return SpamCheckResult(
      label: _labelForScore(score),
      score: score,
      spamProbability: score / 100,
      hamProbability: 1 - (score / 100),
      source: 'heuristic',
      tokenCount: 0,
      windowCount: 0,
      reason: reason,
    );
  }

  static SpamLabel _labelForScore(int score) {
    if (score >= blockThreshold) return SpamLabel.spam;
    if (score >= suspiciousThreshold) return SpamLabel.suspicious;
    return SpamLabel.ham;
  }

  static String _cleanForModel(String input) {
    return input
        .replaceAll('\u0000', ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  static int _heuristicScore(String title, String content) {
    final combined = _normalize('$title $content');
    var score = 0;

    score += _capsScore(content);
    score += _punctuationScore(combined);
    score += _repetitionScore(combined);
    score += _urlScore(combined, content);
    score += _numericScore(combined);
    score += _phraseScore(combined);
    score += _entropyPenalty(combined);

    return score.clamp(0, 100).toInt();
  }

  static String _normalize(String input) {
    return input.toLowerCase().replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  static int _capsScore(String content) {
    final letters = content.replaceAll(RegExp(r'[^a-zA-Z]'), '');
    if (letters.isEmpty) return 0;

    final upperCount = content.runes.where((c) => c >= 65 && c <= 90).length;
    final ratio = upperCount / letters.length;

    if (ratio > 0.7) return 25;
    if (ratio > 0.5) return 15;
    return 0;
  }

  static int _punctuationScore(String text) {
    if (RegExp(r'[!?]{4,}').hasMatch(text)) return 20;
    if (RegExp(r'[!?]{3}').hasMatch(text)) return 10;
    return 0;
  }

  static int _repetitionScore(String text) {
    if (RegExp(r'(.)\1{5,}').hasMatch(text)) return 15;
    if (RegExp(r'(.)\1{3,}').hasMatch(text)) return 8;
    return 0;
  }

  static int _urlScore(String text, String content) {
    final urlCount = RegExp(r'https?://').allMatches(text).length;
    var score = 0;

    if (urlCount > 5) {
      score += 30;
    } else if (urlCount > 3) {
      score += 20;
    } else if (urlCount > 1) {
      score += 10;
    }

    if (content.trim().length < 30 && urlCount > 0) {
      score += 25;
    }
    return score;
  }

  static int _numericScore(String text) {
    if (RegExp(r'\b\d{10,}\b').hasMatch(text)) return 15;
    if (RegExp(r'(?:\d[ -]?){8,}').hasMatch(text)) return 10;
    return 0;
  }

  static int _phraseScore(String text) {
    const phrases = [
      'click here',
      'buy now',
      'free money',
      'act now',
      'dm me',
      'whatsapp me',
      'earn \$',
      'make money fast',
      'guaranteed income',
      'investment trick',
      'crypto giveaway',
    ];

    for (final phrase in phrases) {
      if (text.contains(phrase)) return 15;
    }
    return 0;
  }

  static int _entropyPenalty(String text) {
    if (text.length < 20) return 0;

    final uniqueChars = text.split('').toSet().length;
    final ratio = uniqueChars / text.length;

    if (ratio < 0.2) return 15;
    if (ratio < 0.3) return 8;
    return 0;
  }
}

class _OnnxSpamResources {
  const _OnnxSpamResources({
    required this.tokenizer,
    required this.session,
  });

  final WordPieceTokenizer tokenizer;
  final OrtSession session;
}
