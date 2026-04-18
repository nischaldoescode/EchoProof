// string extension methods used throughout the app

extension StringExtensions on String {
  // capitalizes first letter only
  String get capitalized {
    if (isEmpty) return this;
    return '${this[0].toUpperCase()}${substring(1)}';
  }

  // returns true if string looks like a valid email
  bool get isValidEmail =>
      RegExp(r'^[^@]+@[^@]+\.[^@]+').hasMatch(this);

  // extracts signal tags (~word) from text
  List<String> get signals {
    final matches = RegExp(r'~([a-zA-Z0-9_]+)').allMatches(this);
    return matches.map((m) => m.group(0)!.toLowerCase()).toList();
  }

  // replaces signal tags in text with a styled span
  // used for rendering echo content with highlighted signals
  String get withoutSignals =>
      replaceAll(RegExp(r'~[a-zA-Z0-9_]+'), '').trim();

  // truncates with ellipsis
  String truncate(int maxLength) {
    if (length <= maxLength) return this;
    return '${substring(0, maxLength)}...';
  }
}