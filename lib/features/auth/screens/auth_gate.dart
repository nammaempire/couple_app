import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:couple_app/features/auth/models/app_user.dart';
import 'package:couple_app/features/auth/providers/auth_providers.dart';
import 'package:couple_app/features/auth/screens/sign_in_screen.dart';
import 'package:couple_app/features/couple/providers/couple_providers.dart';
import 'package:couple_app/features/onboarding/screens/invite_screen.dart';
import 'package:couple_app/features/onboarding/screens/pairing_screen.dart';
import 'package:couple_app/features/onboarding/screens/profile_setup_screen.dart';
import 'package:couple_app/features/onboarding/screens/setup_checklist_screen.dart';
import 'package:couple_app/features/onboarding/screens/welcome_screen.dart';
import 'package:couple_app/features/shell/main_shell.dart';

/// Routes the user through onboarding and into the app, driven entirely by
/// auth, profile and couple state:
///
///   signed out           → welcome → sign in / sign up
///   profile incomplete   → about you
///   no couple            → create or join
///   couple of one        → invite (waiting for partner)
///   setup not finished   → setup checklist
///   otherwise            → main app
///
/// Each step writes to Firestore and the streams move the user on, so no
/// screen needs to navigate to the next one.
class AuthGate extends ConsumerWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authStateProvider);
    if (auth.isLoading && !auth.hasValue) return const _Splash();

    final user = auth.value;
    if (user == null) return const _SignedOutFlow();

    return _ProfileGate(key: ValueKey(user.uid), uid: user.uid);
  }
}

/// Profile setup and pairing, until the user belongs to a couple.
class _ProfileGate extends ConsumerWidget {
  const _ProfileGate({super.key, required this.uid});

  final String uid;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profileState = ref.watch(profileProvider(uid));
    if (profileState.isLoading && !profileState.hasValue) {
      return const _Splash();
    }

    final profile = profileState.value;
    if (profile == null || !profile.profileComplete) {
      return ProfileSetupScreen(uid: uid, profile: profile);
    }

    final coupleId = profile.coupleId;
    if (coupleId == null) return PairingScreen(uid: uid, me: profile);

    return _CoupleGate(key: ValueKey(coupleId), me: profile);
  }
}

/// Welcome screen, then the sign-in form, without pushing routes.
class _SignedOutFlow extends StatefulWidget {
  const _SignedOutFlow();

  @override
  State<_SignedOutFlow> createState() => _SignedOutFlowState();
}

class _SignedOutFlowState extends State<_SignedOutFlow> {
  /// null while on the welcome screen; otherwise which form to open.
  bool? _signUp;

  @override
  Widget build(BuildContext context) {
    final signUp = _signUp;

    return PopScope(
      canPop: signUp == null,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) setState(() => _signUp = null);
      },
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 250),
        child: signUp == null
            ? WelcomeScreen(
                key: const ValueKey('welcome'),
                onGetStarted: () => setState(() => _signUp = true),
                onSignIn: () => setState(() => _signUp = false),
              )
            : SignInScreen(
                key: const ValueKey('sign-in'),
                initialSignUp: signUp,
                onBack: () => setState(() => _signUp = null),
              ),
      ),
    );
  }
}

/// Decides between the invite screen, the setup checklist and the app once
/// the user belongs to a couple.
class _CoupleGate extends ConsumerWidget {
  const _CoupleGate({super.key, required this.me});

  final AppUser me;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final coupleState = ref.watch(coupleProvider);
    // Waiting for this couple's first snapshot (including right after
    // switching couples, when the previous couple's state is still around).
    if (coupleState.isLoading) return const _Splash();

    // A couple that was deleted, or one this user is no longer a member
    // of, is unreadable under the rules. Either way they need a new one.
    final couple = coupleState.value;
    final gone =
        coupleState.hasError ||
        (couple != null && !couple.memberIds.contains(me.uid));
    if (gone) {
      return PairingScreen(
        uid: me.uid,
        me: me,
        notice:
            'Your previous space is no longer available. Create a new '
            'one or join your partner.',
      );
    }

    if (couple == null) return const _Splash();
    if (!couple.isComplete) return InviteScreen(me: me, couple: couple);
    if (!me.setupComplete) return SetupChecklistScreen(me: me, couple: couple);
    return const MainShell();
  }
}

class _Splash extends StatelessWidget {
  const _Splash();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.favorite,
              size: 56,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(height: 24),
            const SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ],
        ),
      ),
    );
  }
}
