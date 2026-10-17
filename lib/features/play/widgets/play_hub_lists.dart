import 'package:intl/intl.dart';

import 'package:couple_app/features/play/models/game.dart';

/// Sorting, grouping and wording for the Play hub. Pure, so it is easy to
/// test.
class PlayHubLists {
  const PlayHubLists._();

  static DateTime _when(Game g) =>
      g.finishedAt ??
      g.updatedAt ??
      g.createdAt ??
      DateTime.fromMillisecondsSinceEpoch(0);

  static List<Game> _newestFirst(Iterable<Game> games) =>
      games.toList()..sort((a, b) => _when(b).compareTo(_when(a)));

  /// Invites to accept and games where it is [uid]'s turn.
  static List<Game> waitingOnMe(Iterable<Game> games, String uid) =>
      _newestFirst(games.where((g) => g.needsActionFrom(uid)));

  /// [uid]'s pending invites and games where it is the partner's turn.
  static List<Game> waitingOnPartner(Iterable<Game> games, String uid) =>
      _newestFirst(games.where((g) => g.isOpen && !g.needsActionFrom(uid)));

  /// Finished and cancelled games, newest first.
  static List<Game> recent(Iterable<Game> games, {int limit = 10}) =>
      _newestFirst(games.where((g) => !g.isOpen)).take(limit).toList();

  /// The open game (invite or in progress) of [type], if there is one.
  static Game? openOf(Iterable<Game> games, GameType type) {
    for (final g in _newestFirst(games)) {
      if (g.isOpen && g.type == type) return g;
    }
    return null;
  }

  /// What an open game is waiting for, from [uid]'s side.
  static String statusText(Game game, String uid, String partnerName) {
    if (game.isInvite) {
      return game.invitee == uid
          ? '$partnerName invited you'
          : 'Invite sent to $partnerName';
    }
    if (game.isActive) {
      return game.turn == uid ? 'Your turn' : '$partnerName\'s turn';
    }
    return resultText(game, uid, partnerName);
  }

  /// How a finished or cancelled game ended, from [uid]'s side.
  static String resultText(Game game, String uid, String partnerName) {
    if (game.status == GameStatus.cancelled) {
      // Declined or withdrawn straight from the invite (invite → cancel).
      return game.moveCount <= 1 ? 'Not played' : 'Ended early';
    }
    if (!game.isFinished) return statusText(game, uid, partnerName);
    final winner = game.winner;
    if (winner == Game.draw) return 'Draw';
    if (winner == uid) return 'You won';
    if (winner != null) return '$partnerName won';
    if (game.type == GameType.knowMe) {
      final score = game.state['score'];
      final total = game.state['total'];
      if (score is num && total is num) {
        return 'Quiz: ${score.toInt()}/${total.toInt()}';
      }
      return 'Quiz done';
    }
    return 'Played';
  }

  /// "just now", "5m ago", "3h ago", "Yesterday", "4d ago", "12 Mar".
  static String relativeTime(DateTime? time, DateTime now) {
    if (time == null) return '';
    final diff = now.difference(time);
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inHours < 1) return '${diff.inMinutes}m ago';
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(time.year, time.month, time.day);
    final days = today.difference(day).inDays;
    if (days == 0) return '${diff.inHours}h ago';
    if (days == 1) return 'Yesterday';
    if (days < 7) return '${days}d ago';
    if (time.year == now.year) return DateFormat('d MMM').format(time);
    return DateFormat('d MMM y').format(time);
  }

  /// When [game] last changed, for the row's timestamp.
  static DateTime? lastActivity(Game game) =>
      game.finishedAt ?? game.updatedAt ?? game.createdAt;
}
