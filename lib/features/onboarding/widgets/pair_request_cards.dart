import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:couple_app/core/widgets/animated_gradient_card.dart';
import 'package:couple_app/core/widgets/gradient_preset.dart';
import 'package:couple_app/features/auth/models/phone_number.dart';
import 'package:couple_app/features/couple/data/couple_service.dart';
import 'package:couple_app/features/couple/data/pair_request_service.dart';
import 'package:couple_app/features/couple/models/couple.dart';
import 'package:couple_app/features/couple/models/pair_request.dart';
import 'package:couple_app/features/couple/providers/pair_request_providers.dart';
import 'package:couple_app/features/onboarding/widgets/busy_button_label.dart';
import 'package:couple_app/features/onboarding/widgets/romance_kit.dart';

/// "Asha (+91 98•••• 3210) wants to pair with you", with Accept and
/// Decline, for each pending request to [uid]. Nothing when there are none.
///
/// Accepting joins the sender's space with their invite, as typing the code
/// would. [myCouple] is [uid]'s own waiting space, which is given up.
class IncomingPairRequests extends ConsumerStatefulWidget {
  const IncomingPairRequests({super.key, required this.uid, this.myCouple});

  final String uid;
  final Couple? myCouple;

  @override
  ConsumerState<IncomingPairRequests> createState() =>
      _IncomingPairRequestsState();
}

class _IncomingPairRequestsState extends ConsumerState<IncomingPairRequests> {
  late final PairRequestService _service;
  String? _busyId;
  String? _error;
  String? _errorId;

  @override
  void initState() {
    super.initState();
    _service = ref.read(pairRequestServiceProvider);
  }

  Future<void> _run(PairRequest r, Future<void> Function() action) async {
    setState(() {
      _busyId = r.id;
      _error = null;
      _errorId = null;
    });
    try {
      await action();
    } on PairingException catch (e) {
      if (mounted) {
        setState(() {
          _error = e.message;
          _errorId = r.id;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _error = 'Something went wrong. Try again.';
          _errorId = r.id;
        });
      }
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final requests =
        ref.watch(incomingPairRequestsProvider(widget.uid)).value ??
        const <PairRequest>[];
    if (requests.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final r in requests)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: IncomingPairRequestCard(
              request: r,
              busy: _busyId == r.id,
              error: _errorId == r.id ? _error : null,
              onAccept: _busyId != null
                  ? null
                  : () => _run(
                      r,
                      () => _service.accept(
                        uid: widget.uid,
                        request: r,
                        myCouple: widget.myCouple,
                      ),
                    ),
              onDecline: _busyId != null
                  ? null
                  : () => _run(r, () => _service.decline(r)),
            ),
          ),
      ],
    );
  }
}

/// One incoming request.
class IncomingPairRequestCard extends StatelessWidget {
  const IncomingPairRequestCard({
    super.key,
    required this.request,
    required this.onAccept,
    required this.onDecline,
    this.busy = false,
    this.error,
  });

  final PairRequest request;
  final VoidCallback? onAccept;
  final VoidCallback? onDecline;
  final bool busy;
  final String? error;

  /// "Asha (+91 98•••• 3210)", or just the name without a number.
  static String who(PairRequest r) => r.fromPhone.isEmpty
      ? r.fromName
      : '${r.fromName} (${PhoneNumbers.mask(r.fromPhone)})';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final b = theme.brightness;
    const preset = GradientPreset.blush;
    final initial = request.fromName.characters.first.toUpperCase();

    return AnimatedGradientCard(
      preset: preset,
      radius: 26,
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              GlowRing(
                width: 3,
                child: CircleAvatar(
                  radius: 22,
                  backgroundColor: theme.colorScheme.primaryContainer,
                  child: Text(
                    initial,
                    style: romanceSerif(theme.textTheme.titleLarge).copyWith(
                      fontWeight: FontWeight.w700,
                      color: theme.colorScheme.onPrimaryContainer,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  '${who(request)} wants to pair with you',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: preset.foreground(b),
                    height: 1.3,
                  ),
                ),
              ),
            ],
          ),
          if (error != null) ...[
            const SizedBox(height: 10),
            Text(
              error!,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.error,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: onDecline,
                  style: pillOutlineStyle(
                    context,
                    minimumSize: const Size(0, 46),
                  ),
                  child: const Text('Decline'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton(
                  onPressed: onAccept,
                  style: pillButtonStyle(
                    context,
                    minimumSize: const Size(0, 46),
                  ),
                  child: BusyButtonLabel(busy: busy, label: 'Accept'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// The latest request [uid] sent: waiting (with Cancel), or the generic
/// "Couldn't pair with this number" once it was declined.
class OutgoingPairRequestCard extends ConsumerStatefulWidget {
  const OutgoingPairRequestCard({super.key, required this.uid});

  final String uid;

  @override
  ConsumerState<OutgoingPairRequestCard> createState() =>
      _OutgoingPairRequestCardState();
}

class _OutgoingPairRequestCardState
    extends ConsumerState<OutgoingPairRequestCard> {
  late final PairRequestService _service;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _service = ref.read(pairRequestServiceProvider);
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() => _busy = true);
    try {
      await action();
    } catch (_) {
      // The card stays; they can try again.
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final requests =
        ref.watch(outgoingPairRequestsProvider(widget.uid)).value ??
        const <PairRequest>[];
    PairRequest? shown;
    for (final r in requests) {
      if (r.status == PairRequestStatus.pending ||
          r.status == PairRequestStatus.declined) {
        shown = r;
        break;
      }
    }
    final request = shown;
    if (request == null) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final b = theme.brightness;
    final pending = request.isPending;
    final preset = pending ? GradientPreset.mint : GradientPreset.sunny;
    final number = request.toPhone.isEmpty
        ? 'them'
        : PhoneNumbers.format(request.toPhone);

    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: AnimatedGradientCard(
        preset: preset,
        radius: 24,
        padding: const EdgeInsets.fromLTRB(16, 14, 8, 10),
        child: Row(
          children: [
            IconTile(
              icon: pending
                  ? Icons.schedule_send_rounded
                  : Icons.info_outline_rounded,
              preset: preset,
              size: 40,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                pending
                    ? 'Waiting for $number to accept'
                    : PairRequestService.couldNotPair,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: preset.foreground(b),
                ),
              ),
            ),
            TextButton(
              onPressed: _busy
                  ? null
                  : () => _run(
                      () => pending
                          ? _service.cancel(request)
                          : _service.dismiss(request),
                    ),
              style: TextButton.styleFrom(
                foregroundColor: preset.isDarkIn(b)
                    ? preset.accent(b)
                    : preset.ink,
              ),
              child: Text(pending ? 'Cancel' : 'OK'),
            ),
          ],
        ),
      ),
    );
  }
}
