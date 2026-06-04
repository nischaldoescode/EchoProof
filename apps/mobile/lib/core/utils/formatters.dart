// formatting utilities used across the app

abstract final class Formatters {
  // twitter-style time ago
  // < 60s → "just now"
  // < 60m → "42m"
  // < 24h → "6h"
  // < 7 days → "mon" (day name)
  // else → "apr 24"
  static String timeAgo(DateTime date) {
    final now = DateTime.now();
    final diff = now.difference(date);

    if (diff.inSeconds < 60) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m';
    if (diff.inHours < 24) return '${diff.inHours}h';
    if (diff.inDays < 7) return _dayName(date.weekday);

    final month = _monthAbbr(date.month);
    return '$month ${date.day}';
  }

  static String _dayName(int weekday) => const [
        'Mon',
        'Tue',
        'Wed',
        'Thu',
        'Fri',
        'Sat',
        'Sun',
      ][weekday - 1];

  static String _monthAbbr(int month) => const [
        'Jan',
        'Feb',
        'Mar',
        'Apr',
        'May',
        'Jun',
        'Jul',
        'Aug',
        'Sep',
        'Oct',
        'Nov',
        'Dec',
      ][month - 1];

  // formats lamports as readable sol amount
  static String lamportsToSol(int lamports) {
    final sol = lamports / 1000000000;
    return '${sol.toStringAsFixed(4)} SOL';
  }

  // shortens a wallet address or tx signature
  static String shortenAddress(String address, {int chars = 6}) {
    if (address.length <= chars * 2) return address;
    return '${address.substring(0, chars)}...${address.substring(address.length - chars)}';
  }

  static String compactNumber(int value) {
    if (value < 1000) return value.toString();
    if (value < 1000000) {
      final compact = value / 1000;
      return compact >= 10
          ? '${compact.toStringAsFixed(0)}K'
          : '${compact.toStringAsFixed(1).replaceAll('.0', '')}K';
    }
    final compact = value / 1000000;
    return compact >= 10
        ? '${compact.toStringAsFixed(0)}M'
        : '${compact.toStringAsFixed(1).replaceAll('.0', '')}M';
  }

  // formats a signal tag ensures ~ prefix and lowercase
  static String formatSignal(String raw) {
    final cleaned = raw.replaceAll(RegExp(r'[^a-zA-Z0-9_]'), '').toLowerCase();
    return '~$cleaned';
  }

  // extracts signal tags from echo content
  static List<String> extractSignals(String content) {
    final matches = RegExp(r'~([a-zA-Z0-9_]+)').allMatches(content);
    return matches.map((m) => m.group(0)!.toLowerCase()).toList();
  }
}
