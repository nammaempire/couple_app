import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';

import 'package:couple_app/core/utils/snackbar.dart';
import 'package:couple_app/features/auth/data/auth_service.dart';
import 'package:couple_app/features/auth/models/app_user.dart';
import 'package:couple_app/features/auth/providers/auth_providers.dart';
import 'package:couple_app/features/couple/data/couple_service.dart';
import 'package:couple_app/features/couple/models/couple.dart';
import 'package:couple_app/features/couple/models/invite.dart';
import 'package:couple_app/features/couple/providers/couple_providers.dart';
import 'package:couple_app/features/onboarding/widgets/onboarding_progress.dart';

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
    await SharePlus.instance.share(
      ShareParams(
        text: _shareText,
        subject: 'Join me on Us',
        sharePositionOrigin: box == null
            ? null
            : box.localToGlobal(Offset.zero) & box.size,
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

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
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
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const OnboardingProgress(step: OnboardingStep.invite),
                  const SizedBox(height: 24),
                  Text(
                    widget.couple.coupleName == null
                        ? 'Your space is ready'
                        : '“${widget.couple.coupleName}” is ready',
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Send this invite to your partner. It works once, and '
                    'only for them.',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 24),

                  Container(
                    padding: const EdgeInsets.fromLTRB(20, 24, 20, 16),
                    decoration: BoxDecoration(
                      color: scheme.primaryContainer,
                      borderRadius: BorderRadius.circular(28),
                    ),
                    child: Column(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: QrImageView(
                            data: InviteCode.qrPayload(_code),
                            size: 180,
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
                            color: scheme.onPrimaryContainer.withValues(
                              alpha: .75,
                            ),
                          ),
                        ),
                        const SizedBox(height: 4),
                        SelectableText(
                          _code,
                          style: theme.textTheme.displaySmall?.copyWith(
                            letterSpacing: 10,
                            fontWeight: FontWeight.bold,
                            color: scheme.onPrimaryContainer,
                          ),
                        ),
                        TextButton.icon(
                          onPressed: _copy,
                          icon: const Icon(Icons.copy, size: 18),
                          label: const Text('Copy code'),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: _busy ? null : _share,
                    icon: const Icon(Icons.ios_share),
                    label: const Text('Share invite'),
                  ),
                  const SizedBox(height: 24),

                  const _WaitingIndicator(),
                  const SizedBox(height: 24),

                  Text(
                    'On their phone, your partner signs up, taps “I have an '
                    'invite”, then scans this QR code or types the code.',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextButton(
                    onPressed: _busy ? null : _useCodeInstead,
                    child: const Text('My partner already sent me a code'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A gently pulsing heart with "waiting" copy.
class _WaitingIndicator extends StatefulWidget {
  const _WaitingIndicator();

  @override
  State<_WaitingIndicator> createState() => _WaitingIndicatorState();
}

class _WaitingIndicatorState extends State<_WaitingIndicator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        ScaleTransition(
          scale: Tween(
            begin: .85,
            end: 1.1,
          ).animate(CurvedAnimation(parent: _pulse, curve: Curves.easeInOut)),
          child: Icon(Icons.favorite, color: theme.colorScheme.primary),
        ),
        const SizedBox(width: 10),
        Text(
          'Waiting for your partner to join…',
          style: theme.textTheme.bodyMedium,
        ),
      ],
    );
  }
}
