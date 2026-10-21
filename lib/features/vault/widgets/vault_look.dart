import 'package:flutter/material.dart';

import 'package:couple_app/core/theme/app_theme.dart';
import 'package:couple_app/core/widgets/animated_gradient_card.dart';
import 'package:couple_app/core/widgets/floating_hearts.dart';
import 'package:couple_app/core/widgets/glass.dart';
import 'package:couple_app/core/widgets/gradient_preset.dart';
import 'package:couple_app/features/onboarding/widgets/romance_kit.dart';

/// The vault's look: a deep night gradient with slow stars, light text,
/// warm gold and blush accents. Calm, dim and private, in both themes.

/// The night preset every vault screen sits on.
const vaultPreset = GradientPreset.night;

/// Warm gold, for highlights and the active dot.
const vaultGold = Color(0xFFFFE08A);

/// Soft blush, for the user's own bubbles and hearts.
const vaultBlush = Color(0xFFFF9EBB);

/// Muted light text.
const vaultMuted = Color(0xCCFFF4F6);

/// The app's dark theme, keeping the surrounding text fallbacks (emoji), so
/// sheets and dialogs read well over the night gradient.
ThemeData vaultThemeOf(BuildContext context) {
  final base = Theme.of(context);
  final dark = AppTheme.dark();
  final fallback = base.textTheme.bodyMedium?.fontFamilyFallback;
  return dark.copyWith(
    scaffoldBackgroundColor: Colors.transparent,
    textTheme: dark.textTheme.apply(fontFamilyFallback: fallback),
    primaryTextTheme: dark.primaryTextTheme.apply(fontFamilyFallback: fallback),
    colorScheme: dark.colorScheme.copyWith(
      primary: vaultGold,
      onPrimary: const Color(0xFF2A2140),
      surface: const Color(0xFF1B1838),
      surfaceContainerHigh: const Color(0xFF26214A),
      surfaceContainerHighest: const Color(0xFF2E2856),
    ),
    dialogTheme: const DialogThemeData(backgroundColor: Color(0xFF231E45)),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: Color(0xFF1E1A3F),
      surfaceTintColor: Colors.transparent,
    ),
    popupMenuTheme: const PopupMenuThemeData(color: Color(0xFF26214A)),
    snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
  );
}

/// Applies [vaultThemeOf] to [child].
class VaultTheme extends StatelessWidget {
  const VaultTheme({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) =>
      Theme(data: vaultThemeOf(context), child: child);
}

/// A full-page night gradient with a few slow stars behind [child].
class VaultBackdrop extends StatelessWidget {
  const VaultBackdrop({super.key, required this.child, this.stars = 16});

  final Widget child;
  final int stars;

  @override
  Widget build(BuildContext context) {
    return VaultTheme(
      child: Stack(
        fit: StackFit.expand,
        children: [
          const RepaintBoundary(
            child: AnimatedGradientBackground(
              preset: vaultPreset,
              colors: [Color(0xFF15173A), Color(0xFF2A1D52), Color(0xFF0E1030)],
              duration: Duration(seconds: 18),
            ),
          ),
          if (stars > 0)
            Positioned.fill(
              child: FloatingHearts(
                count: stars,
                style: ParticleStyle.stars,
                color: vaultGold,
                opacity: .45,
                duration: const Duration(seconds: 26),
              ),
            ),
          child,
        ],
      ),
    );
  }
}

/// A serif title for vault screens.
class VaultTitle extends StatelessWidget {
  const VaultTitle(this.text, {super.key, this.size = 30, this.center = true});

  final String text;
  final double size;
  final bool center;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      textAlign: center ? TextAlign.center : TextAlign.start,
      style: romanceSerif(Theme.of(context).textTheme.headlineMedium).copyWith(
        fontSize: size,
        fontWeight: FontWeight.w700,
        fontStyle: FontStyle.italic,
        color: Colors.white,
        height: 1.15,
      ),
    );
  }
}

/// Body text on the night gradient.
class VaultText extends StatelessWidget {
  const VaultText(this.text, {super.key, this.center = true, this.size = 15});

  final String text;
  final bool center;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      textAlign: center ? TextAlign.center : TextAlign.start,
      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
        fontSize: size,
        color: vaultMuted,
        height: 1.45,
      ),
    );
  }
}

/// The glowing lock badge at the top of vault pages.
class VaultBadge extends StatelessWidget {
  const VaultBadge({super.key, this.icon = Icons.lock_rounded, this.size = 76});

  final IconData icon;
  final double size;

  @override
  Widget build(BuildContext context) =>
      GlowBadge(preset: vaultPreset, icon: icon, size: size);
}

/// The vault's primary pill button: gold on night.
ButtonStyle vaultButtonStyle(
  BuildContext context, {
  Size minimumSize = const Size.fromHeight(54),
}) => FilledButton.styleFrom(
  minimumSize: minimumSize,
  backgroundColor: vaultGold,
  foregroundColor: const Color(0xFF2A2140),
  disabledBackgroundColor: Colors.white.withValues(alpha: .12),
  disabledForegroundColor: Colors.white38,
  shape: const StadiumBorder(),
  padding: const EdgeInsets.symmetric(horizontal: 24),
  textStyle: Theme.of(
    context,
  ).textTheme.labelLarge?.copyWith(fontSize: 16, fontWeight: FontWeight.w700),
  elevation: 0,
);

/// A quiet outlined pill for secondary actions.
ButtonStyle vaultOutlineStyle(
  BuildContext context, {
  Size minimumSize = const Size.fromHeight(54),
}) => OutlinedButton.styleFrom(
  minimumSize: minimumSize,
  foregroundColor: Colors.white,
  backgroundColor: Colors.white.withValues(alpha: .06),
  side: BorderSide(color: Colors.white.withValues(alpha: .28)),
  shape: const StadiumBorder(),
  padding: const EdgeInsets.symmetric(horizontal: 20),
  textStyle: Theme.of(
    context,
  ).textTheme.labelLarge?.copyWith(fontSize: 15, fontWeight: FontWeight.w600),
);

/// A frosted card on the night gradient.
class VaultCard extends StatelessWidget {
  const VaultCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.radius = 22,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;

  @override
  Widget build(BuildContext context) =>
      GlassPanel(dark: true, radius: radius, padding: padding, child: child);
}

/// A dialog in the vault's look.
Future<T?> showVaultDialog<T>(BuildContext context, WidgetBuilder builder) =>
    showDialog<T>(
      context: context,
      builder: (dialogContext) => VaultTheme(child: Builder(builder: builder)),
    );

/// A bottom sheet in the vault's look.
Future<T?> showVaultSheet<T>(
  BuildContext context,
  WidgetBuilder builder, {
  bool scrollable = false,
}) => showModalBottomSheet<T>(
  context: context,
  isScrollControlled: scrollable,
  showDragHandle: true,
  backgroundColor: const Color(0xFF1E1A3F),
  builder: (sheetContext) => VaultTheme(child: Builder(builder: builder)),
);
