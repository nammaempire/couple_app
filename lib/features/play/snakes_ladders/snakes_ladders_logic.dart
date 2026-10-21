import 'package:couple_app/features/play/data/game_service.dart';
import 'package:couple_app/features/play/models/game.dart';

/// How a roll's move ended, besides plain steps.
enum SnakesLaddersVia {
  ladder('ladder'),
  snake('snake'),

  /// Overshot 100 and walked back.
  bounce('bounce');

  const SnakesLaddersVia(this.id);
  final String id;

  static SnakesLaddersVia? fromId(Object? id) {
    for (final v in values) {
      if (v.id == id) return v;
    }
    return null;
  }
}

/// Where one roll takes a token. Pure data, see [SnakesLaddersLogic.move].
class SnakesLaddersMove {
  const SnakesLaddersMove({
    required this.from,
    required this.landing,
    required this.to,
    this.bounced = false,
    this.via,
    this.viaFrom,
    this.viaTo,
  });

  final int from;

  /// The square the steps end on, before any ladder or snake.
  final int landing;

  /// Where the token ends up.
  final int to;
  final bool bounced;

  /// Ladder or snake if one applied, else bounce if it bounced, else null.
  final SnakesLaddersVia? via;

  /// The first ladder foot / snake head, and where the last one ends.
  final int? viaFrom;
  final int? viaTo;

  /// The squares the token steps through, [from] excluded, [landing]
  /// included: up to 100 and back down after an overshoot.
  List<int> get steps {
    final out = <int>[];
    var at = from;
    var dir = 1;
    final count = bounced
        ? (100 - from) + (100 - landing)
        : (landing - from).abs();
    for (var i = 0; i < count; i++) {
      if (at == 100) dir = -1;
      at += dir;
      out.add(at);
    }
    return out;
  }
}

/// The last roll, as stored in `state.lastRoll`.
class SnakesLaddersRoll {
  const SnakesLaddersRoll({
    required this.by,
    required this.value,
    required this.from,
    required this.to,
    this.via,
    this.viaFrom,
    this.viaTo,
    this.bounced = false,
    this.forfeit = false,
    this.again = false,
  });

  final String by;
  final int value;
  final int from;
  final int to;
  final SnakesLaddersVia? via;
  final int? viaFrom;
  final int? viaTo;
  final bool bounced;

  /// The third six in a row: no move, turn over.
  final bool forfeit;

  /// A six: the same player rolls again.
  final bool again;

  static SnakesLaddersRoll? fromState(Map<String, dynamic> state) {
    final raw = state['lastRoll'];
    if (raw is! Map) return null;
    final by = raw['by'];
    final value = raw['value'];
    if (by is! String || value is! num) return null;
    int? n(Object? v) => (v as num?)?.toInt();
    return SnakesLaddersRoll(
      by: by,
      value: value.toInt(),
      from: n(raw['from']) ?? 0,
      to: n(raw['to']) ?? 0,
      via: SnakesLaddersVia.fromId(raw['via']),
      viaFrom: n(raw['viaFrom']),
      viaTo: n(raw['viaTo']),
      bounced: raw['bounced'] == true,
      forfeit: raw['forfeit'] == true,
      again: raw['again'] == true,
    );
  }

  /// The move this roll made, for animating it.
  SnakesLaddersMove get move => SnakesLaddersMove(
    from: from,
    landing: via == SnakesLaddersVia.ladder || via == SnakesLaddersVia.snake
        ? viaFrom ?? to
        : to,
    to: to,
    bounced: bounced,
    via: via,
    viaFrom: viaFrom,
    viaTo: viaTo,
  );
}

/// Snakes & Ladders rules. Pure Dart: the screen only calls these.
///
/// The classic 10×10 board, numbered 1–100 boustrophedon from the bottom
/// left. Both tokens start off the board on 0 and any roll enters. You
/// must land exactly on 100: an overshoot walks back the extra steps.
/// Ladders and snakes apply automatically. A six rolls again, but a third
/// six in a row ends the turn with no move.
///
/// One write per roll (roll and move together). State (in `Game.state`):
/// - `positions`: `{uid: int}`, 0 = not on the board yet, 100 = won.
/// - `lastRoll`: `{by, value, from, to, via, viaFrom, viaTo, bounced,
///   forfeit, again}` or null; `via` is `'ladder'`, `'snake'`, `'bounce'`
///   or null.
/// - `sixes`: sixes rolled in a row by the player whose turn it is.
///
/// The invitee (who accepted) rolls first.
class SnakesLaddersLogic {
  const SnakesLaddersLogic._();

  static const size = 10;
  static const last = 100;

  /// The classic Milton Bradley layout: foot → top.
  static const ladders = <int, int>{
    1: 38,
    4: 14,
    9: 31,
    21: 42,
    28: 84,
    36: 44,
    51: 67,
    71: 91,
    80: 100,
  };

  /// Head → tail.
  static const snakes = <int, int>{
    16: 6,
    47: 26,
    49: 11,
    56: 53,
    62: 19,
    64: 60,
    87: 24,
    93: 73,
    95: 75,
    98: 78,
  };

  static Map<String, dynamic> newState({
    required String inviter,
    required String invitee,
  }) => {
    'positions': {inviter: 0, invitee: 0},
    'lastRoll': null,
    'sixes': 0,
  };

