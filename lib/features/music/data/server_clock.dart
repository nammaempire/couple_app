/// Server time on this phone: the local clock plus a measured offset.
///
/// Listening sessions store times in server milliseconds so that two
/// phones whose clocks disagree by a few seconds still play the same part
/// of a song. The offset is measured with a round trip (see
/// `MusicService.calibrateClock`); until then it is 0, i.e. the phone's own
/// clock, which on a network-synced phone is usually within a second.
class ServerClock {
  ServerClock({int Function()? localNowMs})
    : _localNow = localNowMs ?? (() => DateTime.now().millisecondsSinceEpoch);

  final int Function() _localNow;

  int _offsetMs = 0;
  int? _bestRoundTripMs;

  /// Server minus local, in milliseconds.
  int get offsetMs => _offsetMs;

  /// Whether at least one measurement has been taken.
  bool get isCalibrated => _bestRoundTripMs != null;

  /// The phone's own clock, in milliseconds since the epoch.
  int localNowMs() => _localNow();

  /// Best estimate of the server's clock now, in milliseconds.
  int nowMs() => _localNow() + _offsetMs;

  /// Records a measurement: the server said [serverMs] somewhere between
  /// local times [sentMs] and [receivedMs]. The midpoint is the best guess,
  /// and the measurement with the shortest round trip wins, since its
  /// uncertainty (half the round trip) is smallest.
  void observe({
    required int sentMs,
    required int receivedMs,
    required int serverMs,
  }) {
    final roundTrip = receivedMs - sentMs;
    if (roundTrip < 0) return;
    final best = _bestRoundTripMs;
    if (best != null && roundTrip >= best) return;
    _bestRoundTripMs = roundTrip;
    _offsetMs = serverMs - (sentMs + roundTrip ~/ 2);
  }
}
