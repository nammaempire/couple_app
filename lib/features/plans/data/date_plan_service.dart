import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:couple_app/features/plans/models/date_plan.dart';

/// Reads and writes `couples/{coupleId}/datePlans`.
class DatePlanService {
  DatePlanService({FirebaseFirestore? firestore})
    : _db = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;

  CollectionReference<Map<String, dynamic>> _plans(String coupleId) =>
      _db.collection('couples').doc(coupleId).collection('datePlans');

  /// Every date plan of the couple, unsorted (see `DatePlanLists`).
  Stream<List<DatePlan>> watchPlans(String coupleId) {
    return _plans(
      coupleId,
    ).snapshots().map((snap) => snap.docs.map(DatePlan.fromDoc).toList());
  }

  /// Adds [plan] when its id is empty, otherwise updates it.
  Future<void> save(String coupleId, DatePlan plan) async {
    final data = plan.toMap();
    if (plan.id.isEmpty) {
      await _plans(
        coupleId,
      ).add({...data, 'createdAt': FieldValue.serverTimestamp()});
    } else {
      await _plans(coupleId).doc(plan.id).set({
        ...data,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    }
  }

  /// Puts a plan on the calendar at [at] (also used to reschedule).
  Future<void> schedule(String coupleId, String planId, DateTime at) {
    return _plans(coupleId).doc(planId).update({
      'status': DatePlanStatus.planned.id,
      'scheduledAt': Timestamp.fromDate(at),
      'completedAt': null,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  /// Marks a planned date as done, with optional hearts and a reflection.
  Future<void> markDone(
    String coupleId,
    String planId, {
    int? rating,
    String reflection = '',
  }) {
    final trimmed = reflection.trim();
    return _plans(coupleId).doc(planId).update({
      'status': DatePlanStatus.done.id,
      'rating': rating,
      'reflection': trimmed.length > DatePlan.maxReflection
          ? trimmed.substring(0, DatePlan.maxReflection)
          : trimmed,
      'completedAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  /// Sends a plan back to the ideas list, clearing its date and rating.
  /// The reflection text is kept.
  Future<void> moveToIdeas(String coupleId, String planId) {
    return _plans(coupleId).doc(planId).update({
      'status': DatePlanStatus.idea.id,
      'scheduledAt': null,
      'rating': null,
      'completedAt': null,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> delete(String coupleId, String planId) {
    return _plans(coupleId).doc(planId).delete();
  }
}
