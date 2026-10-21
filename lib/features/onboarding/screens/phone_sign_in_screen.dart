import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:couple_app/core/widgets/gradient_preset.dart';
import 'package:couple_app/features/auth/data/auth_service.dart';
import 'package:couple_app/features/auth/data/phone_auth_gateway.dart';
import 'package:couple_app/features/auth/data/phone_number_service.dart';
import 'package:couple_app/features/auth/models/phone_number.dart';
import 'package:couple_app/features/auth/providers/auth_providers.dart';
import 'package:couple_app/features/onboarding/widgets/busy_button_label.dart';
import 'package:couple_app/features/onboarding/widgets/otp_code_field.dart';
import 'package:couple_app/features/onboarding/widgets/pairing_error_text.dart';
import 'package:couple_app/features/onboarding/widgets/phone_number_field.dart';
import 'package:couple_app/features/onboarding/widgets/romance_kit.dart';

/// Sign in with a mobile number, or ([PhoneAuthMode.link]) add one to the
/// signed-in account: the number, then the six-digit SMS code.
///
/// Once verified, the number is saved on the profile and in `phoneIndex`
/// so a partner can find you by it. Signing in needs no navigation (the
/// auth gate moves on); adding a number pops with `true`.
class PhoneSignInScreen extends ConsumerStatefulWidget {
  const PhoneSignInScreen({
    super.key,
    this.mode = PhoneAuthMode.signIn,
    this.onBack,
  });

  final PhoneAuthMode mode;

  /// Back from the number step. Defaults to popping the route.
  final VoidCallback? onBack;

  /// Seconds before a new code can be sent.
  static const resendAfter = 30;

  static Route<bool> linkRoute() => MaterialPageRoute<bool>(
    builder: (_) => const PhoneSignInScreen(mode: PhoneAuthMode.link),
  );

  @override
  ConsumerState<PhoneSignInScreen> createState() => _PhoneSignInScreenState();
}

class _PhoneSignInScreenState extends ConsumerState<PhoneSignInScreen> {
  late final PhoneAuthGateway _gateway;
  late final AuthService _auth;
  late final PhoneNumberService _phones;

  PhoneCountry _country = PhoneCountry.india;
  final _number = TextEditingController();
  final _code = TextEditingController();
  String? _numberError;

  PhoneCodeTicket? _ticket;
  bool _busy = false;
  String? _error;
  bool _codeError = false;

  Timer? _resendTimer;
  int _resendIn = 0;

  bool get _linking => widget.mode == PhoneAuthMode.link;

  @override
  void initState() {
    super.initState();
    _gateway = ref.read(phoneAuthGatewayProvider);
    _auth = ref.read(authServiceProvider);
    _phones = ref.read(phoneNumberServiceProvider);
  }

  @override
  void dispose() {
    _resendTimer?.cancel();
    _number.dispose();
    _code.dispose();
    super.dispose();
  }

