import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:couple_app/core/providers/core_providers.dart';
import 'package:couple_app/features/chat/data/chat_service.dart';

final chatServiceProvider = Provider<ChatService>(
  (ref) => ChatService(storage: ref.watch(storageServiceProvider)),
);
