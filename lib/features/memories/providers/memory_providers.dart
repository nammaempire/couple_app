import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:couple_app/features/auth/providers/auth_providers.dart';
import 'package:couple_app/features/memories/data/memory_service.dart';
import 'package:couple_app/features/memories/models/memory.dart';

final memoryServiceProvider = Provider<MemoryService>((ref) => MemoryService());

/// Every memory of the couple, as [MemoryService.watchMemories] orders them.
/// After an error the last good list is kept in `.value`.
final memoriesProvider = StreamProvider.autoDispose<List<Memory>>(
  (ref) => ref
      .watch(memoryServiceProvider)
      .watchMemories(ref.watch(currentCoupleIdProvider)),
);
