// input validators for forms throughout the app

abstract final class Validators {
  static String? email(String? value) {
    if (value == null || value.trim().isEmpty) return 'email is required';
    if (!RegExp(r'^[^@]+@[^@]+\.[^@]+').hasMatch(value)) return 'enter a valid email';
    return null;
  }

  static String? password(String? value) {
    if (value == null || value.isEmpty) return 'password is required';
    if (value.length < 8) return 'minimum 8 characters';
    return null;
  }

  static String? username(String? value) {
    if (value == null || value.trim().isEmpty) return 'username is required';
    if (value.length < 4) return 'minimum 4 characters';
    if (!RegExp(r'^[a-z0-9_]+$').hasMatch(value)) {
      return 'only lowercase letters, numbers, and underscores';
    }
    return null;
  }

  static String? echoTitle(String? value) {
    if (value == null || value.trim().isEmpty) return 'title is required';
    if (value.length > 120) return 'maximum 120 characters';
    return null;
  }

  static String? echoContent(String? value) {
    if (value == null || value.trim().isEmpty) return 'content is required';
    if (value.length > 2000) return 'maximum 2000 characters';
    return null;
  }
}