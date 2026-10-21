import 'package:couple_app/features/play/data/game_service.dart';
import 'package:couple_app/features/play/models/game.dart';

/// Classic (4 tokens, leave the yard on a 6) or Quick (2 tokens, leave on
/// a 1 or a 6). Chosen when inviting and stored in `state.mode`.
enum LudoMode {
  classic('classic', 'Classic', '4 tokens each. Roll a 6 to leave the yard.'),
  quick('quick', 'Quick', '2 tokens each. Leave the yard on a 1 or a 6.');

  const LudoMode(this.id, this.label, this.description);
  final String id;
  final String label;
  final String description;

  int get tokens => this == classic ? 4 : 2;

  /// Rolls that bring a token out of the yard.
  Set<int> get exitRolls => this == classic ? const {6} : const {1, 6};

  static LudoMode fromId(Object? id) =>
      values.firstWhere((m) => m.id == id, orElse: () => classic);
}

/// The roll waiting for a token to be picked: `state.pendingRoll`.
class LudoPendingRoll {
  const LudoPendingRoll({required this.value, required this.movable});

  final int value;
  final List<int> movable;

  static LudoPendingRoll? fromState(Map<String, dynamic> state) {
    final raw = state['pendingRoll'];
    if (raw is! Map) return null;
    final value = raw['value'];
    final movable = raw['movable'];
    if (value is! num || movable is! List) return null;
    return LudoPendingRoll(
      value: value.toInt(),
      movable: [for (final m in movable) (m as num).toInt()],
    );
  }
}

/// The last roll and what it did: `state.lastRoll`.
class LudoRoll {
  const LudoRoll({
    required this.by,
    required this.value,
    this.token,
    this.from,
    this.to,
    this.captured = const [],
    this.passed = false,
    this.forfeit = false,
    this.again = false,
  });

  final String by;
  final int value;

  /// The token moved, with its progress before and after; null while the
  /// roller is still choosing, or when no move was possible.
  final int? token;
  final int? from;
  final int? to;

  /// The opponent's token indexes sent back to their yard.
  final List<int> captured;

  /// No legal move: the turn passed.
  final bool passed;

  /// Third six in a row: the turn passed.
  final bool forfeit;

  /// The mover rolls again (a six, or a capture).
  final bool again;

  bool get moved => token != null;

  static LudoRoll? fromState(Map<String, dynamic> state) {
    final raw = state['lastRoll'];
    if (raw is! Map) return null;
    final by = raw['by'];
    final value = raw['value'];
    if (by is! String || value is! num) return null;
    int? n(Object? v) => (v as num?)?.toInt();
    final captured = raw['captured'];
    return LudoRoll(
      by: by,
      value: value.toInt(),
      token: n(raw['token']),
      from: n(raw['from']),
      to: n(raw['to']),
      captured: captured is List
          ? [for (final c in captured) (c as num).toInt()]
          : const [],
      passed: raw['passed'] == true,
      forfeit: raw['forfeit'] == true,
      again: raw['again'] == true,
    );
  }
}

/// Ludo for two. Pure Dart: the screen only calls these.
///
/// The inviter plays red (seat 0) and the invitee yellow (seat 2), on
/// opposite sides of the board. Each token's progress is stored in its
/// owner's own frame: [yard] (-1), 0–[lastTrack] on the shared 52-square
/// track (0 is the owner's start square), [firstColumn]–[lastColumn] up
/// the owner's home column, and [home]. [absolute] turns progress into a
/// shared track square, for drawing and captures only.
///
/// A turn is two writes. Rolling ([applyRoll]) stores `pendingRoll`
/// (`{value, movable}`) and keeps the turn, or passes it straight away
/// when nothing can move or on a third six. Moving ([applyMove]) applies
/// the move, clears `pendingRoll`, and passes the turn unless the roll
/// was a six or captured a token.
///
/// State (in `Game.state`): `mode` (`'classic'` | `'quick'`), `tokens`
/// (`{uid: [int]}`), `pendingRoll` (or null), `lastRoll` (`{by, value,
/// token, from, to, captured, passed, forfeit, again}` or null) and
/// `sixes` (sixes in a row this turn).
class LudoLogic {
  const LudoLogic._();

