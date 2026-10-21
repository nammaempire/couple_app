import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:couple_app/features/auth/providers/auth_providers.dart';
import 'package:couple_app/features/security/providers/security_providers.dart';
import 'package:couple_app/features/security/screens/confirm_new_phone_screen.dart';

/// Sits in the auth gate right after sign-in: builds [child] (profile,
/// pairing and the app) only once this phone has passed sign-in
/// protection, and "Confirm it's you" until then. Nothing below it, so no
/// couple data, is read or listened to before that.
class NewPhoneGate extends ConsumerWidget {
  const NewPhoneGate({
    super.key,
    required this.uid,
    required this.child,
    required this.loading,
  });

  final String uid;

  /// The signed-in part of the app.
  final Widget child;

  /// Shown while deciding.
  final Widget loading;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final trust = ref.watch(deviceTrustProvider(uid));
    if (trust.isLoading && !trust.hasValue) return loading;
    if (trust.hasError && !trust.hasValue) {
      return NewPhoneCheckErrorScreen(
        onRetry: () => ref.invalidate(deviceTrustProvider(uid)),
        onSignOut: () => ref.read(authServiceProvider).signOut(),
      );
    }
    final value = trust.requireValue;
    if (value.trusted) return child;
    return ConfirmNewPhoneScreen(uid: uid, trust: value);
  }
}
