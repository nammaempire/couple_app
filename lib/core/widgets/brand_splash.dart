import 'package:flutter/material.dart';

import 'package:couple_app/core/widgets/motion_policy.dart';

/// The splash shown while the app starts (signing in, loading your
/// profile and couple). The icon, the "Us" wordmark, a tagline, three
/// breathing dots and "powered by RESET95" in the corner. Follows light and
/// dark mode, matching Android's native splash colours before it.
class BrandSplash extends StatelessWidget {
  const BrandSplash({super.key});

  static const lightColors = [
    Color(0xFFFFF7F9),
    Color(0xFFFDE3EC),
    Color(0xFFF4D4EF),
  ];
  static const darkColors = [
    Color(0xFF2E1D4F),
    Color(0xFF1A1230),
    Color(0xFF0F0A1E),
  ];

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final ink = dark ? const Color(0xFFFFE9F0) : const Color(0xFF4A1630);
    final soft = dark ? const Color(0xFFC7A9C4) : const Color(0xFF8A6070);
    final brand = dark ? const Color(0xFFF2C9DA) : const Color(0xFF6D3550);
    final faint = dark ? const Color(0xFF9D8AA8) : const Color(0xFF9A7985);

    return Scaffold(
      body: DecoratedBox(
        key: const Key('brand-splash'),
        decoration: BoxDecoration(
          gradient: RadialGradient(
            center: const Alignment(0, -0.3),
            radius: 1.2,
            colors: dark ? darkColors : lightColors,
            stops: const [0, .55, 1],
          ),
        ),
        child: SafeArea(
          child: Stack(
            children: [
              Center(
                child: Semantics(
                  label: 'Us, just the two of you. Loading',
                  child: ExcludeSemantics(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 124,
                          height: 124,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(29),
                            boxShadow: [
                              BoxShadow(
                                color: dark
                                    ? const Color(0x66FF78AA)
                                    : const Color(0x99502A6E),
                                blurRadius: 40,
                                spreadRadius: -14,
                                offset: const Offset(0, 18),
                              ),
                            ],
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(29),
                            child: Image.asset(
                              'assets/branding/app_icon.png',
                              width: 124,
                              height: 124,
                              filterQuality: FilterQuality.medium,
                              errorBuilder: (context, error, stack) =>
                                  ColoredBox(color: const Color(0xFF241848)),
                            ),
                          ),
                        ),
                        const SizedBox(height: 20),
                        Text(
                          'Us',
                          style: TextStyle(
                            fontFamily: 'UsSerif',
                            fontStyle: FontStyle.italic,
                            fontWeight: FontWeight.w700,
                            fontSize: 44,
                            height: 1,
                            color: ink,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          'just the two of you',
                          style: TextStyle(
                            fontSize: 14,
                            letterSpacing: .3,
                            color: soft,
                          ),
                        ),
                        const SizedBox(height: 24),
                        const _BreathingDots(color: Color(0xFFE58AAB)),
                      ],
                    ),
                  ),
                ),
              ),
              Positioned(
                right: 20,
                bottom: 18,
                child: Text.rich(
                  key: const Key('powered-by'),
                  TextSpan(
                    text: 'powered by ',
                    style: TextStyle(
                      fontSize: 11,
                      letterSpacing: .4,
                      color: faint,
                    ),
                    children: [
                      TextSpan(
                        text: 'RESET95',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1.3,
                          color: brand,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Three dots that brighten in turn; still when motion is reduced.
class _BreathingDots extends StatefulWidget {
  const _BreathingDots({required this.color});

  final Color color;

  @override
  State<_BreathingDots> createState() => _BreathingDotsState();
}

class _BreathingDotsState extends State<_BreathingDots>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MotionPolicy.enabled(context)) {
      if (!_c.isAnimating) _c.repeat();
    } else {
      _c.stop();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < 3; i++) ...[
            if (i > 0) const SizedBox(width: 7),
            Container(
              width: 7,
              height: 7,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: widget.color.withValues(alpha: _alpha(i)),
              ),
            ),
          ],
        ],
      ),
    );
  }

  double _alpha(int i) {
    if (!_c.isAnimating) return i == 1 ? 1 : .45;
    final t = (_c.value * 3 - i) % 3;
    return t < 1 ? .45 + .55 * (1 - (t - .5).abs() * 2).clamp(0, 1) : .45;
  }
}
