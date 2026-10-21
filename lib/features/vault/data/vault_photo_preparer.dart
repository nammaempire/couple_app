import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';

import 'package:couple_app/features/vault/data/vault_crypto.dart';

/// A photo made ready for the vault: re-encoded JPEGs (no EXIF or location)
/// in memory.
@immutable
class PreparedPhoto {
  const PreparedPhoto({
    required this.photo,
    required this.thumb,
    required this.width,
    required this.height,
  });

  final Uint8List photo;
  final Uint8List thumb;
  final int width;
  final int height;
}

/// Picks a photo for the vault and shrinks it.
///
/// Behind an interface so tests and screenshots can skip the camera.
abstract class VaultPhotoSource {
  /// Opens the camera or gallery. Returns the photo's bytes, or null if the
  /// user backed out. The picker's temporary copy is deleted straight away.
  Future<Uint8List?> pick(ImageSource source);

  /// Downscales to [VaultPhotoPreparer.longEdge] (JPEG q85) and makes a
  /// [VaultPhotoPreparer.thumbEdge] thumbnail.
  Future<PreparedPhoto> prepare(Uint8List source);
}

/// [VaultPhotoSource] with image_picker, the engine's image decoder and the
/// `image` package's JPEG encoder (on a worker isolate).
class VaultPhotoPreparer implements VaultPhotoSource {
  VaultPhotoPreparer({ImagePicker? picker, VaultWorker? worker})
    : _picker = picker ?? ImagePicker(),
      _worker = worker ?? isolateWorker;

  static const longEdge = 2048;
  static const thumbEdge = 320;
  static const quality = 85;
  static const thumbQuality = 80;

  final ImagePicker _picker;
  final VaultWorker _worker;

  @override
  Future<Uint8List?> pick(ImageSource source) async {
    final picked = await _picker.pickImage(
      source: source,
      // Location and other EXIF data aren't needed; the photo is
      // re-encoded without them anyway.
      requestFullMetadata: false,
    );
    if (picked == null) return null;
    try {
      return await picked.readAsBytes();
    } finally {
      // The picker leaves a copy in the app's cache; don't keep it.
      try {
        await File(picked.path).delete();
      } catch (_) {}
    }
  }

  @override
  Future<PreparedPhoto> prepare(Uint8List source) async {
    final full = await _decode(source, longEdge);
    final thumb = await _decode(source, thumbEdge);
    final photoJpeg = await _encodeOn(_worker, full, quality);
    final thumbJpeg = await _encodeOn(_worker, thumb, thumbQuality);
    return PreparedPhoto(
      photo: photoJpeg,
      thumb: thumbJpeg,
      width: full.width,
      height: full.height,
    );
  }

  /// Decodes (EXIF orientation applied by the engine) at most [edge] pixels
  /// along the longer side.
  static Future<RawRgba> _decode(Uint8List bytes, int edge) async {
    final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
    final codec = await ui.instantiateImageCodecWithSize(
      buffer,
      getTargetSize: (w, h) {
        if (w >= h) return ui.TargetImageSize(width: math.min(w, edge));
        return ui.TargetImageSize(height: math.min(h, edge));
      },
    );
    final frame = await codec.getNextFrame();
    final image = frame.image;
    try {
      final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      return RawRgba(
        data!.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
        image.width,
        image.height,
      );
    } finally {
      image.dispose();
      codec.dispose();
    }
  }
}

/// Decoded pixels, ready to send to a worker.
class RawRgba {
  const RawRgba(this.rgba, this.width, this.height);
  final Uint8List rgba;
  final int width;
  final int height;
}

/// RGBA pixels to a baseline JPEG.
Uint8List encodeJpeg(RawRgba raw, int quality) {
  final image = img.Image.fromBytes(
    width: raw.width,
    height: raw.height,
    bytes: raw.rgba.buffer,
    bytesOffset: raw.rgba.offsetInBytes,
    numChannels: 4,
    order: img.ChannelOrder.rgba,
  );
  return img.encodeJpg(image, quality: quality);
}

Future<Uint8List> _encodeOn(VaultWorker worker, RawRgba raw, int quality) =>
    worker(() => encodeJpeg(raw, quality));
