import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';

import 'package:couple_app/core/utils/snackbar.dart';
import 'package:couple_app/core/widgets/animated_gradient_card.dart';
import 'package:couple_app/core/widgets/entrance_animation.dart';
import 'package:couple_app/core/widgets/floating_hearts.dart';
import 'package:couple_app/core/widgets/glass.dart';
import 'package:couple_app/core/widgets/gradient_preset.dart';
import 'package:couple_app/features/app_lock/app_lock_controller.dart';
import 'package:couple_app/features/auth/data/auth_service.dart';
import 'package:couple_app/features/auth/models/app_user.dart';
import 'package:couple_app/features/auth/providers/auth_providers.dart';
import 'package:couple_app/features/couple/data/couple_service.dart';
import 'package:couple_app/features/couple/models/couple.dart';
import 'package:couple_app/features/couple/models/invite.dart';
import 'package:couple_app/features/couple/providers/couple_providers.dart';
import 'package:couple_app/features/onboarding/widgets/onboarding_progress.dart';
import 'package:couple_app/features/onboarding/widgets/romance_kit.dart';

/// Onboarding step 3: share the invite and wait for the partner to accept.
///
/// [AuthGate] replaces this screen automatically once the couple has two
/// members, so there is no "done" button.
class InviteScreen extends ConsumerStatefulWidget {
  const InviteScreen({super.key, required this.me, required this.couple});

  final AppUser me;
  final Couple couple;

  @override
  ConsumerState<InviteScreen> createState() => _InviteScreenState();
}

