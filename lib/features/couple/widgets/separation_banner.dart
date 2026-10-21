import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import 'package:couple_app/core/utils/snackbar.dart';
import 'package:couple_app/core/widgets/animated_gradient_card.dart';
import 'package:couple_app/core/widgets/gradient_preset.dart';
import 'package:couple_app/features/auth/providers/auth_providers.dart';
import 'package:couple_app/features/couple/data/separation_service.dart';
import 'package:couple_app/features/couple/models/couple.dart';
import 'package:couple_app/features/couple/models/separation.dart';
import 'package:couple_app/features/couple/providers/couple_providers.dart';
import 'package:couple_app/features/couple/providers/separation_providers.dart';
import 'package:couple_app/features/onboarding/widgets/busy_button_label.dart';
import 'package:couple_app/features/onboarding/widgets/romance_kit.dart';

/// "4 Nov", with a non-breaking space so it never splits across lines.
String separationDate(DateTime date) =>
    DateFormat('d MMM').format(date).replaceAll(' ', '\u00A0');

/// The card both partners see while their pairing is ending, on Home, Us
/// and (as a slim strip with [compact]) over the chat.
///
/// - The one who asked: "Your pairing ends on 4 Nov", with Cancel (we're
///   staying together) and Mute.
/// - The other: "Asha wants to end your pairing", with Agree or I don't
///   want this; after declining, a way to message them, and Agree still.
/// - Both: the date, the countdown, and that everything shared will be
///   deleted. Once the date passes: "Ending your pairing…", or "Waiting for
///   the server to finish" when the server isn't there yet.
///
/// Nothing is shown while the pairing isn't ending.
class SeparationBanner extends ConsumerStatefulWidget {
  const SeparationBanner({super.key, this.compact = false, this.onOpenChat});

  /// One line for the chat header; tapping opens the full card in a sheet.
  final bool compact;

  /// "Message Asha" after declining. Hidden when null.
  final VoidCallback? onOpenChat;

  @override
  ConsumerState<SeparationBanner> createState() => _SeparationBannerState();
}

