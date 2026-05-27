import 'dart:io';
import 'sanitizer.dart';

enum MediaFileKind { image, video }

class MediaFileValidationResult {
  const MediaFileValidationResult({
    required this.kind,
    required this.extension,
    required this.sizeBytes,
    this.error,
  });

  final MediaFileKind kind;
  final String extension;
  final int sizeBytes;
  final String? error;

  bool get isValid => error == null;
}

abstract final class MediaFileSafety {
  static const maxImageBytes = 8 * 1024 * 1024;
  static const maxVideoBytes = 50 * 1024 * 1024;

  static const allowedImageExtensions = {
    'jpg',
    'jpeg',
    'png',
    'gif',
    'webp',
    'heic',
    'heif',
  };
  static const allowedVideoExtensions = {'mp4', 'mov', 'm4v', 'webm', '3gp'};
  static const _blockedExtensions = {
    'apk',
    'app',
    'bat',
    'cmd',
    'com',
    'dll',
    'dmg',
    'exe',
    'html',
    'hta',
    'jar',
    'js',
    'msi',
    'php',
    'ps1',
    'scr',
    'sh',
    'svg',
    'vbs',
  };

  static String displayName(String pathOrUrl) {
    final clean = pathOrUrl.split('?').first.split('#').first;
    final parts = clean.split(RegExp(r'[\\/]'));
    return parts.isEmpty ? clean : parts.last;
  }

  static String extensionOf(String pathOrUrl) {
    final name = displayName(pathOrUrl).toLowerCase();
    final dot = name.lastIndexOf('.');
    if (dot < 0 || dot == name.length - 1) return '';
    return name.substring(dot + 1);
  }

  static bool isImagePath(String pathOrUrl) {
    return allowedImageExtensions.contains(extensionOf(pathOrUrl));
  }

  static bool isVideoPath(String pathOrUrl) {
    return allowedVideoExtensions.contains(extensionOf(pathOrUrl));
  }

  static String contentTypeForExtension(String extension) {
    final ext = extension.toLowerCase();
    return switch (ext) {
      'jpg' || 'jpeg' => 'image/jpeg',
      'png' => 'image/png',
      'gif' => 'image/gif',
      'webp' => 'image/webp',
      'heic' => 'image/heic',
      'heif' => 'image/heif',
      'mp4' || 'm4v' => 'video/mp4',
      'mov' => 'video/quicktime',
      'webm' => 'video/webm',
      '3gp' => 'video/3gpp',
      _ => 'application/octet-stream',
    };
  }

  static Future<MediaFileValidationResult> validateLocalFile(
    String path, {
    required MediaFileKind expectedKind,
  }) async {
    final extension = extensionOf(path);
    final file = File(path);
    final maxBytes =
        expectedKind == MediaFileKind.video ? maxVideoBytes : maxImageBytes;

    MediaFileValidationResult invalid(String message, {int sizeBytes = 0}) {
      return MediaFileValidationResult(
        kind: expectedKind,
        extension: extension,
        sizeBytes: sizeBytes,
        error: message,
      );
    }

    if (path.contains('\x00')) {
      return invalid('That file path is not safe. Rename it and try again.');
    }

    final rawName = displayName(path);
    final name = Sanitizer.displayName(rawName);
    if (name.trim().isEmpty ||
        _hasSuspiciousName(rawName) ||
        _hasSuspiciousName(name)) {
      return invalid('That file name looks unsafe. Rename it and try again.');
    }

    if (extension.isEmpty ||
        _blockedExtensions.contains(extension) ||
        !_matchesExpectedKind(extension, expectedKind)) {
      return invalid(_typeMessage(expectedKind));
    }

    if (!await file.exists()) {
      return invalid('Could not read that file. Try selecting it again.');
    }

    final size = await file.length();
    if (size == 0) {
      return invalid('That file is empty. Try another one.');
    }
    if (size > maxBytes) {
      return invalid(_sizeMessage(expectedKind), sizeBytes: size);
    }

    final header = await _readHeader(file);
    final validBytes = expectedKind == MediaFileKind.video
        ? bytesMatchVideoExtension(extension, header)
        : bytesMatchImageExtension(extension, header);

    if (!validBytes) {
      return invalid(
        'That file does not look like a real ${expectedKind.name}. Try exporting it again.',
        sizeBytes: size,
      );
    }

    return MediaFileValidationResult(
      kind: expectedKind,
      extension: extension,
      sizeBytes: size,
    );
  }