  static const trackLength = 52;
  static const yard = -1;
  static const lastTrack = 50;
  static const firstColumn = 51;

  /// The classic board's home column has five squares, then home.
  static const lastColumn = 55;
  static const home = 56;

  static const red = 0;
  static const green = 1;
  static const yellow = 2;
  static const blue = 3;

  /// Each seat starts this many squares further round the track.
  static const seatOffset = 13;

  /// Start squares and the star eight squares after each.
  static const safeSquares = {0, 8, 13, 21, 26, 34, 39, 47};

  static Map<String, dynamic> newState({
    required String inviter,
    required String invitee,
    LudoMode mode = LudoMode.classic,
  }) => {
    'mode': mode.id,
    'tokens': {
      inviter: List<int>.filled(mode.tokens, yard),
      invitee: List<int>.filled(mode.tokens, yard),
    },
    'pendingRoll': null,
    'lastRoll': null,
    'sixes': 0,
  };

  /// The accepter starts, so the inviter isn't left waiting twice.
  static String firstTurn(Game game) => game.invitee;

  static LudoMode modeOf(Map<String, dynamic> state) =>
      LudoMode.fromId(state['mode']);

  /// The inviter is red, the invitee yellow.
  static int seatOf(Game game, String uid) =>
      uid == game.createdBy ? red : yellow;

  static int sixes(Map<String, dynamic> state) =>
      (state['sixes'] as num?)?.toInt() ?? 0;

  /// [uid]'s token progress, padded to the mode's token count.
  static List<int> tokensOf(Map<String, dynamic> state, String uid) {
    final count = modeOf(state).tokens;
    final all = state['tokens'];
    final raw = all is Map ? all[uid] : null;
    final list = raw is List ? raw : const [];
    return List<int>.generate(count, (i) {
      final v = i < list.length ? list[i] : null;
      return v is num ? v.toInt().clamp(yard, home) : yard;
    });
  }

  /// The shared track square (0–51) for [progress] of a token in [seat],
  /// or null in the yard, home column or home.
  static int? absolute(int progress, int seat) {
    if (progress < 0 || progress > lastTrack) return null;
    return (progress + seat * seatOffset) % trackLength;
  }

  static bool isSafe(int square) => safeSquares.contains(square);

  /// Where a token at [progress] goes with [value], or null if it can't.
  static int? destination(int progress, int value, LudoMode mode) {
    if (progress == home) return null;
    if (progress == yard) return mode.exitRolls.contains(value) ? 0 : null;
    final to = progress + value;
    return to > home ? null : to;
  }

  /// The indexes of [tokens] that can move [value].
  static List<int> legalMoves(List<int> tokens, int value, LudoMode mode) => [
    for (var i = 0; i < tokens.length; i++)
      if (destination(tokens[i], value, mode) != null) i,
  ];

  /// The [opponent] tokens (in [opponentSeat]) sent home by a token of
  /// [seat] landing on [progress]. None on safe squares or off the track.
  static List<int> captures({
    required int progress,
    required int seat,
    required List<int> opponent,
    required int opponentSeat,
  }) {
    final square = absolute(progress, seat);
    if (square == null || isSafe(square)) return const [];
    return [
      for (var i = 0; i < opponent.length; i++)
        if (absolute(opponent[i], opponentSeat) == square) i,
    ];
  }

  static bool allHome(List<int> tokens) => tokens.every((t) => t == home);

  static void _checkTurn(Game game, String me) {
    if (!game.isActive) {
      throw const GameMoveException('This game has already ended.');
    }
    if (game.turn != me) {
      throw const GameMoveException('It\'s not your turn yet.');
    }
  }

  static Map<String, dynamic> _tokens(Game game) => {
    for (final p in game.players) p: tokensOf(game.state, p),
  };

