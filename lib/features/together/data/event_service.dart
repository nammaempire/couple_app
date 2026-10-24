import 'dart:async';

import 'package:couple_app/core/backend/backend.dart';

import 'package:couple_app/features/auth/models/app_user.dart';
import 'package:couple_app/features/couple/models/couple.dart';
import 'package:couple_app/features/together/models/calendar_event.dart';

/// Reads and writes `couples/{coupleId}/events`.
class EventService {
  EventService({Db? db}) : _db = db ?? Db.instance;

  final Db _db;

  CollectionReference<Map<String, dynamic>> _events(String coupleId) =>
      _db.collection('couples').doc(coupleId).collection('events');

  /// Every event this user may see: all shared ones plus their own private
  /// ones. Security rules refuse a query that could return the partner's
  /// private events, so this runs two queries and merges them.
  Stream<List<CalendarEvent>> watchEvents(String coupleId, String uid) {
    // The stream is handed to the caller; onCancel releases the queries.
    // ignore: close_sinks
    late StreamController<List<CalendarEvent>> controller;
    StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? shared;
    StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? mine;
    List<CalendarEvent>? sharedList;
    List<CalendarEvent>? mineList;

    void emit() {
      if (sharedList == null || mineList == null) return;
      final byId = <String, CalendarEvent>{
        for (final e in sharedList!) e.id: e,
        for (final e in mineList!) e.id: e,
      };
      final list = byId.values.toList()
        ..sort((a, b) => a.start.compareTo(b.start));
      controller.add(list);
    }

    // Single-subscription: each caller gets its own pair of listeners, so
    // a late listener still receives the current events.
    controller = StreamController<List<CalendarEvent>>(
      onListen: () {
        shared = _events(coupleId)
            .where('private', isEqualTo: false)
            .snapshots()
            .listen(
              (snap) {
                sharedList = snap.docs.map(CalendarEvent.fromDoc).toList();
                emit();
              },
              onError: (Object e) {
                // Show what we can from the other query.
                sharedList ??= const [];
                emit();
                controller.addError(e);
              },
            );
        mine = _events(coupleId)
            .where('createdBy', isEqualTo: uid)
            .snapshots()
            .listen(
              (snap) {
                mineList = snap.docs.map(CalendarEvent.fromDoc).toList();
                emit();
              },
              onError: (Object e) {
                mineList ??= const [];
                emit();
                controller.addError(e);
              },
            );
      },
      onCancel: () async {
        await shared?.cancel();
        await mine?.cancel();
      },
    );
    return controller.stream;
  }

  Future<void> save({
    required String coupleId,
    required CalendarEvent event,
  }) async {
    final data = event.toMap();
    if (event.id.isEmpty) {
      await _events(
        coupleId,
      ).add({...data, 'createdAt': FieldValue.serverTimestamp()});
    } else {
      await _events(coupleId).doc(event.id).set({
        ...data,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    }
  }

  Future<void> delete({required String coupleId, required String eventId}) {
    return _events(coupleId).doc(eventId).delete();
  }

  /// Dates the app already knows, shown on the calendar without being
  /// stored as events: the anniversary, both birthdays and the next meetup.
  static List<CalendarEvent> automaticEvents({
    required Couple couple,
    required AppUser me,
    required AppUser? partner,
    required String partnerName,
  }) {
    final list = <CalendarEvent>[];

    final start = couple.startDate;
    if (start != null) {
      list.add(
        CalendarEvent(
          id: 'auto-anniversary',
          title: 'Our anniversary',
          type: EventType.anniversary,
          // The original date (so Feb 29 stays Feb 29), repeating from the
          // first anniversary rather than the day you started.
          start: DateTime(start.year, start.month, start.day),
          firstYear: start.year + 1,
          repeatYearly: true,
          createdBy: '',
          isAutomatic: true,
        ),
      );
    }

    void birthday(AppUser? user, String id, String title) {
      final b = user?.birthday;
      if (b == null) return;
      list.add(
        CalendarEvent(
          id: id,
          title: title,
          type: EventType.birthday,
          start: b,
          repeatYearly: true,
          createdBy: '',
          isAutomatic: true,
        ),
      );
    }

    birthday(me, 'auto-birthday-me', 'Your birthday');
    birthday(partner, 'auto-birthday-partner', '$partnerName\'s birthday');

    final meetup = couple.nextMeetup;
    if (meetup != null) {
      list.add(
        CalendarEvent(
          id: 'auto-meetup',
          title: 'Seeing each other',
          type: EventType.meetup,
          start: meetup,
          createdBy: '',
          isAutomatic: true,
        ),
      );
    }
    return list;
  }
}
