import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:couple_app/core/widgets/animated_gradient_card.dart';
import 'package:couple_app/core/widgets/gradient_preset.dart';
import 'package:couple_app/features/auth/models/app_user.dart';
import 'package:couple_app/features/auth/models/phone_number.dart';
import 'package:couple_app/features/couple/data/couple_service.dart';
import 'package:couple_app/features/couple/data/pair_request_service.dart';
import 'package:couple_app/features/couple/models/couple.dart';
import 'package:couple_app/features/couple/providers/pair_request_providers.dart';
import 'package:couple_app/features/onboarding/widgets/busy_button_label.dart';
import 'package:couple_app/features/onboarding/widgets/pairing_error_text.dart';
import 'package:couple_app/features/onboarding/widgets/phone_number_field.dart';
import 'package:couple_app/features/onboarding/widgets/romance_kit.dart';

/// "Pair with their mobile number": type your partner's number and send
/// them a request. If nobody has joined with that number, offers the
/// invite to share instead.
class PairByNumberStep extends ConsumerStatefulWidget {
  const PairByNumberStep({
    super.key,
    required this.me,
    required this.onShareInvite,
    this.couple,
    this.onSent,
  });

  final AppUser me;

  /// [me]'s couple of one, if they made one already.
  final Couple? couple;

  /// Shares this user's invite (making their space first if needed).
  final Future<void> Function() onShareInvite;

  /// After a request went out.
  final VoidCallback? onSent;

  @override
  ConsumerState<PairByNumberStep> createState() => _PairByNumberStepState();
}

class _PairByNumberStepState extends ConsumerState<PairByNumberStep> {
  late final PairRequestService _requests;

  PhoneCountry _country = PhoneCountry.india;
  final _number = TextEditingController();
  String? _numberError;
  String? _error;
  bool _busy = false;

  /// The number has no account: offer the invite.
  bool _notJoined = false;
  bool _sent = false;

  @override
  void initState() {
    super.initState();
    _requests = ref.read(pairRequestServiceProvider);
  }

  @override
  void dispose() {
    _number.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final e164 = PhoneNumbers.toE164(_country, _number.text);
    if (e164 == null) {
      setState(
        () => _numberError = PhoneNumbers.validate(_country, _number.text),
      );
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
      _numberError = null;
      _notJoined = false;
    });
    try {
      final outcome = await _requests.requestByNumber(
        me: widget.me,
        toPhone: e164,
        myCouple: widget.couple,
      );
      if (!mounted) return;
      switch (outcome) {
        case PairByNumberNotJoined():
          setState(() => _notJoined = true);
        case PairByNumberSent():
          setState(() => _sent = true);
          widget.onSent?.call();
      }
    } on PairingException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = PairRequestService.couldNotPair);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _share() async {
    setState(() => _busy = true);
    try {
      await widget.onShareInvite();
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Could not open sharing. Try again.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    const preset = GradientPreset.mint;

    if (_sent) {
      return _SentCard(onAnother: () => setState(() => _sent = false));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 8),
        const Center(
          child: GlowBadge(
            preset: preset,
            icon: Icons.phone_in_talk_rounded,
            size: 68,
          ),
        ),
        const SizedBox(height: 16),
        Text(
          'Pair with their number',
          textAlign: TextAlign.center,
          style: romanceSerif(
            theme.textTheme.headlineSmall,
          ).copyWith(fontWeight: FontWeight.w700, fontStyle: FontStyle.italic),
        ),
        const SizedBox(height: 6),
        Text(
          'If they\'ve joined with this number, we\'ll ask them to pair with '
          'you. They\'ll see your name and number.',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
            height: 1.4,
          ),
        ),
        const SizedBox(height: 22),
        FrostedForm(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              PhoneNumberField(
                country: _country,
                controller: _number,
                enabled: !_busy,
                label: 'Their mobile number',
                errorText: _numberError,
                onCountryChanged: (c) => setState(() {
                  _country = c;
                  _numberError = null;
                }),
                onChanged: (_) {
                  if (_numberError != null || _notJoined) {
                    setState(() {
                      _numberError = null;
                      _notJoined = false;
                    });
                  }
                },
                onSubmitted: _submit,
              ),
              PairingErrorText(error: _error),
              const SizedBox(height: 20),
              FilledButton(
                onPressed: _busy ? null : _submit,
                style: pillButtonStyle(context, preset: GradientPreset.ocean),
                child: BusyButtonLabel(busy: _busy, label: 'Send request'),
              ),
            ],
          ),
        ),
        if (_notJoined) ...[
          const SizedBox(height: 16),
          _NotJoinedCard(busy: _busy, onShare: _share),
        ],
      ],
    );
  }
}

/// "They haven't joined yet — share your invite instead".
class _NotJoinedCard extends StatelessWidget {
  const _NotJoinedCard({required this.busy, required this.onShare});

  final bool busy;
  final VoidCallback onShare;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final b = theme.brightness;
    const preset = GradientPreset.sunny;
    return AnimatedGradientCard(
      preset: preset,
      radius: 24,
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const IconTile(
                icon: Icons.hourglass_empty_rounded,
                preset: preset,
                size: 42,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'They haven\'t joined yet — share your invite instead',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: preset.foreground(b),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Once they install the app, they can join with your code.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: preset.foregroundMuted(b),
            ),
          ),
          const SizedBox(height: 14),
          FilledButton.icon(
            onPressed: busy ? null : onShare,
            style: pillButtonStyle(context, minimumSize: const Size(0, 48)),
            icon: const Icon(Icons.ios_share),
            label: const Text('Share your invite'),
          ),
        ],
      ),
    );
  }
}

class _SentCard extends StatelessWidget {
  const _SentCard({required this.onAnother});

  final VoidCallback onAnother;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final b = theme.brightness;
    const preset = GradientPreset.mint;
    return AnimatedGradientCard(
      preset: preset,
      radius: 26,
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 16),
      child: Column(
        children: [
          const GlowBadge(
            preset: preset,
            icon: Icons.mark_email_read_outlined,
            size: 60,
          ),
          const SizedBox(height: 14),
          Text(
            'Request sent',
            style: romanceSerif(theme.textTheme.headlineSmall).copyWith(
              fontWeight: FontWeight.w700,
              fontStyle: FontStyle.italic,
              color: preset.foreground(b),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'When they accept, you\'ll be connected.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: preset.foregroundMuted(b),
            ),
          ),
          TextButton(
            onPressed: onAnother,
            child: const Text('Use another number'),
          ),
        ],
      ),
    );
  }
}
