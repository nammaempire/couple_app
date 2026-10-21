import 'dart:isolate';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:image/image.dart' as img;

import 'package:couple_app/features/avatar/models/avatar_config.dart';
import 'package:couple_app/features/avatar/painting/avatar_painter.dart';

/// Fetches a book's photos and makes them print-sized. Behind an interface
/// so tests can fake it.
abstract class BookImageSource {
  /// The photo at [url] as a JPEG at most [maxEdge] px on its long edge,
  /// or null if it can't be fetched.
  Future<Uint8List?> fetch(String url, {int maxEdge = 1600});
}

/// Downloads through the app's image cache, then shrinks off the UI
/// thread.
class CachedBookImageSource implements BookImageSource {
  @override
  Future<Uint8List?> fetch(String url, {int maxEdge = 1600}) async {
    try {
      final file = await DefaultCacheManager().getSingleFile(url);
      final bytes = await file.readAsBytes();
      return await Isolate.run(() => shrinkJpeg(bytes, maxEdge: maxEdge));
    } catch (e) {
      debugPrint('Book photo skipped ($url): $e');
      return null;
    }
  }
}

/// Re-encodes [bytes] as a JPEG no larger than [maxEdge] on its long edge.
/// Returns null if it isn't an image.
Uint8List? shrinkJpeg(Uint8List bytes, {int maxEdge = 1600, int quality = 82}) {
  final decoded = img.decodeImage(bytes);
  if (decoded == null) return null;
  final oriented = img.bakeOrientation(decoded);
  final long = oriented.width > oriented.height
      ? oriented.width
      : oriented.height;
  final sized = long <= maxEdge
      ? oriented
      : oriented.width >= oriented.height
      ? img.copyResize(oriented, width: maxEdge)
      : img.copyResize(oriented, height: maxEdge);
  return Uint8List.fromList(img.encodeJpg(sized, quality: quality));
}

/// Draws [config] (the cartoon avatar) into a round PNG for the cover,
/// with the same painter `AvatarView` uses.
Future<Uint8List?> renderAvatarPng(
  AvatarConfig config, {
  double size = 480,
}) async {
  try {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final rect = Offset.zero & Size(size, size);
    canvas.clipPath(Path()..addOval(rect));
    AvatarPainter(
      config: config,
      expression: AvatarExpression.happy,
    ).paint(canvas, rect.size);
    final picture = recorder.endRecording();
    final image = await picture.toImage(size.round(), size.round());
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    picture.dispose();
    return data?.buffer.asUint8List();
  } catch (e) {
    debugPrint('Avatar for the cover failed: $e');
    return null;
  }
}
