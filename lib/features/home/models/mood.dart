import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

/// The set of moods a partner can broadcast.
enum Mood {
  happy('happy', '😊', 'Happy', Color(0xFFFFC94D)),
  loved('loved', '🥰', 'Loved', Color(0xFFFF7EA6)),
  calm('calm', '😌', 'Calm', Color(0xFF8FD3C4)),
  tired('tired', '😴', 'Tired', Color(0xFF9DA7D0)),
  stressed('stressed', '😖', 'Stressed', Color(0xFFE8945C)),
  sad('sad', '🥺', 'Sad', Color(0xFF7FA9D6)),
  missingYou('missing', '🫂', 'Missing you', Color(0xFFC58BE0));

  const Mood(this.id, this.emoji, this.label, this.color);

  final String id;
  final String emoji;
  final String label;
  final Color color;

  static Mood? fromId(String? id) {
    if (id == null) return null;
    for (final mood in Mood.values) {
      if (mood.id == id) return mood;
    }
    return null;
  }
}

/// One partner's current mood, with an optional short note.
class MoodEntry {
  final String uid;
  final Mood mood;
  final String note;
  final DateTime? updatedAt;

  const MoodEntry({
    required this.uid,
    required this.mood,
    this.note = '',
    this.updatedAt,
  });

  /// True when the mood was set today; older moods are shown as stale.
  bool get isFresh {
    final at = updatedAt;
    if (at == null) return false;
    final now = DateTime.now();
    return at.year == now.year && at.month == now.month && at.day == now.day;
  }

  factory MoodEntry.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? <String, dynamic>{};
    return MoodEntry(
      uid: doc.id,
      mood: Mood.fromId(data['mood'] as String?) ?? Mood.calm,
      note: (data['note'] as String?) ?? '',
      updatedAt: (data['updatedAt'] as Timestamp?)?.toDate(),
    );
  }

  Map<String, dynamic> toMap() => {
    'mood': mood.id,
    'note': note,
    'updatedAt': FieldValue.serverTimestamp(),
  };
}
