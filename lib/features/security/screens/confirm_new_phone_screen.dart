import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import 'package:couple_app/core/utils/snackbar.dart';
import 'package:couple_app/core/widgets/animated_gradient_card.dart';
import 'package:couple_app/core/widgets/entrance_animation.dart';
import 'package:couple_app/core/widgets/glass.dart';
import 'package:couple_app/core/widgets/gradient_preset.dart';
import 'package:couple_app/features/auth/providers/auth_providers.dart';
import 'package:couple_app/features/onboarding/widgets/busy_button_label.dart';
import 'package:couple_app/features/onboarding/widgets/romance_kit.dart';
import 'package:couple_app/features/security/data/account_reauth.dart';
import 'package:couple_app/features/security/data/device_trust_service.dart';
import 'package:couple_app/features/security/device_trust_controller.dart';
import 'package:couple_app/features/security/models/device_check.dart';
import 'package:couple_app/features/security/models/security_event.dart';
import 'package:couple_app/features/security/providers/security_providers.dart';

/// The calm line that explains why we ask at all.
const newPhoneWhy =
    'We check new phones to keep your space private, in case a phone '
    'number ever changes hands.';

/// The note about reinstalling, which looks like a new phone.
const newPhoneReinstallNote =
    'Reinstalled the app? That counts as a new phone too, so we ask once '
    'more. That\'s expected.';

/// "6 days 23 hours", "5 hours 12 min", "3 min".
String waitLeftLabel(Duration left) {
  String plural(int n, String word) => '$n $word${n == 1 ? '' : 's'}';
  if (left.inDays >= 1) {
    final hours = left.inHours % 24;
    return hours == 0
        ? plural(left.inDays, 'day')
        : '${plural(left.inDays, 'day')} ${plural(hours, 'hour')}';
  }
  if (left.inHours >= 1) {
    return '${plural(left.inHours, 'hour')} ${left.inMinutes % 60} min';
  }
  return '${left.inMinutes < 1 ? 1 : left.inMinutes} min';
}

enum _Step { options, partner, password, wait, rejected }

/// "Confirm it's you": shown by the auth gate, instead of the app, on a
/// phone that hasn't passed sign-in protection yet (see
/// [DeviceTrustController]). Nothing of the couple is loaded behind it.
///
/// Offers whichever apply: the partner vouching for this phone (with a
/// two-digit number to compare), the account's password or Google
/// account, or, with neither, a 7-day wait that the owner's other phones
/// can pause with "It wasn't me".
class ConfirmNewPhoneScreen extends ConsumerStatefulWidget {
  const ConfirmNewPhoneScreen({
    super.key,
    required this.uid,
    required this.trust,
  });

  final String uid;
  final DeviceTrust trust;

  @override
  ConsumerState<ConfirmNewPhoneScreen> createState() =>
      _ConfirmNewPhoneScreenState();
}

class _ConfirmNewPhoneScreenState extends ConsumerState<ConfirmNewPhoneScreen> {
  static const _preset = GradientPreset.ocean;

  late final DeviceTrustService _service;
  late final AccountReauth _reauth;
  late final DateTime Function() _now;

  _Step _step = _Step.options;
  bool _busy = false;
  String? _error;

  // Partner
  DeviceCheck? _check;
  StreamSubscription<DeviceCheck?>? _checkSub;

  // Password
  final _password = TextEditingController();
  bool _resetSent = false;

  // Wait
  StreamSubscription<({bool exists, DateTime? at})>? _waitSub;
  StreamSubscription<DateTime?>? _blockSub;
  DateTime? _waitStart;
  DateTime? _blockUntil;
  bool _waitRequested = false;
  Timer? _tick;

  DeviceTrust get _trust => widget.trust;
  PartnerContact? get _partner => _trust.partner;

