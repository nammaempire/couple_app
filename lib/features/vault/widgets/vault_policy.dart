import 'package:flutter/material.dart';

import 'package:couple_app/features/vault/models/vault_item.dart';
import 'package:couple_app/features/vault/widgets/vault_look.dart';

/// A small round badge for a view-once (👁) or 24-hour (⏳) item.
class VaultPolicyBadge extends StatelessWidget {
  const VaultPolicyBadge({super.key, required this.policy, this.size = 26});

  final VaultPolicy policy;
  final double size;

  @override
  Widget build(BuildContext context) {
    final badge = policy.badge;
    if (badge == null) return const SizedBox.shrink();
    return Semantics(
      label: policy.label,
      child: Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: const Color(0xCC15173A),
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white24),
        ),
        child: Text(badge, style: TextStyle(fontSize: size * .5)),
      ),
    );
  }
}

/// How long is left on a 24-hour item, e.g. "23h left".
String vaultTimeLeft(DateTime expiresAt, DateTime now) {
  final left = expiresAt.difference(now);
  if (left.inHours >= 1) return '${left.inHours}h left';
  if (left.inMinutes >= 1) return '${left.inMinutes}m left';
  return 'Ending';
}

/// Asks how long an item should last. Returns null if dismissed.
Future<VaultPolicy?> showVaultPolicyPicker(
  BuildContext context, {
  required VaultPolicy current,
  String title = 'How long should it last?',
  Widget? preview,
  String? confirmLabel,
}) {
  return showVaultSheet<VaultPolicy>(
    context,
    (context) => _PolicyPicker(
      current: current,
      title: title,
      preview: preview,
      confirmLabel: confirmLabel,
    ),
    scrollable: true,
  );
}

class _PolicyPicker extends StatefulWidget {
  const _PolicyPicker({
    required this.current,
    required this.title,
    this.preview,
    this.confirmLabel,
  });

  final VaultPolicy current;
  final String title;
  final Widget? preview;
  final String? confirmLabel;

  @override
  State<_PolicyPicker> createState() => _PolicyPickerState();
}

class _PolicyPickerState extends State<_PolicyPicker> {
  late VaultPolicy _policy = widget.current;

  @override
  Widget build(BuildContext context) {
    final confirm = widget.confirmLabel;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (widget.preview != null) ...[
              Center(child: widget.preview!),
              const SizedBox(height: 14),
            ],
            VaultTitle(widget.title, size: 22),
            const SizedBox(height: 12),
            for (final policy in VaultPolicy.values)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _PolicyOption(
                  policy: policy,
                  selected: policy == _policy,
                  onTap: () {
                    if (confirm == null) {
                      Navigator.of(context).pop(policy);
                    } else {
                      setState(() => _policy = policy);
                    }
                  },
                ),
              ),
            if (confirm != null) ...[
              const SizedBox(height: 8),
              FilledButton(
                style: vaultButtonStyle(context),
                onPressed: () => Navigator.of(context).pop(_policy),
                child: Text(confirm),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _PolicyOption extends StatelessWidget {
  const _PolicyOption({
    required this.policy,
    required this.selected,
    required this.onTap,
  });

  final VaultPolicy policy;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected
          ? vaultGold.withValues(alpha: .14)
          : Colors.white.withValues(alpha: .05),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: selected ? vaultGold : Colors.white24),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              SizedBox(
                width: 30,
                child: Text(
                  policy.badge ?? '♾️',
                  style: const TextStyle(fontSize: 22),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      policy.label,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                      ),
                    ),
                    Text(
                      policy.description,
                      style: const TextStyle(color: vaultMuted, fontSize: 13),
                    ),
                  ],
                ),
              ),
              if (selected)
                const Icon(Icons.check_circle, color: vaultGold, size: 22),
            ],
          ),
        ),
      ),
    );
  }
}
