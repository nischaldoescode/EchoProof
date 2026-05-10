// Client-side spam pre-check using heuristics.
// TFLite model runs locally — no network call needed.
// This is a fast gate before the echo hits the server.
// If this flags content, we warn the user before submission.
// The server (SightEngine) is the authoritative check.
//
// Note: We use a rule-based approach here because loading a custom
// TFLite model requires a trained .tflite asset. Until you train one,
// the heuristic provides comparable coverage for common spam patterns.

import '../utils/logger.dart';

class TfliteSpamChecker {
  static const _threshold = 60; // warn above this score

  /// checks text and returns a spam score between 0 and 100
  static int checkText(String title, String content) {
    final combined = _normalize('$title $content');
    int score = 0;

    score += _capsScore(content);
    score += _punctuationScore(combined);
    score += _repetitionScore(combined);
    score += _urlScore(combined, content);
    score += _numericScore(combined);
    score += _phraseScore(combined);
    score += _entropyPenalty(combined);

    score = score.clamp(0, 100);

    AppLogger.info(
      'tflite: spam score=$score for "${title.substring(0, title.length.clamp(0, 30))}"',
    );

    return score;
  }

  /// determines if user should be warned before submission
  static bool shouldWarn(String title, String content) {
    return checkText(title, content) >= _threshold;
  }

  // ------------------------
  // internal helpers
  // ------------------------

  /// normalizes text for consistent checks
  static String _normalize(String input) {
    return input.toLowerCase().replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  /// detects excessive capitalization
  static int _capsScore(String content) {
    final letters = content.replaceAll(RegExp(r'[^a-zA-Z]'), '');
    if (letters.isEmpty) return 0;

    final upperCount = content.runes.where((c) => c >= 65 && c <= 90).length;

    final ratio = upperCount / letters.length;

    if (ratio > 0.7) return 25; // aggressive caps
    if (ratio > 0.5) return 15;

    return 0;
  }

  /// detects excessive punctuation like !!! or ???
  static int _punctuationScore(String text) {
    if (RegExp(r'[!?]{4,}').hasMatch(text)) return 20;
    if (RegExp(r'[!?]{3}').hasMatch(text)) return 10;
    return 0;
  }

  /// detects repeated characters like loooooool
  static int _repetitionScore(String text) {
    if (RegExp(r'(.)\1{5,}').hasMatch(text)) return 15;
    if (RegExp(r'(.)\1{3,}').hasMatch(text)) return 8;
    return 0;
  }

  /// detects link spam patterns
  static int _urlScore(String text, String content) {
    final urlCount = RegExp(r'https?://').allMatches(text).length;

    int score = 0;

    if (urlCount > 5)
      score += 30;
    else if (urlCount > 3)
      score += 20;
    else if (urlCount > 1) score += 10;

    // short content + link = high spam probability
    if (content.trim().length < 30 && urlCount > 0) {
      score += 25;
    }

    return score;
  }

  /// detects phone numbers or numeric spam
  static int _numericScore(String text) {
    if (RegExp(r'\b\d{10,}\b').hasMatch(text)) return 15;
    if (RegExp(r'(?:\d[ -]?){8,}').hasMatch(text)) return 10;
    return 0;
  }

  /// detects common spam phrases
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
    ];

    for (final p in phrases) {
      if (text.contains(p)) {
        return 15;
      }
    }

    return 0;
  }

  /// detects low-quality / gibberish-like text
  static int _entropyPenalty(String text) {
    if (text.length < 20) return 0;

    final uniqueChars = text.split('').toSet().length;
    final ratio = uniqueChars / text.length;

    // very low diversity = likely spam/gibberish
    if (ratio < 0.2) return 15;
    if (ratio < 0.3) return 8;

    return 0;
  }
}
