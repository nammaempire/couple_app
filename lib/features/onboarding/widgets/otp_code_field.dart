import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:couple_app/core/widgets/gradient_preset.dart';

/// Six boxes for an SMS code.
///
/// One real (invisible) text field sits under the boxes, so typing,
/// pasting and the keyboard's one-time-code suggestion all work, and
/// Android's SMS autofill can fill it in one go. [onCompleted] runs when
/// the sixth digit lands.
class OtpCodeField extends StatefulWidget {
  const OtpCodeField({
    super.key,
    required this.controller,
    this.onCompleted,
    this.enabled = true,
    this.hasError = false,
    this.preset = GradientPreset.lavender,
  });

  static const length = 6;

  final TextEditingController controller;
  final ValueChanged<String>? onCompleted;
  final bool enabled;
  final bool hasError;
  final GradientPreset preset;

  @override
  State<OtpCodeField> createState() => _OtpCodeFieldState();
}

class _OtpCodeFieldState extends State<OtpCodeField> {
  final _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_changed);
    _focus.addListener(_changed);
  }

  @override
  void didUpdateWidget(covariant OtpCodeField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_changed);
      widget.controller.addListener(_changed);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_changed);
    _focus.dispose();
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final b = theme.brightness;
    final dark = b == Brightness.dark;
    final accent = dark ? widget.preset.accent(b) : widget.preset.ink;
    final code = widget.controller.text;
    final active = _focus.hasFocus ? code.length : -1;

    return Semantics(
      label: 'Six-digit code',
      textField: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.enabled ? _focus.requestFocus : null,
        child: Stack(
          alignment: Alignment.center,
          children: [
            // The real field: invisible, but it takes the keyboard and
            // the SMS autofill.
            Opacity(
              opacity: 0,
              child: AutofillGroup(
                child: TextField(
                  key: const Key('otp-field'),
                  controller: widget.controller,
                  focusNode: _focus,
                  enabled: widget.enabled,
                  autofocus: true,
                  keyboardType: TextInputType.number,
                  autofillHints: const [AutofillHints.oneTimeCode],
                  showCursor: false,
                  enableInteractiveSelection: false,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(OtpCodeField.length),
                  ],
                  onChanged: (value) {
                    if (value.length == OtpCodeField.length) {
                      widget.onCompleted?.call(value);
                    }
                  },
                ),
              ),
            ),
            IgnorePointer(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (var i = 0; i < OtpCodeField.length; i++) ...[
                    if (i == 3) const SizedBox(width: 10),
                    _Box(
                      digit: i < code.length ? code[i] : '',
                      active: i == active,
                      error: widget.hasError,
                      accent: accent,
                    ),
                    if (i < OtpCodeField.length - 1 && i != 2)
                      const SizedBox(width: 8),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Box extends StatelessWidget {
  const _Box({
    required this.digit,
    required this.active,
    required this.error,
    required this.accent,
  });

  final String digit;
  final bool active;
  final bool error;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final border = error
        ? theme.colorScheme.error
        : active
        ? accent
        : (dark
              ? Colors.white.withValues(alpha: .22)
              : accent.withValues(alpha: .22));
    return AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      width: 42,
      height: 54,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: dark
            ? Colors.black.withValues(alpha: .28)
            : Colors.white.withValues(alpha: .9),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: border, width: active || error ? 2 : 1.2),
        boxShadow: active
            ? [
                BoxShadow(
                  color: accent.withValues(alpha: .25),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ]
            : null,
      ),
      child: Text(
        digit,
        style: theme.textTheme.headlineSmall?.copyWith(
          fontWeight: FontWeight.w800,
          color: theme.colorScheme.onSurface,
        ),
      ),
    );
  }
}
