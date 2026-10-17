import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:couple_app/features/auth/providers/auth_providers.dart';
import 'package:couple_app/features/together/data/event_service.dart';
import 'package:couple_app/features/together/data/love_note_service.dart';
import 'package:couple_app/features/together/models/calendar_event.dart';
import 'package:couple_app/features/together/models/love_note.dart';

final eventServiceProvider = Provider<EventService>((ref) => EventService());

final loveNoteServiceProvider = Provider<LoveNoteService>(
  (ref) => LoveNoteService(),
);

/// Calendar events this user can see: every shared event plus their own
/// private ones. Read with `.value ?? const []`; after an error the last
/// good list is kept.
final eventsProvider = StreamProvider.autoDispose<List<CalendarEvent>>(
  (ref) => ref
      .watch(eventServiceProvider)
      .watchEvents(
        ref.watch(currentCoupleIdProvider),
        ref.watch(currentUidProvider),
      ),
);

/// Love notes addressed to this user, sealed or not.
final incomingNotesProvider = StreamProvider.autoDispose<List<LoveNote>>((ref) {
  final uid = ref.watch(currentUidProvider);
  return ref
      .watch(loveNoteServiceProvider)
      .watchNotes(ref.watch(currentCoupleIdProvider))
      .map((notes) => notes.where((n) => n.recipientId == uid).toList());
});
