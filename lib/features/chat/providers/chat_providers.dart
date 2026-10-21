import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:couple_app/core/providers/core_providers.dart';
import 'package:couple_app/features/auth/providers/auth_providers.dart';
import 'package:couple_app/features/chat/data/chat_service.dart';
import 'package:couple_app/features/couple/providers/couple_providers.dart';

final chatServiceProvider = Provider<ChatService>(
  (ref) => ChatService(storage: ref.watch(storageServiceProvider)),
);

/// Messages sent at or before this are hidden on this phone: the later of
/// "clear for me" (this user's own) and "clear for both" (the couple's,
/// whose messages are being deleted). Null when the chat was never cleared.
final chatClearedAtProvider = Provider.autoDispose<DateTime?>((ref) {
  final mine = ref.watch(
    currentUserProvider.select((user) => user.chatClearedAt),
  );
  final both = ref.watch(
    coupleProvider.select((couple) => couple.value?.chatClearedAt),
  );
  if (mine == null) return both;
  if (both == null) return mine;
  return mine.isAfter(both) ? mine : both;
});

/// Whether the couple has turned on "block screenshots of our chat".
final blockScreenshotsProvider = Provider.autoDispose<bool>(
  (ref) => ref.watch(
    coupleProvider.select((couple) => couple.value?.blockScreenshots ?? false),
  ),
);

/// What the signed-in user is called in system lines the partner sees on
/// older app versions, e.g. "Asha took a screenshot".
final myChatNameProvider = Provider.autoDispose<String>((ref) {
  final user = ref.watch(currentUserProvider);
  final nickname = user.nickname?.trim();
  return (nickname == null || nickname.isEmpty) ? user.displayName : nickname;
});
