import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:couple_app/core/widgets/animated_gradient_card.dart';
import 'package:couple_app/core/widgets/entrance_animation.dart';
import 'package:couple_app/core/widgets/floating_hearts.dart';
import 'package:couple_app/core/widgets/gradient_preset.dart';
import 'package:couple_app/core/widgets/motion_policy.dart';
import 'package:couple_app/features/auth/providers/auth_providers.dart';
import 'package:couple_app/features/books/screens/book_builder_screen.dart';
import 'package:couple_app/features/couple/providers/couple_providers.dart';
import 'package:couple_app/features/onboarding/widgets/romance_kit.dart';
import 'package:couple_app/features/premium/models/gift.dart';
import 'package:couple_app/features/premium/providers/premium_providers.dart';

/// The surprise: a wrapped box that opens on tap, with confetti and
/// hearts, then "Asha gifted you 3 months of Premium 💝", their message,
/// and for a book "Make our book".
///
/// Opening it marks the gift opened (once), so it is only a surprise once.
class GiftRevealScreen extends ConsumerStatefulWidget {
  const GiftRevealScreen({super.key, required this.gift});

  final Gift gift;

  static Route<void> route(Gift gift) => MaterialPageRoute<void>(
    fullscreenDialog: true,
    builder: (_) => GiftRevealScreen(gift: gift),
  );

  @override
  ConsumerState<GiftRevealScreen> createState() => _GiftRevealScreenState();
}

class _GiftRevealScreenState extends ConsumerState<GiftRevealScreen> {
  late bool _open = widget.gift.isOpened;

  Future<void> _unwrap() async {
    if (_open) return;
    HapticFeedback.mediumImpact();
    setState(() => _open = true);
    try {
      await ref
          .read(giftServiceProvider)
          .markOpened(
            coupleId: ref.read(currentCoupleIdProvider),
            gift: widget.gift,
          );
    } catch (_) {
      // It still opened here; it is marked next time.
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final from = ref.watch(partnerNameProvider);
    final motion = MotionPolicy.enabled(context);
    final gift = widget.gift;

    return RomanceBackdrop(
      preset: GradientPreset.festive,
      hearts: _open,
      heartCount: 16,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: romanceAppBar(leading: const CloseButton()),
        body: Stack(
          children: [
            if (_open)
              const Positioned.fill(
                child: IgnorePointer(
                  child: FloatingHearts(
                    count: 26,
                    style: ParticleStyle.confetti,
                    opacity: .8,
                    duration: Duration(seconds: 9),
                  ),
                ),
              ),
            SafeArea(
              child: Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
                  child: AnimatedSwitcher(
                    duration: Duration(milliseconds: motion ? 420 : 0),
                    transitionBuilder: (child, animation) => ScaleTransition(
                      scale: Tween(begin: .8, end: 1.0).animate(
                        CurvedAnimation(
                          parent: animation,
                          curve: Curves.easeOutBack,
                        ),
                      ),
                      child: FadeTransition(opacity: animation, child: child),
                    ),
                    child: _open
                        ? _Revealed(
                            key: const ValueKey('open'),
                            gift: gift,
                            from: from,
                          )
                        : Column(
                            key: const ValueKey('closed'),
                            children: [
                              Text(
                                'A gift from $from',
                                style:
                                    romanceSerif(
                                      theme.textTheme.headlineSmall,
                                    ).copyWith(
                                      fontWeight: FontWeight.w700,
                                      fontStyle: FontStyle.italic,
                                    ),
                              ),
                              const SizedBox(height: 28),
                              Semantics(
                                button: true,
                                label: 'Open your gift',
                                child: GestureDetector(
                                  key: const Key('gift-box'),
                                  onTap: _unwrap,
                                  child: const Bobbing(
                                    amplitude: 6,
                                    child: _GiftBox(),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 28),
                              Text(
                                'Tap to open',
                                style: theme.textTheme.titleMedium?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A wrapped present: a gradient box, a ribbon both ways, and a bow.
class _GiftBox extends StatelessWidget {
  const _GiftBox();

  @override
  Widget build(BuildContext context) {
    const ribbon = Color(0xFFFFD27A);
    return SizedBox(
      width: 200,
      height: 210,
      child: Stack(
        alignment: Alignment.bottomCenter,
        children: [
          SizedBox(
            width: 190,
            height: 170,
            child: AnimatedGradientCard(
              preset: GradientPreset.festive,
              // Richer than the page, so the present stands out.
              colors: const [
                Color(0xFFE5487C),
                Color(0xFFB03A8C),
                Color(0xFF7A4FD0),
              ],
              radius: 28,
              padding: EdgeInsets.zero,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Container(width: 30, color: ribbon),
                  Container(height: 30, color: ribbon),
                ],
              ),
            ),
          ),
          const Positioned(
            top: 0,
            child: Text('🎀', style: TextStyle(fontSize: 64)),
          ),
        ],
      ),
    );
  }
}

class _Revealed extends StatelessWidget {
  const _Revealed({super.key, required this.gift, required this.from});

  final Gift gift;
  final String from;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final b = theme.brightness;
    const preset = GradientPreset.blush;
    final book = gift.kind == GiftKind.book;
    return Column(
      children: staggered([
        GlowBadge(
          preset: book ? GradientPreset.lavender : GradientPreset.gold,
          icon: book
              ? Icons.auto_stories_rounded
              : Icons.workspace_premium_rounded,
          size: 96,
        ),
        const SizedBox(height: 22),
        Text(
          '$from gifted you ${gift.what} 💝',
          key: const Key('gift-headline'),
          textAlign: TextAlign.center,
          style: romanceSerif(theme.textTheme.headlineSmall).copyWith(
            fontWeight: FontWeight.w700,
            fontStyle: FontStyle.italic,
            height: 1.25,
          ),
        ),
        const SizedBox(height: 18),
        if (gift.message.trim().isNotEmpty)
          AnimatedGradientCard(
            preset: preset,
            radius: 24,
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
            child: Column(
              children: [
                Text(
                  '“${gift.message.trim()}”',
                  textAlign: TextAlign.center,
                  style: romanceSerif(theme.textTheme.titleMedium).copyWith(
                    fontStyle: FontStyle.italic,
                    color: preset.foreground(b),
                    height: 1.45,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  '— $from',
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: preset.foregroundMuted(b),
                  ),
                ),
              ],
            ),
          ),
        const SizedBox(height: 22),
        if (book)
          FilledButton.icon(
            key: const Key('gift-make-book'),
            onPressed: () => Navigator.of(
              context,
            ).pushReplacement(BookBuilderScreen.route()),
            style: pillButtonStyle(context, preset: GradientPreset.lavender),
            icon: const Icon(Icons.auto_stories_outlined),
            label: const Text('Make our book'),
          )
        else
          Text(
            'Premium is on for both of you.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
      ]),
    );
  }
}
