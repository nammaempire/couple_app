import 'package:flutter/widgets.dart';

/// One switch for decorative motion (drifting gradients, floating hearts,
/// entrance slides, bobbing envelopes).
///
/// Motion is off when the system asks for reduced motion
/// ([MediaQueryData.disableAnimations]) or when [frozen] is set. Tests set
/// [frozen] in `test/flutter_test_config.dart` so looping animations never
/// keep `pumpAndSettle` waiting, and screenshots stay deterministic.
abstract final class MotionPolicy {
  /// Freezes all decorative motion app-wide.
  static bool frozen = false;

  /// Whether decorative motion should run under [context].
  static bool enabled(BuildContext context) =>
      !frozen && !systemReduced(context);

  /// The user asked the system for reduced motion. Purely decorative layers
  /// (floating hearts) are hidden then, not just stilled.
  static bool systemReduced(BuildContext context) =>
      MediaQuery.maybeDisableAnimationsOf(context) ?? false;
}
