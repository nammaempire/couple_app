import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:couple_app/features/auth/providers/auth_providers.dart';
import 'package:couple_app/features/chat/data/chat_look_service.dart';
import 'package:couple_app/features/chat/models/chat_look.dart';

final chatLookServiceProvider = Provider<ChatLookService>(
  (ref) => ChatLookService(),
);

/// The couple's shared chat look.
final sharedChatLookProvider = StreamProvider.autoDispose<SharedChatLook>(
  (ref) => ref
      .watch(chatLookServiceProvider)
      .watchShared(ref.watch(currentCoupleIdProvider)),
);

/// This person's choice of shared or personal look.
final personalChatLookProvider = StreamProvider.autoDispose<PersonalChatLook>(
  (ref) => ref
      .watch(chatLookServiceProvider)
      .watchPersonal(ref.watch(currentUidProvider)),
);

/// What the chat should look like on this phone right now.
final effectiveChatLookProvider = Provider.autoDispose<ChatLook>((ref) {
  final shared =
      ref.watch(sharedChatLookProvider).value?.look ?? ChatLook.standard;
  final personal =
      ref.watch(personalChatLookProvider).value ?? const PersonalChatLook();
  return personal.effective(shared);
});
