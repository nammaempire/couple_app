import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:couple_app/features/security/models/device_check.dart';
import 'package:couple_app/features/security/providers/security_providers.dart';
import 'package:couple_app/features/security/widgets/device_check_dialog.dart';

/// Wraps the signed-in app (the shell): when the partner signs in on a new
/// phone and asks this user to vouch for it, shows [DeviceCheckDialog]
/// once per check. A check put off with "Decide later" stays in
/// [DeviceCheckBanner].
///
/// Only mount it where the user belongs to a couple.
class DeviceCheckListener extends ConsumerStatefulWidget {
  const DeviceCheckListener({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<DeviceCheckListener> createState() =>
      _DeviceCheckListenerState();
}

class _DeviceCheckListenerState extends ConsumerState<DeviceCheckListener> {
  final _asked = <String>{};
  bool _showing = false;

  @override
  void initState() {
    super.initState();
    ref.listenManual(
      partnerDeviceChecksProvider,
      (_, next) => _maybeAsk(next.value ?? const []),
      fireImmediately: true,
    );
  }

  Future<void> _maybeAsk(List<DeviceCheck> checks) async {
    if (_showing) return;
    final check = checks.where((c) => !_asked.contains(c.id)).firstOrNull;
    if (check == null) return;
    _asked.add(check.id);
    _showing = true;
    // After this frame, so the dialog has a navigator to open on.
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted) return;
    try {
      await showDeviceCheckDialog(context, check);
    } finally {
      _showing = false;
    }
    if (mounted) {
      _maybeAsk(ref.read(partnerDeviceChecksProvider).value ?? const []);
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
