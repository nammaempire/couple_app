import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:couple_app/core/widgets/motion_policy.dart';
import 'package:couple_app/features/vault/widgets/vault_look.dart';

/// Six dots and a number pad (no system keyboard) for vault codes.
///
/// When six digits are in, [onSubmit] runs; if it returns false the dots
/// shake and clear. Either way the entry starts over.
class VaultCodeEntry extends StatefulWidget {
  const VaultCodeEntry({
    super.key,
    required this.onSubmit,
    this.enabled = true,
    this.leadingKey,
    this.length = 6,
  });

  final Future<bool> Function(String code) onSubmit;
  final bool enabled;

  /// Shown in the pad's bottom-left corner (the fingerprint button).
  final Widget? leadingKey;
  final int length;

  @override
  State<VaultCodeEntry> createState() => VaultCodeEntryState();
}

class VaultCodeEntryState extends State<VaultCodeEntry>
    with SingleTickerProviderStateMixin {
  late final AnimationController _shake = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 420),
  );
  String _code = '';
  bool _checking = false;

  @override
  void dispose() {
    _shake.dispose();
    super.dispose();
  }

  bool get _accepting => widget.enabled && !_checking;

  void _digit(String d) {
    if (!_accepting || _code.length >= widget.length) return;
    HapticFeedback.selectionClick();
    setState(() => _code += d);
    if (_code.length == widget.length) _submit();
  }

  void _backspace() {
    if (!_accepting || _code.isEmpty) return;
    setState(() => _code = _code.substring(0, _code.length - 1));
  }

  Future<void> _submit() async {
    final code = _code;
    setState(() => _checking = true);
    final ok = await widget.onSubmit(code);
    if (!mounted) return;
    setState(() {
      _checking = false;
      _code = '';
    });
    if (!ok) shake();
  }

  /// Shakes the dots, as after a wrong code.
  void shake() {
    HapticFeedback.heavyImpact();
    if (MotionPolicy.enabled(context)) _shake.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        AnimatedBuilder(
          animation: _shake,
          builder: (context, child) {
            final t = _shake.value;
            final dx = math.sin(t * math.pi * 6) * 12 * (1 - t);
            return Transform.translate(offset: Offset(dx, 0), child: child);
          },
          child: VaultCodeDots(
            length: widget.length,
            filled: _code.length,
            busy: _checking,
          ),
        ),
        const SizedBox(height: 28),
        VaultNumberPad(
          enabled: _accepting,
          onDigit: _digit,
          onBackspace: _backspace,
          leadingKey: widget.leadingKey,
        ),
      ],
    );
  }
}

/// [length] dots, the first [filled] of them lit.
class VaultCodeDots extends StatelessWidget {
  const VaultCodeDots({
    super.key,
    required this.length,
    required this.filled,
    this.busy = false,
  });

  final int length;
  final int filled;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '$filled of $length digits entered',
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < length; i++)
            AnimatedContainer(
              duration: const Duration(milliseconds: 140),
              margin: const EdgeInsets.symmetric(horizontal: 9),
              width: 16,
              height: 16,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: i < filled
                    ? (busy ? vaultGold.withValues(alpha: .6) : vaultGold)
                    : Colors.transparent,
                border: Border.all(
                  color: i < filled ? vaultGold : Colors.white54,
                  width: 1.6,
                ),
                boxShadow: [
                  if (i < filled)
                    BoxShadow(
                      color: vaultGold.withValues(alpha: .45),
                      blurRadius: 10,
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// A 3 × 4 number pad of round glass keys.
class VaultNumberPad extends StatelessWidget {
  const VaultNumberPad({
    super.key,
    required this.onDigit,
    required this.onBackspace,
    this.enabled = true,
    this.leadingKey,
  });

  final ValueChanged<String> onDigit;
  final VoidCallback onBackspace;
  final bool enabled;
  final Widget? leadingKey;

  @override
  Widget build(BuildContext context) {
    Widget row(List<Widget> keys) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          for (var i = 0; i < keys.length; i++) ...[
            if (i > 0) const SizedBox(width: 26),
            keys[i],
          ],
        ],
      ),
    );

    Widget digit(String d) => _PadKey(
      label: d,
      onTap: enabled ? () => onDigit(d) : null,
      child: Text(
        d,
        style: const TextStyle(
          fontSize: 28,
          fontWeight: FontWeight.w400,
          color: Colors.white,
        ),
      ),
    );

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        row([digit('1'), digit('2'), digit('3')]),
        row([digit('4'), digit('5'), digit('6')]),
        row([digit('7'), digit('8'), digit('9')]),
        row([
          SizedBox.square(dimension: _PadKey.size, child: leadingKey),
          digit('0'),
          _PadKey(
            label: 'Delete',
            plain: true,
            onTap: enabled ? onBackspace : null,
            child: const Icon(
              Icons.backspace_outlined,
              color: Colors.white70,
              size: 24,
            ),
          ),
        ]),
      ],
    );
  }
}

class _PadKey extends StatelessWidget {
  const _PadKey({
    required this.label,
    required this.child,
    this.onTap,
    this.plain = false,
  });

  static const size = 74.0;

  final String label;
  final Widget child;
  final VoidCallback? onTap;

  /// No glass circle (for the delete key).
  final bool plain;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      child: SizedBox.square(
        dimension: size,
        child: Material(
          type: MaterialType.circle,
          color: plain
              ? Colors.transparent
              : Colors.white.withValues(alpha: .08),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onTap,
            child: DecoratedBox(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: plain
                    ? null
                    : Border.all(color: Colors.white.withValues(alpha: .16)),
              ),
              child: Center(child: child),
            ),
          ),
        ),
      ),
    );
  }
}

/// A round key for the pad's corner: the fingerprint / face button.
class VaultPadIconKey extends StatelessWidget {
  const VaultPadIconKey({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => _PadKey(
    label: label,
    plain: true,
    onTap: onTap,
    child: Icon(icon, color: vaultGold, size: 30),
  );
}
