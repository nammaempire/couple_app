import 'dart:io';
import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' show Color, Offset, Rect;

import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:image/image.dart' as img;

import 'package:couple_app/features/avatar/models/avatar_config.dart';

/// What a selfie scan made: the avatar, and what it matched, for
/// "Matched your skin tone, hair colour…".
class SelfieAvatar {
  const SelfieAvatar(this.avatar, this.matched);

  final AvatarConfig avatar;
  final List<String> matched;

  String get summary => matched.join(', ');
}

/// Builds an avatar from a live selfie, on the phone: ML Kit finds the face,
/// then colours are sampled around it (cheeks for skin, above the head for
/// hair, beside the jaw for long hair, the chin for a beard, below for the
/// outfit) and matched to the nearest avatar options. Parts a photo can't
/// tell (eyes, accessories, outfit style) are kept from [base].
///
/// The photo is deleted as soon as it has been read, whatever happens, and
/// is never uploaded.
abstract final class SelfieAvatarScanner {
  /// Returns null when no face was found.
  static Future<SelfieAvatar?> scan(
    String photoPath, {
    required AvatarConfig base,
  }) async {
    final detector = FaceDetector(
      options: FaceDetectorOptions(
        enableLandmarks: true,
        performanceMode: FaceDetectorMode.accurate,
      ),
    );
    try {
      final faces = await detector.processImage(
        InputImage.fromFilePath(photoPath),
      );
      if (faces.isEmpty) return null;
      // The biggest face is the person holding the phone.
      final face = faces.reduce(
        (a, b) =>
            a.boundingBox.width * a.boundingBox.height >=
                b.boundingBox.width * b.boundingBox.height
            ? a
            : b,
      );
      Offset? at(FaceLandmarkType type) {
        final p = face.landmarks[type]?.position;
        return p == null ? null : Offset(p.x.toDouble(), p.y.toDouble());
      }

      final bytes = await File(photoPath).readAsBytes();
      final box = face.boundingBox;
      final leftCheek = at(FaceLandmarkType.leftCheek);
      final rightCheek = at(FaceLandmarkType.rightCheek);
      // Decoding and sampling take a moment: off the UI thread.
      return await _readOffThread(bytes, box, leftCheek, rightCheek, base);
    } finally {
      await detector.close();
      try {
        await File(photoPath).delete();
      } catch (_) {}
    }
  }

  /// Kept separate so the isolate is only handed plain data.
  static Future<SelfieAvatar?> _readOffThread(
    Uint8List bytes,
    Rect face,
    Offset? leftCheek,
    Offset? rightCheek,
    AvatarConfig base,
  ) => Isolate.run(() {
    final decoded = img.decodeImage(bytes);
    if (decoded == null) return null;
    return fromImage(
      img.bakeOrientation(decoded),
      face: face,
      leftCheek: leftCheek,
      rightCheek: rightCheek,
      base: base,
    );
  });

  /// The avatar for [image], with the face at [face] (image pixels).
  static SelfieAvatar fromImage(
    img.Image image, {
    required Rect face,
    Offset? leftCheek,
    Offset? rightCheek,
    required AvatarConfig base,
  }) {
    final s = _Sampler(image);
    final w = face.width;
    final h = face.height;
    final cx = face.center.dx;

    final skin =
        _avg([
          leftCheek != null
              ? s.at(leftCheek.dx, leftCheek.dy, w * .05)
              : s.at(face.left + w * .25, face.top + h * .6, w * .05),
          rightCheek != null
              ? s.at(rightCheek.dx, rightCheek.dy, w * .05)
              : s.at(face.right - w * .25, face.top + h * .6, w * .05),
          s.at(cx, face.top + h * .18, w * .05), // forehead
        ]) ??
        const _Rgb(220, 175, 140);
    final hair = _avg([
      s.at(cx, face.top - h * .1, w * .07),
      s.at(face.left + w * .3, face.top - h * .05, w * .05),
      s.at(face.right - w * .3, face.top - h * .05, w * .05),
    ]);
    final sides = _avg([
      s.at(face.left - w * .1, face.top + h * .85, w * .05),
      s.at(face.right + w * .1, face.top + h * .85, w * .05),
    ]);
    final chin = _avg([
      s.at(cx, face.bottom - h * .07, w * .05),
      s.at(face.left + w * .27, face.bottom - h * .17, w * .04),
      s.at(face.right - w * .27, face.bottom - h * .17, w * .04),
    ]);
    final shirt = s.at(
      cx,
      min(image.height - 2.0, face.bottom + h * .45),
      w * .12,
    );

    var avatar = base;
    final matched = <String>[];

    // Skin tone. Phone photos come out a little darker than life.
    avatar = avatar.copyWith(
      skin: _nearestBy(
        AvatarConfig.skins,
        (c) => (_Rgb.of(c).luminance - skin.luminance * 1.1).abs(),
      ),
    );
    matched.add('skin tone');

    // Hair: the same colour as the skin above the forehead means bald.
    var longHair = false;
    if (hair != null) {
      if (hair.distanceTo(skin) < 40) {
        avatar = avatar.copyWith(hair: 'bald');
        matched.add('bald look');
      } else if (hair.luminance < .85) {
        longHair = sides != null && sides.distanceTo(hair) < 50;
        final natural = AvatarConfig.hairColors.take(6).toList();
        avatar = avatar.copyWith(
          hairColor: _nearestBy(natural, (c) => _Rgb.of(c).distanceTo(hair)),
          hair: _hairStyle(base.hair, longHair: longHair),
        );
        matched.add('hair colour');
      }
    }

    // A chin clearly darker than the cheeks: a beard or stubble. Long hair
    // shades the jaw, so it isn't read as a beard.
    if (chin != null && !longHair) {
      final ratio = chin.luminance / max(.01, skin.luminance);
      final beard = ratio < .6
          ? 'beard'
          : ratio < .75
          ? 'stubble'
          : 'none';
      avatar = avatar.copyWith(facialHair: beard);
      if (beard != 'none') matched.add('beard');
    } else {
      avatar = avatar.copyWith(facialHair: 'none');
    }

    if (shirt != null) {
      avatar = avatar.copyWith(
        outfitColor: _nearestBy(
          AvatarConfig.outfitColors,
          (c) => _Rgb.of(c).distanceTo(shirt),
        ),
      );
      matched.add('outfit colour');
    }

    return SelfieAvatar(avatar, matched);
  }

