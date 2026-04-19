// formatting utilities used across the app

abstract final class Formatters {
  // formats a datetime as a relative time string
  static String timeAgo(DateTime dateTime) {
    final diff = DateTime.now().difference(dateTime);
    if (diff.inSeconds < 60) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    if (diff.inDays < 30) return '${(diff.inDays / 7).floor()}w ago';
    return '${(diff.inDays / 30).floor()}mo ago';
  }

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

  // formats a signal tag — ensures ~ prefix and lowercase
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
