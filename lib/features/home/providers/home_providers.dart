import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:couple_app/features/auth/providers/auth_providers.dart';
import 'package:couple_app/features/home/data/daily_question_service.dart';
import 'package:couple_app/features/home/data/mood_service.dart';
import 'package:couple_app/features/home/data/nudge_service.dart';
import 'package:couple_app/features/home/models/daily_question.dart';
import 'package:couple_app/features/home/models/mood.dart';

final moodServiceProvider = Provider<MoodService>((ref) => MoodService());

final dailyQuestionServiceProvider = Provider<DailyQuestionService>(
  (ref) => DailyQuestionService(),
);

final nudgeServiceProvider = Provider<NudgeService>((ref) => NudgeService());

/// Both partners' current moods, keyed by uid.
final moodsProvider = StreamProvider.autoDispose<Map<String, MoodEntry>>(
  (ref) => ref
      .watch(moodServiceProvider)
      .watchMoods(ref.watch(currentCoupleIdProvider)),
);

/// Today's daily question and whatever has been answered so far. The date
/// is fixed when the provider is first listened to.
final todayQuestionProvider = StreamProvider.autoDispose<DailyQuestionEntry>(
  (ref) => ref
      .watch(dailyQuestionServiceProvider)
      .watchToday(ref.watch(currentCoupleIdProvider)),
);

/// Past days where both partners answered, newest first.
final questionHistoryProvider =
    StreamProvider.autoDispose<List<DailyQuestionEntry>>(
      (ref) => ref
          .watch(dailyQuestionServiceProvider)
          .watchHistory(ref.watch(currentCoupleIdProvider)),
    );
