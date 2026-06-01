// storage service
// handles all file uploads to supabase storage
// enforces: 1mb limit, images only (jpg png webp), no video
// stores public url never stores binary data in the database

import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';
import '../utils/logger.dart';
import '../utils/media_file_safety.dart';

const _maxFileSizeBytes = 1024 * 1024; // 1 mb

const _allowedExtensions = ['jpg', 'jpeg', 'png', 'webp'];

class StorageException implements Exception {
  final String message;
  const StorageException(this.message);
  @override
  String toString() => message;
}

class UploadResult {
  const UploadResult({required this.publicUrl, required this.storagePath});
  final String publicUrl;
  final String storagePath;
}

class StorageService {
  StorageService(this._client);

  final SupabaseClient _client;
  final _uuid = const Uuid();

  // picks an image file and validates it before returning bytes.
  // throws StorageException if file is too large or wrong type.
  Future<PlatformFile?> pickProofImage() async {
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: _allowedExtensions,
      withData: true,
      allowMultiple: false,
    );

    if (result == null || result.files.isEmpty) return null;

    final file = result.files.first;

    if (file.bytes == null) {
      throw const StorageException('could not read file — try again');
    }

    if (file.size > _maxFileSizeBytes) {
      throw const StorageException('image must be under 1 MB');
    }

    final ext = file.extension?.toLowerCase() ?? '';
    if (!_allowedExtensions.contains(ext)) {
      throw StorageException(
          'only ${_allowedExtensions.join(", ")} files allowed');
    }

    final header = file.bytes!.take(16).toList();
    if (!MediaFileSafety.bytesMatchImageExtension(ext, header)) {
      throw const StorageException('image file looks invalid or corrupted');
    }

    AppLogger.info('storage: picked file ${file.name} ${file.size} bytes');
    return file;
  }

  // uploads proof image for an echo.
  // path format: echo-proofs/{echoId}/{uuid}.{ext}
  // returns public url stored in echo_proofs table
  Future<UploadResult> uploadProofImage({
    required String echoId,
    required Uint8List bytes,
    required String extension,
  }) async {
    final path = '$echoId/${_uuid.v4()}.$extension';
    final contentType = MediaFileSafety.contentTypeForExtension(extension);

    AppLogger.info('storage: uploading proof $path');

    try {
      await _client.storage.from('echo-proofs').uploadBinary(
            path,
            bytes,
            fileOptions: FileOptions(contentType: contentType, upsert: false),
          );
    } on StorageException catch (e) {
      AppLogger.error('storage: upload failed $e');
      rethrow;
    }

    final publicUrl = _client.storage.from('echo-proofs').getPublicUrl(path);

    AppLogger.info('storage: uploaded successfully');
    return UploadResult(publicUrl: publicUrl, storagePath: path);
  }

  // deletes a proof from storage called when a proof is removed
  Future<void> deleteProof(String storagePath) async {
    await _client.storage.from('echo-proofs').remove([storagePath]);
    AppLogger.info('storage: deleted $storagePath');
  }
}
