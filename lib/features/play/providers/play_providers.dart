import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:couple_app/features/auth/providers/auth_providers.dart';
import 'package:couple_app/features/play/data/game_service.dart';
import 'package:couple_app/features/play/models/game.dart';

final gameServiceProvider = Provider<GameService>((ref) => GameService());

/// The couple's recent games, newest first.
final gamesProvider = StreamProvider.autoDispose<List<Game>>(
  (ref) => ref
      .watch(gameServiceProvider)
      .watchGames(ref.watch(currentCoupleIdProvider)),
);

/// One game, live.
final gameProvider = StreamProvider.autoDispose.family<Game?, String>(
  (ref, gameId) => ref
      .watch(gameServiceProvider)
      .watchGame(ref.watch(currentCoupleIdProvider), gameId),
);

/// How many games are waiting on me (invites to accept, turns to take),
/// for the Play tab's badge.
final gamesWaitingOnMeProvider = Provider.autoDispose<int>((ref) {
  final uid = ref.watch(currentUidProvider);
  final games = ref.watch(gamesProvider).value ?? const [];
  return games.where((g) => g.needsActionFrom(uid)).length;
});