  /// The changes for [me] rolling [value], computed from the fresh [game]
  /// inside the transaction. Throws [GameMoveException] when illegal.
  static Map<String, dynamic> applyRoll(Game game, String me, int value) {
    _checkTurn(game, me);
    if (value < 1 || value > 6) {
      throw const GameMoveException('That roll doesn\'t look right.');
    }
    if (LudoPendingRoll.fromState(game.state) != null) {
      throw const GameMoveException('Move a token first.');
    }
    final mode = modeOf(game.state);
    final other = game.opponentOf(me);
    final rolledSixes = value == 6 ? sixes(game.state) + 1 : 0;
    Map<String, dynamic> roll({bool passed = false, bool forfeit = false}) => {
      'by': me,
      'value': value,
      'token': null,
      'from': null,
      'to': null,
      'captured': <int>[],
      'passed': passed,
      'forfeit': forfeit,
      'again': false,
    };

    if (rolledSixes >= 3) {
      return {
        'state': {
          'mode': mode.id,
          'tokens': _tokens(game),
          'pendingRoll': null,
          'lastRoll': roll(forfeit: true),
          'sixes': 0,
        },
        'turn': other,
      };
    }
    final movable = legalMoves(tokensOf(game.state, me), value, mode);
    if (movable.isEmpty) {
      return {
        'state': {
          'mode': mode.id,
          'tokens': _tokens(game),
          'pendingRoll': null,
          'lastRoll': roll(passed: true),
          'sixes': 0,
        },
        'turn': other,
      };
    }
    return {
      'state': {
        'mode': mode.id,
        'tokens': _tokens(game),
        'pendingRoll': {'value': value, 'movable': movable},
        'lastRoll': roll(),
        'sixes': rolledSixes,
      },
      'turn': me,
    };
  }

  /// The changes for [me] moving [token] by the pending roll.
  static Map<String, dynamic> applyMove(Game game, String me, int token) {
    _checkTurn(game, me);
    final pending = LudoPendingRoll.fromState(game.state);
    if (pending == null) {
      throw const GameMoveException('Roll the die first.');
    }
    if (!pending.movable.contains(token)) {
      throw const GameMoveException('That token can\'t move.');
    }
    final mode = modeOf(game.state);
    final other = game.opponentOf(me);
    final mine = tokensOf(game.state, me);
    final theirs = tokensOf(game.state, other);
    final from = mine[token];
    final to = destination(from, pending.value, mode);
    if (to == null) {
      throw const GameMoveException('That token can\'t move.');
    }
    mine[token] = to;
    final captured = captures(
      progress: to,
      seat: seatOf(game, me),
      opponent: theirs,
      opponentSeat: seatOf(game, other),
    );
    for (final i in captured) {
      theirs[i] = yard;
    }
    final won = allHome(mine);
    final again = !won && (pending.value == 6 || captured.isNotEmpty);
    final state = {
      'mode': mode.id,
      'tokens': {me: mine, other: theirs},
      'pendingRoll': null,
      'lastRoll': {
        'by': me,
        'value': pending.value,
        'token': token,
        'from': from,
        'to': to,
        'captured': captured,
        'passed': false,
        'forfeit': false,
        'again': again,
      },
      'sixes': again ? sixes(game.state) : 0,
    };
    if (won) {
      return {
        'state': state,
        'status': GameStatus.finished.id,
        'turn': null,
        'winner': me,
      };
    }
    return {'state': state, 'turn': again ? me : other};
  }

  /// A short, fun line about what [roll] did; null while a token is
  /// still being chosen.
  static String? describe(LudoRoll roll) {
    if (roll.forfeit) return 'Three sixes in a row. Turn over 😅';
    if (roll.passed) return 'No moves this time.';
    if (!roll.moved) return null;
    final parts = <String>[
      if (roll.from == yard)
        'Out of the yard 🚀'
      else if (roll.to == home)
        'Token home! 🏠'
      else if ((roll.to ?? 0) >= firstColumn)
        'Up the home column'
      else
        'Moved ${roll.value}',
      if (roll.captured.isNotEmpty) 'Captured! 💥 Back to the yard',
      if (roll.again) 'Roll again 🎉',
    ];
    return parts.join(' · ');
  }
}
