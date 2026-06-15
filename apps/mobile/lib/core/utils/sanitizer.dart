// sanitizer
// @params none

abstract final class Sanitizer {
  // internal helpers

  static String _stripNulls(String input) {
    return input.replaceAll('\x00', '').replaceAll('\u0000', '');
  }

  static String _stripZeroWidth(String input) {
    return input.replaceAll(RegExp(r'[\u200B-\u200D\uFEFF]'), '');
  }

  static String _normalizeNewlines(String input) {
    return input.replaceAll(RegExp(r'\r\n|\r'), '\n');
  }

  static String _collapseWhitespace(String input) {
    return input.replaceAll(RegExp(r'[ \t]+'), ' ');
  }

  static String _basicClean(String input) {
    return _collapseWhitespace(
      _normalizeNewlines(_stripZeroWidth(_stripNulls(input))),
    );
  }

  static String _safeSubstring(String input, int max) {
    if (input.length <= max) return input;
    return input.substring(0, max);
  }

  static String _stripSqlMeta(String input) {
    return input
        .replaceAll("'", "''") // sql escape
        .replaceAll(RegExp(r'(--|\bOR\b|\bAND\b)', caseSensitive: false), '');
  }

  // public api

  static String text(String input) {
    final cleaned = _basicClean(input).trim();
    return cleaned;
  }

  static String username(String input) {
    final cleaned = _basicClean(
      input,
    ).toLowerCase().replaceAll(RegExp(r'[^a-z0-9_]'), '').trim();
    return _safeSubstring(cleaned, 20);
  }

  static String? url(String input) {
    final cleaned = _basicClean(input).trim();

    if (cleaned.isEmpty) return null;
    if (cleaned.length > 240) return null;
    if (RegExp(r'\s').hasMatch(cleaned)) return null;

    final lower = cleaned.toLowerCase();
    if (!lower.startsWith('http://') && !lower.startsWith('https://')) {
      return null;
    }

    if (lower.contains('javascript:') ||
        lower.contains('data:') ||
        lower.contains('vbscript:') ||
        lower.contains('<') ||
        lower.contains('>')) {
      return null;
    }

    try {
      final uri = Uri.parse(cleaned);

      if (uri.host.isEmpty) return null;
      if (!uri.hasScheme) return null;
      if (uri.userInfo.isNotEmpty) return null;
      final host = uri.host.toLowerCase();
      if (host == 'localhost' || host.endsWith('.local')) return null;
      if (!host.contains('.')) return null;
      if (RegExp(r'^\d{1,3}(\.\d{1,3}){3}$').hasMatch(host)) return null;
      final labels = host.split('.');
      final validLabel = RegExp(r'^[a-z0-9-]{1,63}$');
      if (labels.any((label) {
        return label.isEmpty ||
            !validLabel.hasMatch(label) ||
            label.startsWith('-') ||
            label.endsWith('-');
      })) {
        return null;
      }
      final suffix = labels.last;
      final isClassicSuffix = RegExp(r'^[a-z]{2,63}$').hasMatch(suffix);
      final isPunycodeSuffix =
          suffix.startsWith('xn--') &&
          RegExp(r'^xn--[a-z0-9-]{2,59}$').hasMatch(suffix);
      if (suffix.length < 2 || (!isClassicSuffix && !isPunycodeSuffix)) {
        return null;
      }

      // normalize url (important for dedup + sql storage)
      return uri.normalizePath().toString();
    } catch (_) {
      return null;
    }
  }

  static String displayName(String input) {
    final cleaned = _basicClean(
      input,
    ).replaceAll(RegExp(r'[<>"\\/]'), '').trim();

    return _safeSubstring(cleaned, 50);
  }

  static String bio(String input) {
    final cleaned = _basicClean(input)
        .replaceAll(RegExp(r'[<>]'), '')
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .join('\n')
        .trim();

    return _safeSubstring(cleaned, 160);
  }

  static String stripMarkdown(String input) {
    return input
        .replaceAll(RegExp(r'\*\*\*(.+?)\*\*\*'), r'$1')
        .replaceAll(RegExp(r'\*\*(.+?)\*\*'), r'$1')
        .replaceAll(RegExp(r'_(.+?)_'), r'$1')
        .replaceAll(RegExp(r'~~(.+?)~~'), r'$1');
  }

  // optional sql-safe wrappers (for raw queries only)

  static String textForSql(String input) {
    return _stripSqlMeta(text(input));
  }

  static String usernameForSql(String input) {
    return _stripSqlMeta(username(input));
  }

  static String displayNameForSql(String input) {
    return _stripSqlMeta(displayName(input));
  }
}