  @override
  void initState() {
    super.initState();
    _service = ref.read(deviceTrustServiceProvider);
    _reauth = ref.read(accountReauthProvider);
    _now = ref.read(securityClockProvider);

    final existing = _trust.existingCheck;
    if (_trust.onlyWait) {
      _startWait();
    } else if (existing != null) {
      if (existing.status == DeviceCheckStatus.rejected) {
        _check = existing;
        _step = _Step.rejected;
      } else if (existing.status == DeviceCheckStatus.approved ||
          existing.isFreshAt(_now())) {
        _step = _Step.partner;
        _check = existing;
        _follow(existing);
      } else {
        // Too old for the partner to be asked; a new one is made on demand.
        unawaited(_quietly(() => _service.deleteCheck(_cid!, existing.id)));
      }
    }
  }

  @override
  void dispose() {
    _checkSub?.cancel();
    _waitSub?.cancel();
    _blockSub?.cancel();
    _tick?.cancel();
    _password.dispose();
    super.dispose();
  }

  String? get _cid => _partner?.coupleId;

  Future<void> _quietly(Future<void> Function() action) async {
    try {
      await action();
    } catch (e) {
      debugPrint('confirm new phone: $e');
    }
  }

  DeviceTrustController get _controller =>
      ref.read(deviceTrustProvider(widget.uid).notifier);

