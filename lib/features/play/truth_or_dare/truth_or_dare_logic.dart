import 'dart:math';

import 'package:couple_app/features/play/data/game_service.dart';
import 'package:couple_app/features/play/models/game.dart';
import 'package:couple_app/features/play/truth_or_dare/truth_or_dare_cards.dart';

/// Rules for Truth or Dare.
///
/// One person acts at a time, and `game.turn` always names them:
///
/// 1. **choose** (turn = chooser): picks Truth, Dare or "Surprise me". A
///    random unused card of that kind is drawn into `state.card`, the
///    phase becomes `judge` and the turn passes to the partner.
/// 2. **judge** (turn = the partner): the chooser answers or does the card
///    in chat or on a call; the judge taps Done or Skipped. That is scored
///    for the chooser, logged in `history`, and the roles swap: the judge
///    becomes the next chooser (phase `choose`, turn = them).
///
/// After [rounds] rounds (5 each) the game finishes with no `winner`: it's
/// a game for fun, so it doesn't count in head-to-head scores. The summary
/// names whoever completed more cards "most daring" ([mostDaring]).
///
/// State keys: `round` (1-based), `rounds`, `phase`, `chooser`, `card`
/// (`{kind, id, text}` or null), `used` (card ids), `done` and `skipped`
/// (`{uid: int}`), `history` (`[{round, chooser, kind, id, result}]`,
/// last [historyCap]).
///
/// `chooser` is null in a new game: while the phase is `choose` the
/// chooser is always `game.turn` (see [chooserOf]). It is set when the
/// first card is drawn and kept in sync from then on.
class TruthOrDareLogic {
  const TruthOrDareLogic._();

  static const rounds = 10;
  static const historyCap = 20;
  static const phaseChoose = 'choose';
  static const phaseJudge = 'judge';
  static const resultDone = 'done';
  static const resultSkipped = 'skipped';

  /// Cards are drawn when chosen, so [random] is unused here; it is kept
  /// for the shared contract.
  static Map<String, dynamic> newState({Random? random}) => {
    'round': 1,
    'rounds': rounds,
    'phase': phaseChoose,
    'chooser': null,
    'card': null,
    'used': <String>[],
    'done': <String, int>{},
    'skipped': <String, int>{},
    'history': <Map<String, dynamic>>[],
  };

  /// The invitee (who accepted) chooses first.
  static String firstTurn(Game game) => game.invitee;

  /// Who is choosing (or chose) this round's card.
  static String? chooserOf(Game game) {
    final s = TruthOrDareState.of(game);
    if (s.phase == phaseChoose) return game.turn ?? s.chooser;
    return s.chooser;
  }

  /// Who judges this round: the partner of the chooser.
  static String? judgeOf(Game game) {
    final c = chooserOf(game);
    return c == null ? null : game.opponentOf(c);
  }

  /// Draws a random card of [kind] that isn't in [used]. When that pile is
  /// used up it is reshuffled: its ids leave [used] and every card of the
  /// kind is back in play (except the one drawn last, when possible).
  ///
  /// Returns the card and the new `used` list.
  static (TruthOrDareCard, List<String>) draw(
    TruthOrDareKind kind,
    List<String> used, {
    Random? random,
    List<TruthOrDareCard>? pile,
  }) {
    final rng = random ?? Random();
    final cards = pile ?? TruthOrDareCards.of(kind);
    final usedSet = used.toSet();
    var nextUsed = [...used];
    var options = cards.where((c) => !usedSet.contains(c.id)).toList();
    if (options.isEmpty) {
      final ids = cards.map((c) => c.id).toSet();
      final lastOfKind = used.lastWhere(ids.contains, orElse: () => '');
      nextUsed = used.where((id) => !ids.contains(id)).toList();
      options = cards.where((c) => c.id != lastOfKind).toList();
      if (options.isEmpty) options = [...cards];
    }
    final card = options[rng.nextInt(options.length)];
    return (card, [...nextUsed, card.id]);
  }