class _SeparationBannerState extends ConsumerState<SeparationBanner> {
  Timer? _tick;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    // The countdown moves on its own.
    _tick = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  Future<void> _run(Future<void> Function(SeparationService s) action) async {
    final service = ref.read(separationServiceProvider);
    setState(() => _busy = true);
    try {
      await action(service);
    } on SeparationException catch (e) {
      if (mounted) context.showSnackMessage(e.message);
    } catch (_) {
      if (mounted) context.showSnackMessage('Couldn\'t update. Try again.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _agree(Couple couple, Separation s, String partner) async {
    final uid = ref.read(currentUidProvider);
    final when = s.effectiveAtIfAgreedAt(ref.read(separationClockProvider)());
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Agree to end your pairing?'),
        content: Text(
          'It will end on ${separationDate(when)}. Everything you and '
          '$partner shared will be deleted for both of you.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Not yet'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: pillButtonStyle(
              dialogContext,
              preset: GradientPreset.ocean,
              minimumSize: const Size(0, 44),
            ),
            child: const Text('Agree'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await _run(
      (service) => service.agree(coupleId: couple.id, uid: uid, current: s),
    );
  }

  void _openSheet() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) => const Padding(
        padding: EdgeInsets.fromLTRB(16, 0, 16, 24),
        child: SingleChildScrollView(child: SeparationBanner()),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final couple = ref.watch(coupleProvider).value;
    final separation = couple?.separation;
    if (couple == null || (separation == null && couple.ending == null)) {
      return const SizedBox.shrink();
    }
    final uid = ref.watch(currentUidProvider);
    final partner = ref.watch(partnerNameProvider);
    final muted = ref.watch(mutePartnerProvider);
    final finalize = ref.watch(separationFinalizerProvider);
    final now = ref.watch(separationClockProvider)();

    final view = _BannerView.of(
      couple: couple,
      separation: separation,
      uid: uid,
      partner: partner,
      now: now,
      finalize: finalize,
    );

    if (widget.compact) {
      return _CompactStrip(view: view, onTap: _openSheet);
    }

    final theme = Theme.of(context);
    final b = theme.brightness;
    const preset = GradientPreset.ocean;
    final fg = preset.foreground(b);
    final soft = preset.foregroundMuted(b);
    final s = separation;

    final actions = <Widget>[];
    if (s != null && !view.ending) {
      if (view.isRequester) {
        actions.addAll([
          FilledButton(
            key: const Key('separation-cancel'),
            onPressed: _busy
                ? null
                : () => _run(
                    (service) => service.cancel(
                      coupleId: couple.id,
                      uid: uid,
                      current: s,
                    ),
                  ),
            style: pillButtonStyle(
              context,
              preset: GradientPreset.ocean,
              minimumSize: const Size.fromHeight(48),
            ),
            child: BusyButtonLabel(
              busy: _busy,
              label: 'Cancel (we\'re staying together)',
            ),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            key: const Key('separation-mute'),
            onPressed: _busy
                ? null
                : () => _run(
                    (service) =>
                        service.setMutePartner(uid: uid, muted: !muted),
                  ),
            style: pillOutlineStyle(
              context,
              preset: GradientPreset.ocean,
              minimumSize: const Size.fromHeight(46),
            ),
            icon: Icon(
              muted
                  ? Icons.notifications_active_outlined
                  : Icons.notifications_off_outlined,
            ),
            label: Text(muted ? 'Unmute $partner' : 'Mute $partner'),
          ),
        ]);
      } else {
        final message =
            s.status == SeparationStatus.declined && widget.onOpenChat != null
            ? OutlinedButton.icon(
                onPressed: widget.onOpenChat,
                style: pillOutlineStyle(
                  context,
                  preset: GradientPreset.ocean,
                  minimumSize: const Size(0, 46),
                ),
                icon: const Icon(Icons.chat_bubble_outline, size: 18),
                label: Text('Message $partner'),
              )
            : null;
        final decline = s.status == SeparationStatus.requested
            ? OutlinedButton(
                key: const Key('separation-decline'),
                onPressed: _busy
                    ? null
                    : () => _run(
                        (service) => service.decline(
                          coupleId: couple.id,
                          uid: uid,
                          current: s,
                        ),
                      ),
                style: pillOutlineStyle(
                  context,
                  preset: GradientPreset.ocean,
                  minimumSize: const Size(0, 46),
                ),
                child: const Text('I don\'t want this'),
              )
            : null;
        final agree = s.status != SeparationStatus.agreed
            ? FilledButton(
                key: const Key('separation-agree'),
                onPressed: _busy ? null : () => _agree(couple, s, partner),
                style: pillButtonStyle(
                  context,
                  preset: GradientPreset.ocean,
                  minimumSize: const Size(0, 46),
                ),
                child: BusyButtonLabel(busy: _busy, label: 'Agree'),
              )
            : null;
        if (decline != null && agree != null) {
          actions.add(
            Row(
              children: [
                Expanded(child: decline),
                const SizedBox(width: 10),
                Expanded(child: agree),
              ],
            ),
          );
        } else {
          // After declining: the longer "Message Asha" gets its own row.
          for (final button in [?message, ?agree]) {
            if (actions.isNotEmpty) actions.add(const SizedBox(height: 8));
            actions.add(SizedBox(width: double.infinity, child: button));
          }
        }
      }
    }

    return Semantics(
      container: true,
      label: 'Your pairing is ending',
      child: AnimatedGradientCard(
        key: const Key('separation-banner'),
        preset: preset,
        radius: 26,
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                IconTile(icon: view.icon, preset: preset, size: 44),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    view.title,
                    style: romanceSerif(theme.textTheme.titleLarge).copyWith(
                      fontWeight: FontWeight.w700,
                      color: fg,
                      height: 1.2,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              view.body,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: soft,
                height: 1.4,
              ),
            ),
            if (view.note != null) ...[
              const SizedBox(height: 8),
              Text(
                view.note!,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: fg,
                  fontWeight: FontWeight.w600,
                  height: 1.4,
                ),
              ),
            ],
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerLeft,
              child: _CountdownPill(
                text: view.countdown,
                busy: view.spinning,
                preset: preset,
              ),
            ),
            if (actions.isNotEmpty) ...[const SizedBox(height: 14), ...actions],
          ],
        ),
      ),
    );
  }
}

/// The words on the banner, worked out once for both layouts.
class _BannerView {
  const _BannerView({
    required this.title,
    required this.body,
    required this.countdown,
    required this.icon,
    required this.isRequester,
    required this.ending,
    required this.strip,
    this.note,
    this.spinning = false,
  });

  final String title;
  final String body;
  final String? note;
  final String countdown;
  final IconData icon;
  final bool isRequester;

  /// Past the date: the server is (or should be) deleting.
  final bool ending;

  /// The one line for the chat strip.
  final String strip;

  /// The server is working on it right now.
  final bool spinning;

