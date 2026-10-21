import 'package:cloud_functions/cloud_functions.dart';

/// Why the server couldn't end a pairing.
enum EndPairingFailure {
  /// The functions aren't deployed or reachable yet (no Blaze plan, a
  /// network or server problem). Worth trying again later.
  unavailable,

  /// The server says this user may not do this (or isn't signed in).
  denied,

  /// Not yet: the end date hasn't passed by the server's clock, or there is
  /// no separation to finish.
  notReady,

  /// Anything else, including a malformed request.
  other,
}

class EndPairingException implements Exception {
  EndPairingException(this.failure, [this.message, this.notBefore]);

  final EndPairingFailure failure;
  final String? message;

  /// For [EndPairingFailure.notReady]: the end date the server goes by
  /// (`details.effectiveAt`), when it sent one.
  final DateTime? notBefore;

  @override
  String toString() => 'EndPairingException(${failure.name}: $message)';
}

/// What the server answered.
enum EndPairingStatus {
  /// Everything is deleted (by this call or an earlier one).
  ended,

  /// Another call is deleting right now; watch the couple and profile, and
  /// try again later.
  inProgress;

  static EndPairingStatus parse(Object? raw) => switch (raw) {
    'inProgress' => EndPairingStatus.inProgress,
    _ => EndPairingStatus.ended,
  };
}

class EndPairingResult {
  const EndPairingResult(this.status, [this.how]);

  final EndPairingStatus status;

  /// `agreed`, `oneSided` or `leftNow`, when the server said.
  final String? how;

  bool get isDone => status == EndPairingStatus.ended;
}

/// The server half of ending a pairing: deleting everything the couple
/// shared and unlinking both people. Behind an interface so tests can fake
/// it.
abstract class EndPairingGateway {
  /// Finishes a separation whose end date has passed.
  Future<EndPairingResult> finalizeSeparation(String coupleId);

  /// Ends the pairing right away ("I need to leave now").
  Future<EndPairingResult> leaveNow(String coupleId);
}

/// [EndPairingGateway] through the `finalizeSeparation` and `leaveNow`
/// callable functions in asia-south1.
///
/// Both answer `{status: 'ended' | 'alreadyEnded' | 'inProgress', how}`.
class FunctionsEndPairingGateway implements EndPairingGateway {
  FunctionsEndPairingGateway([FirebaseFunctions? functions])
    : _given = functions;

  static const region = 'asia-south1';

  final FirebaseFunctions? _given;

  /// Looked up on first use, so creating the gateway touches no plugin.
  late final FirebaseFunctions _functions =
      _given ?? FirebaseFunctions.instanceFor(region: region);

  @override
  Future<EndPairingResult> finalizeSeparation(String coupleId) =>
      _call('finalizeSeparation', {'coupleId': coupleId});

  @override
  Future<EndPairingResult> leaveNow(String coupleId) =>
      _call('leaveNow', {'coupleId': coupleId, 'confirm': 'LEAVE'});

  Future<EndPairingResult> _call(String name, Map<String, Object?> data) async {
    try {
      final result = await _functions.httpsCallable(name).call<Object?>(data);
      return parseResult(result.data);
    } on FirebaseFunctionsException catch (e) {
      throw EndPairingException(
        failureForCode(e.code),
        e.message,
        notBeforeFrom(e.details),
      );
    } on EndPairingException {
      rethrow;
    } catch (e) {
      // No plugin, no network, no server: try again later.
      throw EndPairingException(EndPairingFailure.unavailable, '$e');
    }
  }

  /// Reads `{status, how}`.
  static EndPairingResult parseResult(Object? data) {
    if (data is! Map) return const EndPairingResult(EndPairingStatus.ended);
    final how = data['how'];
    return EndPairingResult(
      EndPairingStatus.parse(data['status']),
      how is String ? how : null,
    );
  }

  /// `details.effectiveAt` (an ISO string) of a "not yet" refusal.
  static DateTime? notBeforeFrom(Object? details) {
    if (details is! Map) return null;
    final raw = details['effectiveAt'];
    return raw is String ? DateTime.tryParse(raw)?.toLocal() : null;
  }

  /// Maps a callable error code (`not-found`, `UNAVAILABLE`…) to a failure.
  static EndPairingFailure failureForCode(String code) {
    switch (code.toLowerCase().replaceAll('_', '-')) {
      case 'not-found':
      case 'unavailable':
      case 'internal':
      case 'unimplemented':
      case 'deadline-exceeded':
      case 'resource-exhausted':
      case 'unknown':
        return EndPairingFailure.unavailable;
      case 'permission-denied':
      case 'unauthenticated':
        return EndPairingFailure.denied;
      case 'failed-precondition':
        return EndPairingFailure.notReady;
      default:
        return EndPairingFailure.other;
    }
  }
}