  /// Keeps the current style when it already fits the length the photo
  /// shows, so a bun or braids aren't swapped for a generic cut.
  static String _hairStyle(String current, {required bool longHair}) {
    const long = {'long', 'wavy', 'ponytail', 'braids', 'bob', 'bun'};
    const short = {'short', 'buzz', 'side', 'quiff', 'curly', 'afro'};
    if (longHair) return long.contains(current) ? current : 'long';
    return short.contains(current) ? current : 'short';
  }

  static String _nearestBy(
    List<AvatarSwatch> swatches,
    double Function(Color) distance,
  ) {
    var best = swatches.first;
    var bestD = double.infinity;
    for (final s in swatches) {
      final d = distance(s.color);
      if (d < bestD) {
        best = s;
        bestD = d;
      }
    }
    return best.id;
  }

  static _Rgb? _avg(List<_Rgb?> samples) {
    final v = samples.whereType<_Rgb>().toList();
    if (v.isEmpty) return null;
    return _Rgb(
      v.fold<double>(0, (t, c) => t + c.r) / v.length,
      v.fold<double>(0, (t, c) => t + c.g) / v.length,
      v.fold<double>(0, (t, c) => t + c.b) / v.length,
    );
  }
}

class _Rgb {
  const _Rgb(this.r, this.g, this.b);

  factory _Rgb.of(Color c) => _Rgb(c.r * 255, c.g * 255, c.b * 255);

  final double r;
  final double g;
  final double b;

  /// 0 (black) to 1 (white).
  double get luminance => (.299 * r + .587 * g + .114 * b) / 255;

  double distanceTo(_Rgb o) {
    final dr = r - o.r;
    final dg = g - o.g;
    final db = b - o.b;
    return sqrt(dr * dr + dg * dg + db * db);
  }
}

class _Sampler {
  _Sampler(this.image);

  final img.Image image;

  /// The typical colour of a square of radius [r] around ([x], [y]):
  /// the middle 60% by brightness, so highlights and shadows don't skew it.
  /// Null when the square falls (mostly) outside the photo.
  _Rgb? at(double x, double y, double r) {
    final wMax = image.width - 1;
    final hMax = image.height - 1;
    final x0 = (x - r).round().clamp(0, wMax);
    final x1 = (x + r).round().clamp(0, wMax);
    final y0 = (y - r).round().clamp(0, hMax);
    final y1 = (y + r).round().clamp(0, hMax);
    if (x1 - x0 < 2 || y1 - y0 < 2) return null;
    final step = max(1, ((x1 - x0) / 12).floor());
    final px = <_Rgb>[];
    for (var yy = y0; yy <= y1; yy += step) {
      for (var xx = x0; xx <= x1; xx += step) {
        final p = image.getPixel(xx, yy);
        px.add(_Rgb(p.r.toDouble(), p.g.toDouble(), p.b.toDouble()));
      }
    }
    px.sort((a, b) => a.luminance.compareTo(b.luminance));
    final from = (px.length * .2).floor();
    final to = max((px.length * .8).ceil(), from + 1);
    return SelfieAvatarScanner._avg(px.sublist(from, to));
  }
}
