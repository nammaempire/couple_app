import 'package:flutter/material.dart';

/// First screen for signed-out users: the emotional promise, then sign-up.
class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({
    super.key,
    required this.onGetStarted,
    required this.onSignIn,
  });

  final VoidCallback onGetStarted;
  final VoidCallback onSignIn;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              scheme.primaryContainer.withValues(alpha: .65),
              theme.scaffoldBackgroundColor,
            ],
          ),
        ),
        child: SafeArea(
          // Scrolls on short screens; spacers spread content on tall ones.
          child: LayoutBuilder(
            builder: (context, viewport) => SingleChildScrollView(
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: viewport.maxHeight),
                child: IntrinsicHeight(
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 440),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(28, 24, 28, 24),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            const Spacer(flex: 2),
                            const _HeartsMark(),
                            const SizedBox(height: 28),
                            Text(
                              'Everything that belongs to us, in one private place.',
                              textAlign: TextAlign.center,
                              style: theme.textTheme.headlineSmall?.copyWith(
                                fontWeight: FontWeight.w700,
                                height: 1.25,
                              ),
                            ),
                            const SizedBox(height: 12),
                            Text(
                              'A space made for exactly two people — to talk, '
                              'remember and plan your life together.',
                              textAlign: TextAlign.center,
                              style: theme.textTheme.bodyLarge?.copyWith(
                                color: scheme.onSurfaceVariant,
                                height: 1.4,
                              ),
                            ),
                            const SizedBox(height: 32),
                            const _Promise(
                              icon: Icons.lock_outline,
                              title: 'Just the two of you',
                              body:
                                  'Only you and your partner can see what you share.',
                            ),
                            const _Promise(
                              icon: Icons.chat_bubble_outline,
                              title: 'Talk, call, send photos',
                              body:
                                  'A private chat with voice and video calls.',
                            ),
                            const _Promise(
                              icon: Icons.auto_awesome_outlined,
                              title: 'Stay close every day',
                              body:
                                  'Moods, a daily question and your days-together count.',
                            ),
                            const Spacer(flex: 3),
                            FilledButton(
                              onPressed: onGetStarted,
                              child: const Text('Get started'),
                            ),
                            const SizedBox(height: 8),
                            TextButton(
                              onPressed: onSignIn,
                              child: const Text('I already have an account'),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _HeartsMark extends StatelessWidget {
  const _HeartsMark();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      height: 88,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Transform.translate(
            offset: const Offset(-18, 4),
            child: Icon(
              Icons.favorite,
              size: 72,
              color: scheme.primary.withValues(alpha: .35),
            ),
          ),
          Transform.translate(
            offset: const Offset(18, -4),
            child: Icon(Icons.favorite, size: 72, color: scheme.primary),
          ),
        ],
      ),
    );
  }
}

class _Promise extends StatelessWidget {
  const _Promise({required this.icon, required this.title, required this.body});

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(9),
            decoration: BoxDecoration(
              color: theme.colorScheme.surface,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, size: 20, color: theme.colorScheme.primary),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  body,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
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
