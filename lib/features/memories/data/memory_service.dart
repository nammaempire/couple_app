import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fc_native_video_thumbnail/fc_native_video_thumbnail.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:uuid/uuid.dart';

import 'package:couple_app/features/memories/models/memory.dart';

/// A photo or video picked on this device, not uploaded yet.
class PendingMedia {
  const PendingMedia({
    required this.file,
    required this.isVideo,
    this.duration,
  });

  final File file;
  final bool isVideo;
  final Duration? duration;
}

/// Thrown when a memory cannot be saved for a reason worth explaining.
class MemoryException implements Exception {
  MemoryException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Reads and writes `couples/{coupleId}/memories`, with media stored under
/// `couples/{coupleId}/memories/` in Storage.
class MemoryService {
  MemoryService({FirebaseFirestore? firestore, FirebaseStorage? storage})
    : _db = firestore ?? FirebaseFirestore.instance,
      _storageOverride = storage;

  final FirebaseFirestore _db;
  final FirebaseStorage? _storageOverride;
  FirebaseStorage get _storage => _storageOverride ?? FirebaseStorage.instance;
  static final _uuid = Uuid();

  static const maxMediaPerMemory = 20;
  static const maxVideoBytes = 100 * 1024 * 1024;

  CollectionReference<Map<String, dynamic>> _memories(String coupleId) =>
      _db.collection('couples').doc(coupleId).collection('memories');

  /// Every memory, newest first by the date it happened.
  Stream<List<Memory>> watchMemories(String coupleId) {
    return _memories(coupleId)
        .orderBy('date', descending: true)
        .snapshots()
        .map((snap) => snap.docs.map(Memory.fromDoc).toList());
  }

  /// One memory, live. Emits null once it is deleted.
  Stream<Memory?> watchMemory(String coupleId, String memoryId) {
    return _memories(coupleId)
        .doc(memoryId)
        .snapshots()
        .map((doc) => doc.exists ? Memory.fromDoc(doc) : null);
  }