  factory _BannerView.of({
    required Couple couple,
    required Separation? separation,
    required String uid,
    required String partner,
    required DateTime now,
    required FinalizeState finalize,
  }) {
    final s = separation;
    final isRequester = s?.isRequestedBy(uid) ?? false;
    final due = couple.ending != null || s == null || s.isDue(now);

    if (due) {
      final waiting =
          couple.ending == null &&
          finalize.phase == FinalizePhase.waitingForServer;
      final notYet = finalize.phase == FinalizePhase.notYet;
      final serverDate = finalize.notBefore;
      if (notYet && serverDate != null && couple.ending == null) {
        final date = separationDate(serverDate);
        return _BannerView(
          title: 'Your pairing ends on $date',
          body: 'Everything you shared will be deleted.',
          countdown: Separation.countdown(serverDate.difference(now)),
          icon: Icons.event_outlined,
          isRequester: isRequester,
          ending: true,
          strip: 'Your pairing ends on $date',
        );
      }
      return _BannerView(
        title: waiting
            ? 'Waiting for the server to finish'
            : 'Ending your pairing…',
        body: waiting
            ? 'Your pairing has reached its end date. We\'ll keep trying to '
                  'finish, and everything you shared will be deleted.'
            : 'Everything you shared is being deleted.',
        countdown: waiting ? 'We\'ll keep trying' : 'Ending now',
        icon: Icons.hourglass_bottom_rounded,
        isRequester: isRequester,
        ending: true,
        spinning: !waiting,
        strip: waiting
            ? 'Waiting for the server to finish'
            : 'Ending your pairing…',
      );
    }

    final date = separationDate(s.effectiveAt);
    final countdown = Separation.countdown(s.remaining(now));
    final ends = 'Your pairing ends on $date.';
    const deleted = 'Everything you shared will be deleted.';

    if (isRequester) {
      return _BannerView(
        title: 'Your pairing ends on $date',
        body: deleted,
        note: switch (s.status) {
          SeparationStatus.agreed => '$partner agreed.',
          SeparationStatus.declined =>
            '$partner said they don\'t want this. It still ends on $date '
                'unless you cancel.',
          SeparationStatus.requested => null,
        },
        countdown: countdown,
        icon: Icons.event_outlined,
        isRequester: true,
        ending: false,
        strip: 'Your pairing ends on $date · $countdown',
      );
    }

    return switch (s.status) {
      SeparationStatus.requested => _BannerView(
        title: '$partner wants to end your pairing',
        body: '$ends $deleted',
        countdown: countdown,
        icon: Icons.spa_outlined,
        isRequester: false,
        ending: false,
        strip: '$partner wants to end your pairing · Tap to answer',
      ),
      SeparationStatus.declined => _BannerView(
        title: 'You said you don\'t want this',
        body: '$ends $deleted',
        note:
            '$partner can still end it on $date. You can message them or '
            'ask to talk.',
        countdown: countdown,
        icon: Icons.favorite_border_rounded,
        isRequester: false,
        ending: false,
        strip: 'Your pairing ends on $date · $countdown',
      ),
      SeparationStatus.agreed => _BannerView(
        title: 'You both agreed to end your pairing',
        body: '$ends $deleted',
        countdown: countdown,
        icon: Icons.event_outlined,
        isRequester: false,
        ending: false,
        strip: 'Your pairing ends on $date · $countdown',
      ),
    };
  }
}

class _CountdownPill extends StatelessWidget {
  const _CountdownPill({
    required this.text,
    required this.busy,
    required this.preset,
  });

  final String text;
  final bool busy;
  final GradientPreset preset;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final b = theme.brightness;
    final dark = preset.isDarkIn(b);
    final accent = dark ? preset.accent(b) : preset.ink;
    return Container(
      key: const Key('separation-countdown'),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: dark ? .12 : .7),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (busy)
            SizedBox(
              width: 12,
              height: 12,
              child: CircularProgressIndicator(strokeWidth: 2, color: accent),
            )
          else
            Icon(Icons.schedule_rounded, size: 16, color: accent),
          const SizedBox(width: 6),
          Text(
            text,
            style: theme.textTheme.labelLarge?.copyWith(
              color: accent,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

/// The chat's one-line version.
class _CompactStrip extends StatelessWidget {
  const _CompactStrip({required this.view, required this.onTap});

  final _BannerView view;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final b = theme.brightness;
    const preset = GradientPreset.ocean;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
      child: AnimatedGradientCard(
        key: const Key('separation-strip'),
        preset: preset,
        radius: 18,
        animate: false,
        sheen: false,
        padding: const EdgeInsets.fromLTRB(12, 9, 8, 9),
        onTap: onTap,
        child: Row(
          children: [
            Icon(
              view.icon,
              size: 18,
              color: preset.isDarkIn(b) ? preset.accent(b) : preset.ink,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                view.strip,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelLarge?.copyWith(
                  color: preset.foreground(b),
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            Icon(Icons.chevron_right_rounded, color: preset.foregroundMuted(b)),
          ],
        ),
      ),
    );
  }
}
