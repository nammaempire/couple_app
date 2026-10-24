import 'dart:io';
import 'dart:typed_data';

import 'package:couple_app/core/backend/backend.dart';
import 'package:uuid/uuid.dart';

/// Uploads chat media and profile pictures to the Us server's file storage.
class StorageService {
  StorageService({Files? files}) : _storage = files ?? Files.instance;

  final Files _storage;
  static final _uuid = Uuid();

  /// Uploads [file] and returns its public download URL.
  ///
  /// [onProgress] receives a value from 0.0 to 1.0.
  Future<String> uploadChatPhoto({
    required String coupleId,
    required File file,
    void Function(double progress)? onProgress,
  }) {
    return _upload(
      folder: 'couples/$coupleId/photos',
      file: file,
      onProgress: onProgress,
    );
  }

  /// A chat video, under `couples/{coupleId}/videos/`.
  Future<String> uploadChatVideo({
    required String coupleId,
    required File file,
    void Function(double progress)? onProgress,
  }) {
    return _upload(
      folder: 'couples/$coupleId/videos',
      file: file,
      onProgress: onProgress,
    );
  }

  /// A voice message, under `couples/{coupleId}/voice/`.
  Future<String> uploadVoice({required String coupleId, required File file}) {
    return _upload(folder: 'couples/$coupleId/voice', file: file);
  }

  /// A JPEG video thumbnail, stored with chat photos.
  Future<String> uploadThumbnail({
    required String coupleId,
    required Uint8List jpeg,
  }) async {
    final ref = _storage.ref('couples/$coupleId/photos/${_uuid.v4()}.jpg');
    await ref.putData(jpeg, SettableMetadata(contentType: 'image/jpeg'));
    return ref.getDownloadURL();
  }

  /// A user's own profile picture, under `users/{uid}/profile/`.
  Future<String> uploadProfilePhoto({required String uid, required File file}) {
    return _upload(folder: 'users/$uid/profile', file: file);
  }

  /// The shared couple picture, under `couples/{coupleId}/profile/`.
  Future<String> uploadCouplePhoto({
    required String coupleId,
    required File file,
  }) {
    return _upload(folder: 'couples/$coupleId/profile', file: file);
  }

  Future<String> _upload({
    required String folder,
    required File file,
    void Function(double progress)? onProgress,
  }) async {
    final ext = _extensionOf(file.path);
    final ref = _storage.ref('$folder/${_uuid.v4()}$ext');

    final task = ref.putFile(
      file,
      SettableMetadata(contentType: _contentTypeFor(ext)),
    );

    if (onProgress != null) {
      task.snapshotEvents.listen((snap) {
        if (snap.totalBytes > 0) {
          onProgress(snap.bytesTransferred / snap.totalBytes);
        }
      });
    }

    await task;
    return ref.getDownloadURL();
  }

  Future<void> deleteByUrl(String url) async {
    await _storage.refFromURL(url).delete();
  }

  String _extensionOf(String path) {
    final dot = path.lastIndexOf('.');
    if (dot == -1 || dot == path.length - 1) return '.jpg';
    return path.substring(dot).toLowerCase();
  }

  String _contentTypeFor(String ext) {
    switch (ext) {
      case '.png':
        return 'image/png';
      case '.gif':
        return 'image/gif';
      case '.webp':
        return 'image/webp';
      case '.heic':
        return 'image/heic';
      case '.mp4':
        return 'video/mp4';
      case '.mov':
        return 'video/quicktime';
      case '.3gp':
        return 'video/3gpp';
      case '.webm':
        return 'video/webm';
      case '.m4a':
      case '.aac':
        return 'audio/mp4';
      default:
        return 'image/jpeg';
    }
  }
}