  static bool bytesMatchImageExtension(String extension, List<int> bytes) {
    final ext = extension.toLowerCase();
    return switch (ext) {
      'jpg' || 'jpeg' => _isJpeg(bytes),
      'png' => _isPng(bytes),
      'gif' => _isGif(bytes),
      'webp' => _isWebp(bytes),
      'heic' ||
      'heif' =>
        _hasFtypBrand(bytes, {'heic', 'heix', 'hevc', 'hevx', 'mif1'}),
      _ => false,
    };
  }

  static bool bytesMatchVideoExtension(String extension, List<int> bytes) {
    final ext = extension.toLowerCase();
    return switch (ext) {
      'mp4' || 'm4v' => _hasFtyp(bytes),
      'mov' => _hasFtypBrand(bytes, {'qt  '}),
      'webm' => _isWebm(bytes),
      '3gp' => _hasFtypBrand(bytes, {'3gp4', '3gp5', '3gp6', '3g2a'}),
      _ => false,
    };
  }

  static bool _matchesExpectedKind(String ext, MediaFileKind kind) {
    return switch (kind) {
      MediaFileKind.image => allowedImageExtensions.contains(ext),
      MediaFileKind.video => allowedVideoExtensions.contains(ext),
    };
  }

  static bool _hasSuspiciousName(String name) {
    final lower = name.toLowerCase();
    if (lower.contains('..') || lower.contains('/') || lower.contains('\\')) {
      return true;
    }

    final parts = lower.split('.');
    if (parts.length <= 2) return false;
    final innerExtensions = parts.skip(1).take(parts.length - 2);
    return innerExtensions.any(_blockedExtensions.contains);
  }

  static Future<List<int>> _readHeader(File file) async {
    final raf = await file.open();
    try {
      return await raf.read(16);
    } finally {
      await raf.close();
    }
  }

  static bool _isJpeg(List<int> bytes) {
    return bytes.length >= 3 &&
        bytes[0] == 0xFF &&
        bytes[1] == 0xD8 &&
        bytes[2] == 0xFF;
  }

  static bool _isPng(List<int> bytes) {
    const signature = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A];
    if (bytes.length < signature.length) return false;
    for (var i = 0; i < signature.length; i++) {
      if (bytes[i] != signature[i]) return false;
    }
    return true;
  }

  static bool _isGif(List<int> bytes) {
    return bytes.length >= 6 &&
        (_ascii(bytes, 0, 6) == 'GIF87a' || _ascii(bytes, 0, 6) == 'GIF89a');
  }

  static bool _isWebp(List<int> bytes) {
    return bytes.length >= 12 &&
        _ascii(bytes, 0, 4) == 'RIFF' &&
        _ascii(bytes, 8, 12) == 'WEBP';
  }

  static bool _isWebm(List<int> bytes) {
    return bytes.length >= 4 &&
        bytes[0] == 0x1A &&
        bytes[1] == 0x45 &&
        bytes[2] == 0xDF &&
        bytes[3] == 0xA3;
  }

  static bool _hasFtyp(List<int> bytes) {
    return bytes.length >= 12 && _ascii(bytes, 4, 8) == 'ftyp';
  }

  static bool _hasFtypBrand(List<int> bytes, Set<String> brands) {
    if (!_hasFtyp(bytes)) return false;
    return brands.contains(_ascii(bytes, 8, 12).toLowerCase());
  }

  static String _ascii(List<int> bytes, int start, int end) {
    if (bytes.length < end) return '';
    return String.fromCharCodes(bytes.sublist(start, end));
  }

  static String _typeMessage(MediaFileKind kind) {
    return switch (kind) {
      MediaFileKind.image =>
        'Use a JPG, PNG, GIF, WEBP, HEIC, or HEIF image. SVG and executable files are blocked.',
      MediaFileKind.video =>
        'Use an MP4, MOV, M4V, WEBM, or 3GP video under 50 MB.',
    };
  }

  static String _sizeMessage(MediaFileKind kind) {
    return switch (kind) {
      MediaFileKind.image => 'Images must be under 8 MB.',
      MediaFileKind.video => 'Videos must be under 50 MB.',
    };
  }
}