  /// Creates a memory, uploading [newMedia] first. [onProgress] reports
  /// 0.0–1.0 across all files.
  Future<void> create({
    required String coupleId,
    required String createdBy,
    required String title,
    required String caption,
    required DateTime date,
    required String? place,
    required String album,
    required List<PendingMedia> newMedia,
    void Function(double progress)? onProgress,
  }) async {
    final uploaded = await _uploadAll(coupleId, newMedia, onProgress);
    await _memories(coupleId).add({
      ..._fields(title, caption, date, place, album),
      'media': uploaded.map((m) => m.toMap()).toList(),
      'favorite': false,
      'createdBy': createdBy,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  /// Updates details and media. [keptMedia] are existing items to keep;
  /// removed ones are deleted from Storage after the save.
  Future<void> update({
    required String coupleId,
    required Memory memory,
    required String title,
    required String caption,
    required DateTime date,
    required String? place,
    required String album,
    required List<MemoryMedia> keptMedia,
    required List<PendingMedia> newMedia,
    void Function(double progress)? onProgress,
  }) async {
    final uploaded = await _uploadAll(coupleId, newMedia, onProgress);

    // Only the items this editor removed are dropped. Anything the partner
    // added meanwhile is kept, by re-reading the latest list in a
    // transaction.
    final keptUrls = keptMedia.map((m) => m.url).toSet();
    final removedUrls = memory.media
        .map((m) => m.url)
        .where((url) => !keptUrls.contains(url))
        .toSet();
    final ref = _memories(coupleId).doc(memory.id);

    await _db.runTransaction((tx) async {
      final snap = await tx.get(ref);
      if (!snap.exists) {
        throw MemoryException('This memory was deleted.');
      }
      final latest = Memory.fromDoc(snap).media;
      final merged = [
        ...latest.where((m) => !removedUrls.contains(m.url)),
        ...uploaded,
      ];
      tx.update(ref, {
        ..._fields(title, caption, date, place, album),
        'media': merged.map((m) => m.toMap()).toList(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    });

    for (final removed in memory.media) {
      if (!removedUrls.contains(removed.url)) continue;
      await _deleteQuietly(removed.url);
      if (removed.thumbUrl != null) await _deleteQuietly(removed.thumbUrl!);
    }
  }

  Future<void> setFavorite({
    required String coupleId,
    required String memoryId,
    required bool favorite,
  }) {
    return _memories(coupleId).doc(memoryId).update({'favorite': favorite});
  }

  Future<void> delete({
    required String coupleId,
    required Memory memory,
  }) async {
    await _memories(coupleId).doc(memory.id).delete();
    for (final m in memory.media) {
      await _deleteQuietly(m.url);
      if (m.thumbUrl != null) await _deleteQuietly(m.thumbUrl!);
    }
  }

  Map<String, dynamic> _fields(
    String title,
    String caption,
    DateTime date,
    String? place,
    String album,
  ) {
    final trimmedPlace = place?.trim();
    return {
      'title': title.trim(),
      'caption': caption.trim(),
      'date': Timestamp.fromDate(date),
      'place': (trimmedPlace == null || trimmedPlace.isEmpty)
          ? null
          : trimmedPlace,
      'album': album.trim().isEmpty ? MemoryAlbums.randomMoments : album.trim(),
    };
  }

  Future<List<MemoryMedia>> _uploadAll(
    String coupleId,
    List<PendingMedia> items,
    void Function(double progress)? onProgress,
  ) async {
    for (final item in items) {
      if (item.isVideo && await item.file.length() > maxVideoBytes) {
        throw MemoryException('A video is over 100 MB. Choose a shorter one.');
      }
    }

    final results = <MemoryMedia>[];
    for (var i = 0; i < items.length; i++) {
      void report(double fileProgress) =>
          onProgress?.call((i + fileProgress) / items.length);
      results.add(await _uploadOne(coupleId, items[i], report));
    }
    onProgress?.call(1);
    return results;
  }

  Future<MemoryMedia> _uploadOne(
    String coupleId,
    PendingMedia item,
    void Function(double) onProgress,
  ) async {
    final folder = 'couples/$coupleId/memories';

    if (!item.isVideo) {
      final bytes = await item.file.readAsBytes();
      final url = await _put(
        '$folder/${_uuid.v4()}${_ext(item.file.path, '.jpg')}',
        item.file,
        _imageType(item.file.path),
        onProgress,
      );
      return MemoryMedia(
        type: MemoryMediaType.image,
        url: url,
        aspectRatio: await _aspectRatioOf(bytes),
      );
    }

    String? thumbUrl;
    double? aspectRatio;
    try {
      final jpeg = await FcNativeVideoThumbnail().saveThumbnailToBytes(
        srcFile: item.file.path,
        width: 720,
        height: 720,
        format: 'jpeg',
        quality: 75,
      );
      if (jpeg != null) {
        aspectRatio = await _aspectRatioOf(jpeg);
        final ref = _storage.ref('$folder/${_uuid.v4()}.jpg');
        await ref.putData(jpeg, SettableMetadata(contentType: 'image/jpeg'));
        thumbUrl = await ref.getDownloadURL();
      }
    } catch (_) {
      // A video without a thumbnail still plays.
    }

    final ext = _ext(item.file.path, '.mp4');
    final url = await _put(
      '$folder/${_uuid.v4()}$ext',
      item.file,
      ext == '.mov' ? 'video/quicktime' : 'video/mp4',
      onProgress,
    );
    return MemoryMedia(
      type: MemoryMediaType.video,
      url: url,
      thumbUrl: thumbUrl,
      aspectRatio: aspectRatio,
      durationMs: item.duration?.inMilliseconds,
    );
  }

  Future<String> _put(
    String path,
    File file,
    String contentType,
    void Function(double) onProgress,
  ) async {
    final ref = _storage.ref(path);
    final task = ref.putFile(file, SettableMetadata(contentType: contentType));
    final sub = task.snapshotEvents.listen(
      (s) {
        if (s.totalBytes > 0) onProgress(s.bytesTransferred / s.totalBytes);
      },
      // The failure is reported by `await task` below.
      onError: (_) {},
    );
    try {
      await task;
    } finally {
      await sub.cancel();
    }
    return ref.getDownloadURL();
  }

  Future<void> _deleteQuietly(String url) async {
    try {
      await _storage.refFromURL(url).delete();
    } catch (_) {}
  }

  static String _ext(String path, String fallback) {
    final dot = path.lastIndexOf('.');
    if (dot == -1 || dot == path.length - 1) return fallback;
    return path.substring(dot).toLowerCase();
  }

  static String _imageType(String path) => switch (_ext(path, '.jpg')) {
    '.png' => 'image/png',
    '.webp' => 'image/webp',
    '.heic' => 'image/heic',
    '.gif' => 'image/gif',
    _ => 'image/jpeg',
  };

  Future<double?> _aspectRatioOf(Uint8List bytes) async {
    try {
      final descriptor = await ui.ImageDescriptor.encoded(
        await ui.ImmutableBuffer.fromUint8List(bytes),
      );
      final ratio = descriptor.width / descriptor.height;
      descriptor.dispose();
      return ratio;
    } catch (_) {
      return null;
    }
  }
}
