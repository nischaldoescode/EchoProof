// verification error parser
// @params none

import 'dart:convert';

class VerificationErrorParser {
  const VerificationErrorParser._();

  static const fallbackMessage =
      'Could not start verification. Please try again.';

  static String messageFrom(Object error) {
    final serverMessage = _extractServerMessage(error);
    if (serverMessage != null && serverMessage.trim().isNotEmpty) {
      return serverMessage.trim();
    }

    return messageFromCode(_extractCode(error)) ?? fallbackMessage;
  }

  static String? messageFromResponseData(Object? data) {
    final map = mapFromResponseData(data);
    if (map == null || map['error'] == null) return null;

    final serverMessage = _messageFromValue(map);
    if (serverMessage != null && serverMessage.trim().isNotEmpty) {
      return serverMessage.trim();
    }

    return messageFromCode(map['error']?.toString()) ?? fallbackMessage;
  }

  static bool blocksNavigation(Object error) =>
      _blocksCode(_extractCode(error)) ||
      _blocksRaw(error.toString()) ||
      _blocksText(_extractServerMessage(error) ?? '');

  static bool responseDataBlocks(Object? data) {
    final map = mapFromResponseData(data);
    if (map == null || map['error'] == null) return false;
    return _blocksCode(map['error']?.toString()) ||
        _blocksText(map['message']?.toString() ?? '');
  }

  static Map<String, dynamic>? mapFromResponseData(Object? data) {
    if (data is Map) return Map<String, dynamic>.from(data);

    if (data is String) {
      final decoded = _decodeJsonObject(data);
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
    }

    return null;
  }

  static String? messageFromCode(String? code) {
    final raw = code ?? '';
    if (raw.contains('verification_account_limit')) {
      return 'You have reached the maximum of 2 verification attempts per month per account.';
    }
    if (raw.contains('verification_ip_limit')) {
      return 'Too many verification attempts from this network. Please try again later.';
    }
    if (raw.contains('verification_cooldown')) {
      return 'You can re-apply after your 30-day cooldown period.';
    }
    if (raw.contains('didit_not_configured') ||
        raw.contains('didit_workflow_missing') ||
        raw.contains('DIDIT_API_KEY')) {
      return 'Identity verification is not configured yet.';
    }
    if (raw.contains('didit_session_failed')) {
      return 'The verification provider could not start a session. Please try again later.';
    }
    if (raw.contains('auth_required')) {
      return 'Sign in again to continue.';
    }
    return null;
  }

  static bool _blocksCode(String? code) {
    final raw = code ?? '';
    return raw.contains('verification_account_limit') ||
        raw.contains('verification_ip_limit') ||
        raw.contains('verification_cooldown') ||
        raw.contains('didit_not_configured') ||
        raw.contains('didit_workflow_missing') ||
        raw.contains('auth_required');
  }

  static bool _blocksRaw(String raw) =>
      raw.contains('verification_account_limit') ||
      raw.contains('verification_ip_limit') ||
      raw.contains('verification_cooldown') ||
      raw.contains('didit_not_configured') ||
      raw.contains('didit_workflow_missing') ||
      raw.contains('auth_required');

  static bool _blocksText(String raw) =>
      raw.contains('maximum of 2 verification attempts') ||
      raw.contains('Too many verification attempts') ||
      raw.contains('30-day cooldown') ||
      raw.contains('not configured yet') ||
      raw.contains('Sign in again');

  static String _extractCode(Object error) {
    Object? details;
    try {
      details = (error as dynamic).details;
    } catch (_) {}

    final fromDetails = _codeFromValue(details);
    if (fromDetails != null) return fromDetails;

    return _codeFromValue(error.toString()) ?? error.toString();
  }

  static String? _extractServerMessage(Object error) {
    Object? details;
    try {
      details = (error as dynamic).details;
    } catch (_) {}

    final fromDetails = _messageFromValue(details);
    if (fromDetails != null) return fromDetails;

    return _messageFromValue(error.toString());
  }

  static String? _codeFromValue(Object? value) {
    if (value is Map) {
      final code = value['error'];
      if (code is String && code.trim().isNotEmpty) return code;
    }

    if (value is String) {
      final decoded = _decodeJsonObject(value);
      if (decoded != null) return _codeFromValue(decoded);
    }

    return null;
  }

  static String? _messageFromValue(Object? value) {
    if (value is Map) {
      final message = value['message'];
      if (message is String && message.trim().isNotEmpty) return message;
    }

    if (value is String) {
      final decoded = _decodeJsonObject(value);
      if (decoded != null) {
        final message = _messageFromValue(decoded);
        if (message != null) return message;
      }

      final match = RegExp(r'message["\s:=]+([^,}\n]+)').firstMatch(value);
      final message = match?.group(1)?.replaceAll('"', '').trim();
      if (message != null && message.isNotEmpty) return message;
    }

    return null;
  }

  static Object? _decodeJsonObject(String value) {
    final jsonStart = value.indexOf('{');
    final jsonEnd = value.lastIndexOf('}');
    if (jsonStart < 0 || jsonEnd <= jsonStart) return null;

    try {
      return jsonDecode(value.substring(jsonStart, jsonEnd + 1));
    } catch (_) {
      return null;
    }
  }
}
