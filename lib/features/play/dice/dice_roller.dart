import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Rolls one six-sided die for the dice games.
///
/// The player whose turn it is rolls on their own phone and writes the
/// result. The security rules can't check that the number really was
/// random; for two partners playing together that is fine, and it keeps
/// every roll to a single write.
class DiceRoller {
  DiceRoller(this._random);

  /// The roller the app uses: cryptographically secure.
  DiceRoller.secure() : _random = Random.secure();

  final Random _random;

  /// A number from 1 to 6.
  int roll() => _random.nextInt(6) + 1;
}

/// The app's die. Tests override it to roll known numbers.
final diceRollerProvider = Provider<DiceRoller>((ref) => DiceRoller.secure());
