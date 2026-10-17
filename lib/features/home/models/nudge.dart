import 'package:couple_app/features/home/models/love_tap.dart';

/// A one-tap love message ("nudge") that buzzes the partner's phone.
class Nudge {
  final String id;
  final String senderId;
  final DateTime? sentAt;
  final LoveTap kind;

  const Nudge({
    required this.id,
    required this.senderId,
    this.sentAt,
    this.kind = LoveTap.thinking,
  });

  /// Nudges older than this are treated as history, not a live buzz, so
  /// reopening the app does not replay old ones.
  static const freshWindow = Duration(minutes: 2);

  bool get isFresh {
    final at = sentAt;
    if (at == null) return false;
    return DateTime.now().difference(at) < freshWindow;
  }
}