  /// The changes for [me] choosing [kind] (null = "Surprise me").
  static Map<String, dynamic> choose(
    Game game,
    String me,
    TruthOrDareKind? kind, {
    Random? random,
  }) {
    final rng = random ?? Random();
    final s = TruthOrDareState.of(game);
    if (!game.isActive) {
      throw const GameMoveException('This game has already ended.');
    }
    if (game.turn != me) {
      throw const GameMoveException('It\'s not your turn yet.');
    }
    if (s.phase != phaseChoose || s.round > s.rounds) {
      throw const GameMoveException('A card is already on the table.');
    }
    final pick =
        kind ??
        TruthOrDareKind.values[rng.nextInt(TruthOrDareKind.values.length)];
    final (card, used) = draw(pick, s.used, random: rng);
    return {
      'turn': game.opponentOf(me),
      'state': {
        ...s.raw,
        'phase': phaseJudge,
        'chooser': me,
        'card': card.toMap(),
        'used': used,
      },
    };
  }

  /// The changes for [me], the judge, saying whether the chooser [done]
  /// the card. Moves to the next round, or finishes after the last one.
  static Map<String, dynamic> judge(
    Game game,
    String me, {
    required bool done,
  }) {
    final s = TruthOrDareState.of(game);
    if (!game.isActive) {
      throw const GameMoveException('This game has already ended.');
    }
    if (game.turn != me) {
      throw const GameMoveException('It\'s not your turn yet.');
    }
    final chooser = s.chooser;
    final card = s.card;
    if (s.phase != phaseJudge || card == null || chooser == null) {
      throw const GameMoveException('There is no card to judge yet.');
    }
    if (chooser == me) {
      throw const GameMoveException('Your partner decides this one.');
    }

    final doneMap = Map<String, int>.from(s.done);
    final skippedMap = Map<String, int>.from(s.skipped);
    final tally = done ? doneMap : skippedMap;
    tally[chooser] = (tally[chooser] ?? 0) + 1;

    final history = [
      ...s.history,
      {
        'round': s.round,
        'chooser': chooser,
        'kind': card.kind.id,
        'id': card.id,
        'result': done ? resultDone : resultSkipped,
      },
    ];
    final capped = history.length > historyCap
        ? history.sublist(history.length - historyCap)
        : history;

    final finished = s.round >= s.rounds;
    final state = {
      ...s.raw,
      'round': finished ? s.round : s.round + 1,
      'phase': phaseChoose,
      'chooser': me,
      'card': null,
      'done': doneMap,
      'skipped': skippedMap,
      'history': capped,
    };
    if (finished) {
      return {
        'state': state,
        'status': GameStatus.finished.id,
        'turn': null,
        'winner': null,
      };
    }
    return {'state': state, 'turn': me};
  }

  /// Whoever completed more cards, or [Game.draw] when level. Shown as
  /// "most daring"; never stored as the game's winner.
  static String mostDaring(List<String> players, Map<String, int> done) {
    final a = done[players[0]] ?? 0;
    final b = done[players[1]] ?? 0;
    if (a == b) return Game.draw;
    return a > b ? players[0] : players[1];
  }
}

/// A typed, forgiving read of a Truth or Dare game's state.
class TruthOrDareState {
  const TruthOrDareState._(this.raw);

  factory TruthOrDareState.of(Game game) => TruthOrDareState._(game.state);

  final Map<String, dynamic> raw;

  int get round => (raw['round'] as num?)?.toInt() ?? 1;
  int get rounds => (raw['rounds'] as num?)?.toInt() ?? TruthOrDareLogic.rounds;
  String get phase => raw['phase'] == TruthOrDareLogic.phaseJudge
      ? TruthOrDareLogic.phaseJudge
      : TruthOrDareLogic.phaseChoose;
  String? get chooser => raw['chooser'] as String?;
  TruthOrDareCard? get card => TruthOrDareCard.fromMap(raw['card']);
  List<String> get used =>
      (raw['used'] as List?)?.whereType<String>().toList() ?? const [];
  Map<String, int> get done => _counts(raw['done']);
  Map<String, int> get skipped => _counts(raw['skipped']);

  List<Map<String, dynamic>> get history =>
      (raw['history'] as List?)
          ?.whereType<Map<Object?, Object?>>()
          .map(Map<String, dynamic>.from)
          .toList() ??
      const [];

  int doneBy(String uid) => done[uid] ?? 0;
  int skippedBy(String uid) => skipped[uid] ?? 0;

  static Map<String, int> _counts(Object? v) => v is Map
      ? {
          for (final e in v.entries)
            if (e.key is String && e.value is num)
              e.key as String: (e.value as num).toInt(),
        }
      : const {};
}