class _InviteScreenState extends ConsumerState<InviteScreen> {
  late final AuthService _auth;
  late final CoupleService _couples;

  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _auth = ref.read(authServiceProvider);
    _couples = ref.read(coupleServiceProvider);
    // Couples created before the invites collection existed need one written
    // before the partner can join. Best effort; the screen works without it.
    _couples
        .ensureInvite(
          couple: widget.couple,
          uid: widget.me.uid,
          inviterName: widget.me.displayName,
          inviterPhotoUrl: widget.me.photoUrl,
        )
        .catchError((_) {});
  }

  String get _code => widget.couple.inviteCode;

  String get _shareText =>
      'Join me on Us 💞\n\n'
      'It\'s a private space just for the two of us. Install the app, tap '
      '"I have an invite" and enter our code: $_code';

  Future<void> _share() async {
    final box = context.findRenderObject() as RenderBox?;
    await ref
        .read(appLockControllerProvider.notifier)
        .suspendWhile(
          SharePlus.instance.share(
            ShareParams(
              text: _shareText,
              subject: 'Join me on Us',
              sharePositionOrigin: box == null
                  ? null
                  : box.localToGlobal(Offset.zero) & box.size,
            ),
          ),
        );
  }

  void _copy() {
    Clipboard.setData(ClipboardData(text: _code));
    context.showSnackMessage('Code copied');
  }

  Future<void> _useCodeInstead() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Join your partner instead?'),
        content: const Text(
          'This cancels the space you created and its invite code. You can '
          'then enter the code your partner sent you.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Keep my invite'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: pillButtonStyle(
              dialogContext,
              minimumSize: const Size(0, 44),
            ),
            child: const Text('Cancel it'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _busy = true);
    try {
      await _couples.cancelWaitingCouple(
        uid: widget.me.uid,
        couple: widget.couple,
      );
      // AuthGate returns to the pairing screen once `coupleId` is cleared.
    } catch (_) {
      if (!mounted) return;
      setState(() => _busy = false);
      context.showSnackMessage('Could not cancel. Try again.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final b = theme.brightness;
    final dark = b == Brightness.dark;
    const preset = GradientPreset.festive;

    return RomanceBackdrop(
      preset: GradientPreset.blush,
      strength: .5,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: romanceAppBar(
          title: const Text('Invite your partner'),
          actions: [
            TextButton(
              onPressed: _busy ? null : _auth.signOut,
              child: const Text('Sign out'),
            ),
          ],
        ),
        body: SafeArea(
          child: Align(
            alignment: Alignment.topCenter,
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 440),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: staggered([
                    const OnboardingProgress(step: OnboardingStep.invite),
                    const SizedBox(height: 18),
                    AnimatedGradientCard(
                      preset: preset,
                      radius: 30,
                      padding: EdgeInsets.zero,
                      child: Stack(
                        fit: StackFit.passthrough,
                        children: [
                          Positioned.fill(
                            child: FloatingHearts(
                              count: 12,
                              style: ParticleStyle.confetti,
                              opacity: dark ? .3 : .45,
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.fromLTRB(20, 24, 20, 12),
                            child: Column(
                              children: [
                                Text(
                                  widget.couple.coupleName == null
                                      ? 'Your space is ready'
                                      : '“${widget.couple.coupleName}” is ready',
                                  textAlign: TextAlign.center,
                                  style:
                                      romanceSerif(
                                        theme.textTheme.headlineSmall,
                                      ).copyWith(
                                        fontWeight: FontWeight.w700,
                                        fontStyle: FontStyle.italic,
                                        color: preset.foreground(b),
                                      ),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  'Send this invite to your partner. It works '
                                  'once, and only for them.',
                                  textAlign: TextAlign.center,
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    color: preset.foregroundMuted(b),
                                    height: 1.4,
                                  ),
                                ),
                                const SizedBox(height: 20),
                                Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(24),
                                    boxShadow: [
                                      BoxShadow(
                                        color: preset
                                            .accent(b)
                                            .withValues(alpha: .25),
                                        blurRadius: 20,
                                        offset: const Offset(0, 6),
                                      ),
                                    ],
                                  ),
                                  child: QrImageView(
                                    data: InviteCode.qrPayload(_code),
                                    size: 176,
                                    backgroundColor: Colors.white,
                                    eyeStyle: const QrEyeStyle(
                                      eyeShape: QrEyeShape.circle,
                                      color: Color(0xFF3B2229),
                                    ),
                                    dataModuleStyle: const QrDataModuleStyle(
                                      dataModuleShape: QrDataModuleShape.circle,
                                      color: Color(0xFF3B2229),
                                    ),
                                    semanticsLabel: 'Invite QR code',
                                  ),
                                ),
                                const SizedBox(height: 18),
                                Text(
                                  'or enter this code',
                                  style: theme.textTheme.labelMedium?.copyWith(
                                    color: preset.foregroundMuted(b),
                                  ),
                                ),
                                const SizedBox(height: 4),
                                FittedBox(
                                  fit: BoxFit.scaleDown,
                                  child: SelectableText(
                                    _code,
                                    style: theme.textTheme.displaySmall
                                        ?.copyWith(
                                          letterSpacing: 10,
                                          fontWeight: FontWeight.bold,
                                          color: preset.foreground(b),
                                        ),
                                  ),
                                ),
                                TextButton.icon(
                                  onPressed: _copy,
                                  style: TextButton.styleFrom(
                                    foregroundColor: dark
                                        ? preset.accent(b)
                                        : preset.ink,
                                  ),
                                  icon: const Icon(Icons.copy, size: 18),
                                  label: const Text('Copy code'),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 18),
                    FilledButton.icon(
                      onPressed: _busy ? null : _share,
                      style: pillButtonStyle(context),
                      icon: const Icon(Icons.ios_share),
                      label: const Text('Share invite'),
                    ),
                    const SizedBox(height: 20),

                    const Center(child: _WaitingIndicator()),
                    const SizedBox(height: 20),

                    Text(
                      'On their phone, your partner signs up, taps “I have an '
                      'invite”, then scans this QR code or types the code.',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextButton(
                      onPressed: _busy ? null : _useCodeInstead,
                      child: const Text('My partner already sent me a code'),
                    ),
                  ]),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A gently pulsing heart with "waiting" copy, on a frosted pill.
class _WaitingIndicator extends StatelessWidget {
  const _WaitingIndicator();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    return GlassPanel(
      dark: dark,
      radius: 30,
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          RepaintBoundary(
            child: Pulse(
              duration: const Duration(milliseconds: 1100),
              child: Icon(
                Icons.favorite_rounded,
                color: theme.colorScheme.primary,
              ),
              builder: (context, v, child) =>
                  Transform.scale(scale: .88 + .22 * v, child: child),
            ),
          ),
          const SizedBox(width: 10),
          Flexible(
            child: Text(
              'Waiting for your partner to join…',
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
