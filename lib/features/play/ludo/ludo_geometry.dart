import 'dart:ui';

import 'package:couple_app/features/play/ludo/ludo_logic.dart';

/// Where things are on the 15 × 15 Ludo board, in grid cells: (col, row)
/// with (0, 0) at the top left. Red's yard is top left, green top right,
/// yellow bottom right and blue bottom left; play runs clockwise.
class LudoGeometry {
  const LudoGeometry._();

  static const grid = 15;

  /// The 52 shared track squares, in order, starting at red's start.
  static const track = <(int, int)>[
    (1, 6), (2, 6), (3, 6), (4, 6), (5, 6), //
    (6, 5), (6, 4), (6, 3), (6, 2), (6, 1), (6, 0),
    (7, 0),
    (8, 0), (8, 1), (8, 2), (8, 3), (8, 4), (8, 5),
    (9, 6), (10, 6), (11, 6), (12, 6), (13, 6), (14, 6),
    (14, 7),
    (14, 8), (13, 8), (12, 8), (11, 8), (10, 8), (9, 8),
    (8, 9), (8, 10), (8, 11), (8, 12), (8, 13), (8, 14),
    (7, 14),
    (6, 14), (6, 13), (6, 12), (6, 11), (6, 10), (6, 9),
    (5, 8), (4, 8), (3, 8), (2, 8), (1, 8), (0, 8),
    (0, 7),
    (0, 6),
  ];

  /// Each seat's home column, outermost first.
  static const homeColumns = <List<(int, int)>>[
    [(1, 7), (2, 7), (3, 7), (4, 7), (5, 7)],
    [(7, 1), (7, 2), (7, 3), (7, 4), (7, 5)],
    [(13, 7), (12, 7), (11, 7), (10, 7), (9, 7)],
    [(7, 13), (7, 12), (7, 11), (7, 10), (7, 9)],
  ];

  /// The top-left cell of each seat's 6 × 6 yard.
  static const yards = <(int, int)>[(0, 0), (9, 0), (9, 9), (0, 9)];

  /// Token spots inside a yard, relative to its corner, in grid units.
  static const yardSlots = <Offset>[
    Offset(2, 2),
    Offset(4, 4),
    Offset(4, 2),
    Offset(2, 4),
  ];

  /// Where finished tokens gather: in their colour's home triangle.
  static const homeSpots = <Offset>[
    Offset(6.8, 7.5),
    Offset(7.5, 6.8),
    Offset(8.2, 7.5),
    Offset(7.5, 8.2),
  ];

  static Offset _centre((int, int) cell) =>
      Offset(cell.$1 + 0.5, cell.$2 + 0.5);

  /// The centre of track square [square] (0–51).
  static Offset trackCentre(int square) =>
      _centre(track[square % LudoLogic.trackLength]);

  /// Where token [index] of [seat] at [progress] is drawn.
  static Offset tokenPoint(int seat, int progress, int index) {
    if (progress <= LudoLogic.yard) {
      final (x, y) = yards[seat];
      return Offset(x.toDouble(), y.toDouble()) + yardSlots[index % 4];
    }
    if (progress >= LudoLogic.home) return homeSpots[seat];
    if (progress >= LudoLogic.firstColumn) {
      return _centre(homeColumns[seat][progress - LudoLogic.firstColumn]);
    }
    return trackCentre(LudoLogic.absolute(progress, seat)!);
  }

  /// The points a token passes moving from [from] to [to], [from]
  /// included: out of the yard in one hop, then square by square.
  static List<Offset> path(int seat, int index, int from, int to) {
    if (from == LudoLogic.yard) {
      return [tokenPoint(seat, from, index), tokenPoint(seat, to, index)];
    }
    return [for (var p = from; p <= to; p++) tokenPoint(seat, p, index)];
  }
}