  /// The accepter starts, so the inviter isn't left waiting twice.
  static String firstTurn(Game game) => game.invitee;

  static int positionOf(Map<String, dynamic> state, String uid) {
    final p = state['positions'];
    final v = p is Map ? p[uid] : null;
    return v is num ? v.toInt().clamp(0, last) : 0;
  }

  static int sixes(Map<String, dynamic> state) =>
      (state['sixes'] as num?)?.toInt() ?? 0;

  /// Row (0 = bottom) and column (0 = left) of square [n] (1–100).
  static (int row, int col) cellOf(int n) {
    final i = n - 1;
    final row = i ~/ size;
    final c = i % size;
    return (row, row.isEven ? c : size - 1 - c);
  }

  /// Follows ladders and snakes from [square] until it rests. Returns the
  /// first jump's start and where the token ends up.
  static (int? from, int to) resolveJumps(
    int square, {
    Map<int, int> ladders = ladders,
    Map<int, int> snakes = snakes,
  }) {
    int? first;
    var at = square;
    // A ladder can end on a snake's head and so on; the guard stops a
    // badly drawn board from looping forever.
    for (var guard = 0; guard < 100; guard++) {
      final next = ladders[at] ?? snakes[at];
      if (next == null) break;
      first ??= at;
      at = next;
    }
    return (first, at);
  }

  /// Where rolling [value] from [from] goes.
  static SnakesLaddersMove move(
    int from,
    int value, {
    Map<int, int> ladders = ladders,
    Map<int, int> snakes = snakes,
  }) {
    var landing = from + value;
    var bounced = false;
    if (landing > last) {
      landing = last - (landing - last);
      bounced = true;
    }
    final (jumpFrom, to) = resolveJumps(
      landing,
      ladders: ladders,
      snakes: snakes,
    );
    SnakesLaddersVia? via;
    if (jumpFrom != null) {
      via = to > jumpFrom ? SnakesLaddersVia.ladder : SnakesLaddersVia.snake;
    } else if (bounced) {
      via = SnakesLaddersVia.bounce;
    }
    return SnakesLaddersMove(
      from: from,
      landing: landing,
      to: to,
      bounced: bounced,
      via: via,
      viaFrom: jumpFrom,
      viaTo: jumpFrom == null ? null : to,
    );
  }

  /// The changes for [me] rolling [value], computed from the fresh [game]
  /// inside the transaction. Throws [GameMoveException] when illegal.
  static Map<String, dynamic> applyRoll(Game game, String me, int value) {
    if (!game.isActive) {
      throw const GameMoveException('This game has already ended.');
    }
    if (game.turn != me) {
      throw const GameMoveException('It\'s not your turn yet.');
    }
    if (value < 1 || value > 6) {
      throw const GameMoveException('That roll doesn\'t look right.');
    }
    final other = game.opponentOf(me);
    final from = positionOf(game.state, me);
    final positions = {me: from, other: positionOf(game.state, other)};
    final rolledSixes = value == 6 ? sixes(game.state) + 1 : 0;

    if (rolledSixes >= 3) {
      return {
        'state': {
          'positions': positions,
          'lastRoll': _roll(me, value, from, from, forfeit: true),
          'sixes': 0,
        },
        'turn': other,
      };
    }

    final m = move(from, value);
    positions[me] = m.to;
    final won = m.to == last;
    final again = value == 6 && !won;
    final state = {
      'positions': positions,
      'lastRoll': _roll(
        me,
        value,
        from,
        m.to,
        via: m.via,
        viaFrom: m.viaFrom,
        viaTo: m.viaTo,
        bounced: m.bounced,
        again: again,
      ),
      'sixes': again ? rolledSixes : 0,
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

  static Map<String, dynamic> _roll(
    String by,
    int value,
    int from,
    int to, {
    SnakesLaddersVia? via,
    int? viaFrom,
    int? viaTo,
    bool bounced = false,
    bool forfeit = false,
    bool again = false,
  }) => {
    'by': by,
    'value': value,
    'from': from,
    'to': to,
    'via': via?.id,
    'viaFrom': viaFrom,
    'viaTo': viaTo,
    'bounced': bounced,
    'forfeit': forfeit,
    'again': again,
  };

  /// A short, fun line about what [roll] did.
  static String describe(SnakesLaddersRoll roll) {
    if (roll.forfeit) return 'Three sixes in a row. Turn over 😅';
    final parts = <String>[];
    if (roll.from == 0 && roll.to > 0) parts.add('On the board!');
    if (roll.bounced) parts.add('Bounced off 100 ↩️');
    switch (roll.via) {
      case SnakesLaddersVia.ladder:
        parts.add('Ladder! 🪜 ${roll.viaFrom} → ${roll.viaTo}');
      case SnakesLaddersVia.snake:
        parts.add('Ssss… snake 🐍 ${roll.viaFrom} → ${roll.viaTo}');
      case SnakesLaddersVia.bounce || null:
        break;
    }
    if (roll.to == last) {
      parts.add('Made it to 100! 🏆');
    } else if (roll.again) {
      parts.add('Six! Roll again 🎉');
    }
    if (parts.isEmpty) return 'Moved ${roll.from} → ${roll.to}';
    return parts.join(' ');
  }
}