  Future<void> _run(Future<void> Function() action) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
    } on ReauthException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (e) {
      debugPrint('confirm new phone failed: $e');
      if (mounted) setState(() => _error = 'Something went wrong. Try again.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // ---- Partner --------------------------------------------------------------

  Future<void> _askPartner() => _run(() async {
    final partner = _partner!;
    final code = _service.newCode();
    final id = await _service.createCheck(
      cid: partner.coupleId,
      uid: widget.uid,
      deviceId: _trust.deviceId,
      deviceName: _trust.deviceName,
      code: code,
    );
    if (!mounted) return;
    final check = DeviceCheck(
      id: id,
      uid: widget.uid,
      deviceId: _trust.deviceId,
      deviceName: _trust.deviceName,
      code: code,
      status: DeviceCheckStatus.pending,
    );
    setState(() {
      _check = check;
      _step = _Step.partner;
    });
    _follow(check);
  });

  /// Watches [check] until the partner answers.
  void _follow(DeviceCheck check) {
    _checkSub?.cancel();
    _checkSub = _service.watchCheck(_cid!, check.id).listen((latest) {
      if (!mounted) return;
      if (latest == null) {
        setState(() {
          _check = null;
          _step = _Step.options;
        });
        return;
      }
      setState(() {
        _check = latest;
        if (latest.status == DeviceCheckStatus.rejected) {
          _step = _Step.rejected;
        }
      });
      if (latest.status == DeviceCheckStatus.approved) {
        unawaited(_run(() => _controller.passWithPartner(latest)));
      }
    });
  }

  Future<void> _cancelPartner() async {
    final check = _check;
    unawaited(_checkSub?.cancel());
    _checkSub = null;
    setState(() {
      _check = null;
      _step = _Step.options;
    });
    if (check != null) {
      await _quietly(() => _service.deleteCheck(_cid!, check.id));
    }
  }

  // ---- Account --------------------------------------------------------------

  Future<void> _confirmPassword() => _run(() async {
    final password = _password.text;
    if (password.isEmpty) {
      setState(() => _error = 'Enter your password.');
      return;
    }
    await _reauth.withPassword(password);
    await _controller.passWithAccount();
  });

  Future<void> _sendReset() => _run(() async {
    await _reauth.sendPasswordReset();
    if (mounted) setState(() => _resetSent = true);
  });

  Future<void> _google() => _run(() async {
    if (await _reauth.withGoogle()) await _controller.passWithAccount();
  });

  // ---- Waiting --------------------------------------------------------------

  void _startWait() {
    _step = _Step.wait;
    _waitSub = _service.watchWaitStart(widget.uid, _trust.deviceId).listen((
      wait,
    ) {
      if (!mounted) return;
      if (!wait.exists && !_waitRequested) {
        // Starts the clock and tells the owner's other phones.
        _waitRequested = true;
        unawaited(
          _quietly(
            () => _service.addEvent(
              uid: widget.uid,
              id: SecurityEvent.waitId(_trust.deviceId),
              type: SecurityEventType.newPhoneWaiting,
              deviceName: _trust.deviceName,
            ),
          ),
        );
      } else if (!wait.exists) {
        // The notice was dismissed elsewhere: the wait begins again.
        _waitRequested = false;
      }
      setState(() => _waitStart = wait.at);
    });
    _blockSub = _service.watchBlockUntil(widget.uid).listen((until) {
      if (mounted) setState(() => _blockUntil = until);
    });
    _tick = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  bool get _blocked {
    final until = _blockUntil;
    return until != null && _now().isBefore(until);
  }

  Duration? get _waitLeft {
    final start = _waitStart;
    if (start == null) return null;
    final left = start.add(DeviceTrustController.waitFor).difference(_now());
    return left.isNegative ? Duration.zero : left;
  }

  Future<void> _finishWait() => _run(() async {
    if (_blocked || _waitLeft != Duration.zero) return;
    await _controller.passAfterWait();
  });

  // ---- Leaving --------------------------------------------------------------

  Future<void> _signOut() async {
    final check = _check;
    setState(() => _busy = true);
    if (check != null && _cid != null) {
      await _quietly(() => _service.deleteCheck(_cid!, check.id));
    }
    try {
      await ref.read(authServiceProvider).signOut();
    } catch (e) {
      debugPrint('sign out failed: $e');
      if (mounted) {
        setState(() => _busy = false);
        context.showSnackMessage('Couldn\'t sign out. Try again.');
      }
    }
  }

  void _back() => setState(() {
    _step = _Step.options;
    _error = null;
  });

  // ---- Build ----------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final page = switch (_step) {
      _Step.options => _options(context),
      _Step.partner => _partnerWaiting(context),
      _Step.password => _passwordPage(context),
      _Step.wait => _waitPage(context),
      _Step.rejected => _rejectedPage(context),
    };
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (_step == _Step.password) _back();
        if (_step == _Step.partner) _cancelPartner();
      },
      child: RomanceBackdrop(
        preset: _preset,
        strength: .55,
        child: Scaffold(
          backgroundColor: Colors.transparent,
          body: SafeArea(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 250),
              child: KeyedSubtree(key: ValueKey(_step), child: page),
            ),
          ),
        ),
      ),
    );
  }

  Widget _options(BuildContext context) {
    final partner = _partner;
    final reauth = _trust.reauth;
    final reason = _trust.reason == NewPhoneReason.inactive
        ? 'It\'s been a while since your account was opened, so we check '
              'once more on ${_trust.deviceName}.'
        : 'This is the first time ${_trust.deviceName} has opened your '
              'account.';
    return _Page(
      icon: Icons.verified_user_outlined,
      title: 'Confirm it\'s you',
      lead: newPhoneWhy,
      children: [
        Text(
          reason,
          key: const Key('new-phone-reason'),
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        const SizedBox(height: 18),
        if (_error != null) _ErrorLine(_error!),
        GradientGroup(
          preset: _preset,
          children: [
            if (partner != null)
              _OptionTile(
                key: const Key('new-phone-ask-partner'),
                icon: Icons.favorite_outline,
                title: 'Ask ${partner.name}',
                subtitle:
                    '${partner.name} confirms it\'s you from their phone, '
                    'with a number only you can see.',
                onTap: _busy ? null : _askPartner,
              ),
            if (reauth.password)
              _OptionTile(
                key: const Key('new-phone-password'),
                icon: Icons.key_outlined,
                title: 'Use your password',
                subtitle: 'For ${reauth.passwordEmail}',
                onTap: _busy
                    ? null
                    : () => setState(() {
                        _step = _Step.password;
                        _error = null;
                      }),
              ),
            if (reauth.google)
              _OptionTile(
                key: const Key('new-phone-google'),
                icon: Icons.account_circle_outlined,
                title: 'Continue with Google',
                subtitle: 'With ${reauth.googleEmail}',
                onTap: _busy ? null : _google,
              ),
          ],
        ),
        const SizedBox(height: 18),
        _Note(newPhoneReinstallNote),
        const SizedBox(height: 8),
        _SignOutButton(busy: _busy, onPressed: _signOut),
      ],
    );
  }

  Widget _partnerWaiting(BuildContext context) {
    final theme = Theme.of(context);
    final b = theme.brightness;
    final name = _partner?.name ?? 'your partner';
    final code = _check?.code;
    return _Page(
      icon: Icons.favorite_outline,
      title: 'Waiting for $name',
      lead:
          '$name will be asked on their phone: is this really you? Tell them '
          'the number you see here.',
      children: [
        AnimatedGradientCard(
          preset: GradientPreset.lavender,
          radius: 28,
          padding: const EdgeInsets.symmetric(vertical: 22, horizontal: 18),
          child: Column(
            children: [
              Text(
                'Your number',
                style: theme.textTheme.labelLarge?.copyWith(
                  color: GradientPreset.lavender.foregroundMuted(b),
                  letterSpacing: .4,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                code == null || code == 0 ? '··' : '$code',
                key: const Key('new-phone-code'),
                style: romanceSerif(theme.textTheme.displayLarge).copyWith(
                  fontSize: 76,
                  fontWeight: FontWeight.w700,
                  color: b == Brightness.dark
                      ? GradientPreset.lavender.accent(b)
                      : GradientPreset.lavender.ink,
                  height: 1.05,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // A soft heartbeat rather than a spinner (still when motion is
            // reduced).
            Pulse(
              child: Icon(
                Icons.favorite_rounded,
                size: 18,
                color: b == Brightness.dark
                    ? GradientPreset.lavender.accent(b)
                    : GradientPreset.lavender.ink,
              ),
              builder: (context, v, child) =>
                  Opacity(opacity: .45 + .55 * v, child: child),
            ),
            const SizedBox(width: 10),
            Flexible(
              child: Text(
                'Waiting for $name\'s answer…',
                style: theme.textTheme.bodyMedium,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (_error != null) _ErrorLine(_error!),
        const SizedBox(height: 14),
        OutlinedButton(
          key: const Key('new-phone-cancel-partner'),
          onPressed: _busy ? null : _cancelPartner,
          style: pillOutlineStyle(context, preset: _preset),
          child: Text(_trust.reauth.any ? 'Try another way' : 'Cancel'),
        ),
      ],
    );
  }

  Widget _passwordPage(BuildContext context) {
    final email = _trust.reauth.passwordEmail ?? '';
    return _Page(
      icon: Icons.key_outlined,
      title: 'Enter your password',
      lead:
          'The password for $email. A new owner of your number wouldn\'t '
          'know it.',
      onBack: _busy ? null : _back,
      children: [
        FrostedForm(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                key: const Key('new-phone-password-field'),
                controller: _password,
                obscureText: true,
                autofocus: true,
                autofillHints: const [AutofillHints.password],
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _busy ? null : _confirmPassword(),
                decoration: InputDecoration(
                  labelText: 'Password',
                  prefixIcon: const Icon(Icons.lock_outline),
                  errorText: _error,
                ),
              ),
              const SizedBox(height: 16),
              FilledButton(
                key: const Key('new-phone-password-confirm'),
                onPressed: _busy ? null : _confirmPassword,
                style: pillButtonStyle(context, preset: _preset),
                child: BusyButtonLabel(busy: _busy, label: 'Confirm'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        TextButton(
          onPressed: _busy || _resetSent ? null : _sendReset,
          child: Text(
            _resetSent
                ? 'Reset link sent to $email'
                : 'Forgot it? Email me a reset link',
            textAlign: TextAlign.center,
          ),
        ),
      ],
    );
  }

  Widget _waitPage(BuildContext context) {
    final theme = Theme.of(context);
    final b = theme.brightness;
    final left = _waitLeft;
    final blocked = _blocked;
    final done = left == Duration.zero && !blocked;
    final title = blocked
        ? 'Waiting is paused'
        : done
        ? 'Thanks for waiting'
        : 'One week, to be safe';
    final lead = blocked
        ? 'Someone using this account on another phone said this sign-in '
              'wasn\'t them.'
        : done
        ? 'Nobody said this sign-in wasn\'t you, so ${_trust.deviceName} '
              'can open your account now.'
        : 'This account has no partner or recovery email that can vouch '
              'for a new phone, so we wait 7 days before opening it here.';

    final ink = b == Brightness.dark ? _preset.accent(b) : _preset.ink;
    return _Page(
      icon: blocked
          ? Icons.pause_circle_outline
          : done
          ? Icons.lock_open_outlined
          : Icons.hourglass_top_rounded,
      title: title,
      lead: lead,
      children: [
        if (!done)
          AnimatedGradientCard(
            preset: _preset,
            radius: 28,
            padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 18),
            child: Column(
              children: [
                Text(
                  blocked ? 'Paused until' : 'Opens in',
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: _preset.foregroundMuted(b),
                    letterSpacing: .4,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  blocked
                      ? DateFormat('d MMM').format(_blockUntil!)
                      : left == null
                      ? 'Starting…'
                      : waitLeftLabel(left),
                  key: const Key('new-phone-wait-left'),
                  textAlign: TextAlign.center,
                  style: romanceSerif(
                    theme.textTheme.headlineMedium,
                  ).copyWith(fontWeight: FontWeight.w700, color: ink),
                ),
                if (!blocked && left != null) ...[
                  const SizedBox(height: 12),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: LinearProgressIndicator(
                      value:
                          1 -
                          left.inMinutes /
                              DeviceTrustController.waitFor.inMinutes,
                      minHeight: 8,
                      color: ink,
                      backgroundColor: Colors.white.withValues(alpha: .55),
                    ),
                  ),
                ],
              ],
            ),
          ),
        if (done)
          FilledButton(
            key: const Key('new-phone-wait-continue'),
            onPressed: _busy ? null : _finishWait,
            style: pillButtonStyle(context, preset: _preset),
            child: BusyButtonLabel(busy: _busy, label: 'Continue'),
          ),
        if (_error != null) ...[const SizedBox(height: 8), _ErrorLine(_error!)],
        const SizedBox(height: 18),
        if (!done)
          _Reasons(
            items: [
              (
                Icons.sms_outlined,
                'Mobile numbers sometimes pass to someone new. A text code '
                    'alone can\'t tell us it\'s you.',
              ),
              (
                Icons.phone_android_outlined,
                'If you still have your old phone, you\'ll see a notice '
                    'there. Tapping "It wasn\'t me" pauses this.',
              ),
              (
                Icons.alternate_email_rounded,
                'Add a recovery email next time (Us, then Sign-in '
                    'protection), and a new phone takes a minute instead.',
              ),
            ],
          ),
        const SizedBox(height: 14),
        _Note(newPhoneReinstallNote),
        const SizedBox(height: 8),
        _SignOutButton(busy: _busy, onPressed: _signOut),
      ],
    );
  }

  Widget _rejectedPage(BuildContext context) {
    final name = _partner?.name ?? 'Your partner';
    return _Page(
      icon: Icons.do_not_disturb_on_outlined,
      title: 'Your partner didn\'t recognise this sign-in',
      lead:
          '$name said this wasn\'t you, so we\'ll sign out on this phone. '
          'If it was you, talk to them and try again.',
      children: [
        FilledButton(
          key: const Key('new-phone-rejected-sign-out'),
          onPressed: _busy ? null : _signOut,
          style: pillButtonStyle(context, preset: _preset),
          child: BusyButtonLabel(busy: _busy, label: 'Sign out'),
        ),
      ],
    );
  }
}

/// A page of the flow: a glowing badge, a serif title, a lead and content.
class _Page extends StatelessWidget {
  const _Page({
    required this.icon,
    required this.title,
    required this.lead,
    required this.children,
    this.onBack,
  });

  final IconData icon;
  final String title;
  final String lead;
  final List<Widget> children;
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Stack(
      children: [
        Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(22, 28, 22, 24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: GlowBadge(
                      icon: icon,
                      preset: GradientPreset.ocean,
                      size: 80,
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    title,
                    textAlign: TextAlign.center,
                    style: romanceSerif(theme.textTheme.headlineMedium)
                        .copyWith(
                          fontWeight: FontWeight.w700,
                          fontStyle: FontStyle.italic,
                        ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    lead,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyLarge?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 20),
                  ...children,
                ],
              ),
            ),
          ),
        ),
        if (onBack != null)
          Positioned(
            left: 4,
            top: 4,
            child: IconButton(
              tooltip: 'Back',
              icon: const Icon(Icons.arrow_back),
              onPressed: onBack,
            ),
          ),
      ],
    );
  }
}

class _OptionTile extends StatelessWidget {
  const _OptionTile({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: const EdgeInsets.fromLTRB(14, 6, 12, 6),
      leading: IconTile(icon: icon, preset: GradientPreset.ocean),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 2),
        child: Text(subtitle),
      ),
      trailing: const Icon(Icons.chevron_right),
      onTap: onTap,
    );
  }
}

/// Short reasons, each with an icon, on frosted glass.
class _Reasons extends StatelessWidget {
  const _Reasons({required this.items});

  final List<(IconData, String)> items;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final b = theme.brightness;
    return GlassPanel(
      dark: b == Brightness.dark,
      radius: 22,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final (icon, text) in items)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    icon,
                    size: 20,
                    color: b == Brightness.dark
                        ? GradientPreset.ocean.accent(b)
                        : GradientPreset.ocean.ink,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      text,
                      style: theme.textTheme.bodyMedium?.copyWith(height: 1.35),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _Note extends StatelessWidget {
  const _Note(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Text(
      text,
      textAlign: TextAlign.center,
      style: theme.textTheme.bodySmall?.copyWith(
        color: theme.colorScheme.onSurfaceVariant,
        height: 1.4,
      ),
    );
  }
}

class _ErrorLine extends StatelessWidget {
  const _ErrorLine(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: theme.textTheme.bodyMedium?.copyWith(
          color: theme.colorScheme.error,
        ),
      ),
    );
  }
}

class _SignOutButton extends StatelessWidget {
  const _SignOutButton({required this.busy, required this.onPressed});

  final bool busy;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: TextButton(
        key: const Key('new-phone-sign-out'),
        onPressed: busy ? null : onPressed,
        child: const Text('Not your account? Sign out'),
      ),
    );
  }
}

/// While the gate is deciding couldn't reach the server: say so, and try
/// again.
class NewPhoneCheckErrorScreen extends StatelessWidget {
  const NewPhoneCheckErrorScreen({
    super.key,
    required this.onRetry,
    required this.onSignOut,
  });

  final VoidCallback onRetry;
  final VoidCallback onSignOut;

  @override
  Widget build(BuildContext context) {
    return RomanceBackdrop(
      preset: GradientPreset.ocean,
      strength: .55,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: SafeArea(
          child: _Page(
            icon: Icons.cloud_off_outlined,
            title: 'Can\'t check this phone',
            lead:
                'We need a connection to check this phone before opening '
                'your space. Check your network and try again.',
            children: [
              FilledButton(
                key: const Key('new-phone-retry'),
                onPressed: onRetry,
                style: pillButtonStyle(context, preset: GradientPreset.ocean),
                child: const Text('Try again'),
              ),
              const SizedBox(height: 8),
              _SignOutButton(busy: false, onPressed: onSignOut),
            ],
          ),
        ),
      ),
    );
  }
}
