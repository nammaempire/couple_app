import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import 'package:couple_app/features/app_lock/app_lock_controller.dart';

/// The message sent with an invite code.
String inviteShareText(String code) =>
    'Join me on Us 💞\n\n'
    'It\'s a private space just for the two of us. Install the app, tap '
    '"I have an invite" and enter our code: $code';

/// Opens the system share sheet with [text]. The app lock is paused while
/// it is open.
typedef InviteSharer = Future<void> Function(String text);

/// The share sheet for invites. Tests replace it to see what was shared.
final inviteSharerProvider = Provider<InviteSharer>((ref) {
  return (text) => ref
      .read(appLockControllerProvider.notifier)
      .suspendWhile(
        SharePlus.instance.share(
          ShareParams(text: text, subject: 'Join me on Us'),
        ),
      );
});