  void _startResendTimer() {
    _resendTimer?.cancel();
    setState(() => _resendIn = PhoneSignInScreen.resendAfter);
    _resendTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return timer.cancel();
      setState(() => _resendIn = _resendIn > 0 ? _resendIn - 1 : 0);
      if (_resendIn == 0) timer.cancel();
    });
  }

  Future<void> _sendCode({bool resend = false}) async {
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
      _codeError = false;
    });
    try {
      final ticket = await _gateway.sendCode(
        e164,
        mode: widget.mode,
        resend: resend ? _ticket : null,
        onAutoVerified: (smsCode) {
          if (!mounted) return;
          if (smsCode != null) _code.text = smsCode;
          unawaited(_finish(e164));
        },
      );
      if (!mounted) return;
      if (ticket.autoVerified) {
        await _finish(e164);
        return;
      }
      setState(() {
        _ticket = ticket;
        _code.clear();
      });
      _startResendTimer();
    } on PhoneAuthException catch (e) {
      if (!mounted) return;
      setState(() {
        if (e.error == PhoneAuthError.invalidNumber && _ticket == null) {
          _numberError = e.message;
        } else {
          _error = e.message;
        }
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _confirm() async {
    final ticket = _ticket;
    final code = _code.text;
    if (ticket == null || _busy) return;
    if (code.length != OtpCodeField.length) {
      setState(() {
        _error = 'Enter the 6-digit code from the SMS.';
        _codeError = true;
      });
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
      _codeError = false;
    });
    try {
      await _gateway.confirmCode(ticket, code, mode: widget.mode);
      await _finish(ticket.phoneNumber);
    } on PhoneAuthException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _codeError = e.error == PhoneAuthError.wrongCode;
        if (_codeError) _code.clear();
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  bool _finished = false;

  /// Saves the verified number on the profile and in the index.
  Future<void> _finish(String e164) async {
    if (_finished) return;
    _finished = true;
    if (mounted) setState(() => _busy = true);
    try {
      // A first sign-in by number has no profile yet.
      final uid = _linking ? _auth.uid : await _auth.ensureProfile();
      if (uid == null) throw StateError('Not signed in');
      await _phones.saveVerifiedPhone(uid: uid, e164: e164);
      if (!mounted) return;
      if (_linking) {
        Navigator.of(context).pop(true);
      } else {
        // The auth gate replaces this screen once signed in.
        setState(() => _busy = false);
      }
    } catch (e) {
      _finished = false;
      debugPrint('Saving the verified number failed: $e');
      // Signed in either way; the auth gate moves on. Adding a number
      // explains and lets them try again.
      if (_linking && mounted) {
        setState(() {
          _busy = false;
          _error =
              'Your number is verified, but we couldn\'t save it. '
              'Check your connection and try again.';
        });
      }
    }
  }

  void _back() {
    if (_busy) return;
    if (_ticket != null) {
      _resendTimer?.cancel();
      setState(() {
        _ticket = null;
        _error = null;
        _codeError = false;
        _resendIn = 0;
      });
      return;
    }
    final onBack = widget.onBack;
    if (onBack != null) {
      onBack();
    } else {
      Navigator.of(context).maybePop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final dark = theme.brightness == Brightness.dark;
    const preset = GradientPreset.lavender;
    final ticket = _ticket;
    final codeStep = ticket != null;

    final title = codeStep
        ? 'Enter the code'
        : _linking
        ? 'Add your mobile number'
        : 'Your mobile number';
    final subtitle = codeStep
        ? 'We sent a 6-digit code to ${PhoneNumbers.format(ticket.phoneNumber)}.'
        : _linking
        ? 'So your partner can find you by number. We\'ll text you a code '
              'to check it\'s yours.'
        : 'We\'ll text you a 6-digit code to sign in.';

    return PopScope(
      canPop: !codeStep && widget.onBack == null && !_busy,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _back();
      },
      child: RomanceBackdrop(
        preset: GradientPreset.ocean,
        hearts: true,
        heartCount: 8,
        child: Scaffold(
          backgroundColor: Colors.transparent,
          appBar: romanceAppBar(
            leading: BackButton(onPressed: _busy ? null : _back),
          ),
          body: SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 420),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Center(
                        child: GlowBadge(
                          preset: preset,
                          icon: codeStep
                              ? Icons.sms_outlined
                              : Icons.phone_iphone_rounded,
                          size: 72,
                        ),
                      ),
                      const SizedBox(height: 18),
                      Text(
                        title,
                        textAlign: TextAlign.center,
                        style: romanceSerif(theme.textTheme.headlineMedium)
                            .copyWith(
                              fontWeight: FontWeight.w700,
                              fontStyle: FontStyle.italic,
                              color: dark
                                  ? scheme.onSurface
                                  : const Color(0xFF3B1424),
                            ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        subtitle,
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: scheme.onSurfaceVariant,
                          height: 1.4,
                        ),
                      ),
                      const SizedBox(height: 22),
                      FrostedForm(
                        child: codeStep
                            ? _codeForm(context, preset)
                            : _numberForm(context, preset),
                      ),
                      if (!codeStep) ...[
                        const SizedBox(height: 14),
                        Text(
                          'Standard SMS rates may apply. Your number is never '
                          'shown to anyone but your partner.',
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _numberForm(BuildContext context, GradientPreset preset) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PhoneNumberField(
          country: _country,
          controller: _number,
          enabled: !_busy,
          autofocus: true,
          errorText: _numberError,
          onCountryChanged: (c) => setState(() {
            _country = c;
            _numberError = null;
          }),
          onChanged: (_) {
            if (_numberError != null) setState(() => _numberError = null);
          },
          onSubmitted: _sendCode,
        ),
        PairingErrorText(error: _error),
        const SizedBox(height: 20),
        FilledButton(
          onPressed: _busy ? null : _sendCode,
          style: pillButtonStyle(context, preset: preset),
          child: BusyButtonLabel(busy: _busy, label: 'Send code'),
        ),
      ],
    );
  }

  Widget _codeForm(BuildContext context, GradientPreset preset) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final link = TextButton.styleFrom(
      foregroundColor: dark ? theme.colorScheme.primary : preset.ink,
      textStyle: theme.textTheme.labelLarge?.copyWith(
        fontWeight: FontWeight.w700,
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        OtpCodeField(
          controller: _code,
          enabled: !_busy,
          hasError: _codeError,
          preset: preset,
          onCompleted: (_) => _confirm(),
        ),
        PairingErrorText(error: _error),
        const SizedBox(height: 20),
        FilledButton(
          onPressed: _busy ? null : _confirm,
          style: pillButtonStyle(context, preset: preset),
          child: BusyButtonLabel(
            busy: _busy,
            label: _linking ? 'Verify and add' : 'Verify',
          ),
        ),
        const SizedBox(height: 6),
        // Wraps with large text rather than overflowing.
        Wrap(
          alignment: WrapAlignment.center,
          children: [
            TextButton(
              onPressed: _busy || _resendIn > 0
                  ? null
                  : () => _sendCode(resend: true),
              style: link,
              child: Text(
                _resendIn > 0 ? 'Resend code in ${_resendIn}s' : 'Resend code',
              ),
            ),
            TextButton(
              onPressed: _busy ? null : _back,
              style: link,
              child: const Text('Change number'),
            ),
          ],
        ),
      ],
    );
  }
}
