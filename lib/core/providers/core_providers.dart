import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:couple_app/core/services/screen_privacy.dart';
import 'package:couple_app/core/services/storage_service.dart';

/// Uploads to the Us server's file storage (profile and couple photos).
final storageServiceProvider = Provider<StorageService>(
  (ref) => StorageService(),
);

/// Reports screenshots (Android 14 and newer).
final screenshotDetectorProvider = Provider<ScreenshotDetector>(
  (ref) => PlatformScreenPrivacy.instance,
);

/// Blocks screenshots and the recent-apps preview while asked to.
final screenSecurityProvider = Provider<ScreenSecurity>(
  (ref) => PlatformScreenPrivacy.instance,
);

/// One guard for the whole app, shared by every screen that shows the
/// conversation.
final screenPrivacyGuardProvider = Provider<ScreenPrivacyGuard>((ref) {
  final guard = ScreenPrivacyGuard(
    detector: ref.watch(screenshotDetectorProvider),
    security: ref.watch(screenSecurityProvider),
  );
  ref.onDispose(guard.dispose);
  return guard;
});
