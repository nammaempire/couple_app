import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:couple_app/features/auth/providers/auth_providers.dart';
import 'package:couple_app/features/couple/data/end_pairing_gateway.dart';
import 'package:couple_app/features/couple/data/separation_service.dart';
import 'package:couple_app/features/couple/models/separation.dart';
import 'package:couple_app/features/couple/providers/couple_providers.dart';

/// The time, for the end date and countdown. Tests replace it.
final separationClockProvider = Provider<DateTime Function()>(
  (ref) => DateTime.now,
);

final separationServiceProvider = Provider<SeparationService>(
  (ref) => SeparationService(clock: ref.watch(separationClockProvider)),
);

/// The `finalizeSeparation` and `leaveNow` callables.
final endPairingGatewayProvider = Provider<EndPairingGateway>(
  (ref) => FunctionsEndPairingGateway(),
);

/// How long to wait before asking the server again after it couldn't
/// finish (not deployed yet, busy, or its clock says "not yet").
final separationRetryDelayProvider = Provider<Duration>(
  (ref) => const Duration(minutes: 2),
);

/// The couple's ending pairing, or null.
final separationProvider = Provider.autoDispose<Separation?>(
  (ref) => ref.watch(coupleProvider.select((c) => c.value?.separation)),
);

/// Whether the pairing is ending (asked, or being deleted by the server).
///
/// The one switch for everything that closes during the wait: the vault,
/// sharing and saving out of the app, and screenshots of the chat.
final separationActiveProvider = Provider.autoDispose<bool>(
  (ref) =>
      ref.watch(coupleProvider.select((c) => c.value?.isSeparating ?? false)),
);

/// The server is deleting everything right now (`couples/{id}.ending`).
final pairingEndingProvider = Provider.autoDispose<bool>(
  (ref) => ref.watch(coupleProvider.select((c) => c.value?.ending != null)),
);

/// "Mute my partner": no alerts, banners or badges for their activity, and
/// their calls are not rung.
final mutePartnerProvider = Provider.autoDispose<bool>(
  (ref) => ref.watch(currentUserProvider.select((u) => u.mutePartner)),
);

/// What the app knows about finishing a separation on the server.
enum FinalizePhase {
  /// Not due, or nothing to finish.
  idle,

  /// Asked the server, or it is deleting: "Ending your pairing…".
  working,

  /// The server isn't there yet (no Blaze plan) or failed: "Waiting for the
  /// server to finish", and try again later.
  waitingForServer,

  /// The server's clock says it isn't time yet.
  notYet,
}

@immutable
class FinalizeState {
  const FinalizeState(this.phase, {this.notBefore});

  static const idle = FinalizeState(FinalizePhase.idle);

  final FinalizePhase phase;

  /// For [FinalizePhase.notYet]: the end date by the server's clock.
  final DateTime? notBefore;

  @override
  bool operator ==(Object other) =>
      other is FinalizeState &&
      other.phase == phase &&
      other.notBefore == notBefore;

  @override
  int get hashCode => Object.hash(phase, notBefore);
}

/// Asks the server to finish the separation once its end date has passed,
/// and keeps asking until it does.
///
/// The shell calls [check] when it opens, when the separation changes and
/// when the app comes back to the foreground. In between, it wakes itself
/// at the end date and retries after [separationRetryDelayProvider]. It
/// never throws: a server that isn't deployed yet is just "waiting".
class SeparationFinalizer extends Notifier<FinalizeState> {
  Timer? _timer;
  bool _running = false;

  @override
  FinalizeState build() {
    ref.onDispose(() => _timer?.cancel());
    return FinalizeState.idle;
  }

  void _wakeIn(Duration delay) {
    _timer?.cancel();
    _timer = Timer(delay, () {
      if (ref.mounted) unawaited(check());
    });
  }

  Future<void> check() async {
    if (_running) return;
    final couple = ref.read(coupleProvider).value;
    final separation = couple?.separation;
    if (couple == null || (separation == null && couple.ending == null)) {
      _timer?.cancel();
      state = FinalizeState.idle;
      return;
    }

    final now = ref.read(separationClockProvider)();
    if (separation != null && !separation.isDue(now)) {
      state = couple.ending == null
          ? FinalizeState.idle
          : const FinalizeState(FinalizePhase.working);
      // Wake just after the end date.
      _wakeIn(separation.remaining(now) + const Duration(seconds: 2));
      return;
    }

    final retry = ref.read(separationRetryDelayProvider);
    _running = true;
    if (state.phase != FinalizePhase.waitingForServer) {
      state = const FinalizeState(FinalizePhase.working);
    }
    try {
      final result = await ref
          .read(endPairingGatewayProvider)
          .finalizeSeparation(couple.id);
      if (!ref.mounted) return;
      // Done: the couple and profile streams move everyone on. Until they
      // do, keep saying it's ending; check again in case they don't.
      state = const FinalizeState(FinalizePhase.working);
      _wakeIn(result.isDone ? retry * 2 : retry);
    } on EndPairingException catch (e) {
      if (!ref.mounted) return;
      switch (e.failure) {
        case EndPairingFailure.notReady:
          state = FinalizeState(FinalizePhase.notYet, notBefore: e.notBefore);
          final wait = e.notBefore?.difference(
            ref.read(separationClockProvider)(),
          );
          _wakeIn(wait == null || wait < retry ? retry : wait + retry ~/ 4);
        case EndPairingFailure.unavailable:
        case EndPairingFailure.denied:
        case EndPairingFailure.other:
          state = const FinalizeState(FinalizePhase.waitingForServer);
          _wakeIn(retry);
      }
    } catch (_) {
      if (!ref.mounted) return;
      state = const FinalizeState(FinalizePhase.waitingForServer);
      _wakeIn(retry);
    } finally {
      _running = false;
    }
  }
}

final separationFinalizerProvider =
    NotifierProvider.autoDispose<SeparationFinalizer, FinalizeState>(
      SeparationFinalizer.new,
    );
