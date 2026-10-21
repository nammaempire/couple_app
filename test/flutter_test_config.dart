import 'dart:async';

import 'package:couple_app/core/widgets/motion_policy.dart';

/// Runs before every test file under `test/`: decorative looping motion
/// (drifting gradients, floating hearts, pulses) is frozen so
/// `pumpAndSettle` can settle and renders are deterministic.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  MotionPolicy.frozen = true;
  await testMain();
}
