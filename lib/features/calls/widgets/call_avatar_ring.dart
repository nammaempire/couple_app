import 'package:flutter/material.dart';

import 'package:couple_app/core/widgets/entrance_animation.dart';

/// The partner's avatar inside a glowing gradient ring. With [pulse], soft
/// halos breathe outwards (ringing, connecting); still when motion is off.
class CallAvatarRing extends StatelessWidget {
  const CallAvatarRing({
    super.key,
    required this.child,
    required this.size,
    this.pulse = false,
  });

  /// The avatar, [size] across.
  final Widget child;
  final double size;
  final bool pulse;

  static const _ring = SweepGradient(
    colors: [
      Color(0xFFFF7EB3),
      Color(0xFFB892FF),
      Color(0xFFFFC27A),
      Color(0xFFFF7EB3),
    ],
  );

  @override
  Widget build(BuildContext context) {
    final outer = size * 1.6;
    final avatar = Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: _ring,
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFFF7EB3).withValues(alpha: .45),
            blurRadius: 28,
            spreadRadius: 2,
          ),
        ],
      ),
      child: Container(
        padding: const EdgeInsets.all(3),
        decoration: const BoxDecoration(
          shape: BoxShape.circle,
          color: Color(0xFF2A1838),
        ),
        child: ClipOval(child: child),
      ),
    );

    Widget halo(double scale, double alpha) => Transform.scale(
      scale: scale,
      child: Container(
        width: size + 14,
        height: size + 14,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(
            color: const Color(0xFFFFB3CF).withValues(alpha: alpha),
            width: 2,
          ),
          gradient: RadialGradient(
            colors: [
              const Color(0x00FF7EB3),
              const Color(0xFFFF7EB3).withValues(alpha: alpha * .35),
            ],
          ),
        ),
      ),
    );

    return SizedBox.square(
      dimension: outer,
      child: pulse
          ? RepaintBoundary(
              child: Pulse(
                duration: const Duration(milliseconds: 1600),
                child: avatar,
                builder: (context, v, child) => Stack(
                  alignment: Alignment.center,
                  children: [
                    halo(1.28 + .14 * v, .22 * (1 - v) + .08),
                    halo(1.12 + .08 * v, .4 * (1 - v) + .14),
                    Transform.scale(scale: 1 + .02 * v, child: child),
                  ],
                ),
              ),
            )
          : Center(child: avatar),
    );
  }
}

/// A round frosted call button; [colors] fills it with a gradient instead
/// (hang up, accept).
class GlassCallButton extends StatelessWidget {
  const GlassCallButton({
    super.key,
    required this.icon,
    required this.onPressed,
    this.tooltip,
    this.colors,
    this.active = false,
    this.size = 60,
    this.iconSize = 26,
  });

  final IconData icon;
  final VoidCallback? onPressed;
  final String? tooltip;
  final List<Color>? colors;

  /// Toggled on (muted, camera off): a solid white face.
  final bool active;
  final double size;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    final colors = this.colors;
    final fg = colors != null
        ? Colors.white
        : active
        ? const Color(0xFF33204F)
        : Colors.white;
    final decoration = BoxDecoration(
      shape: BoxShape.circle,
      gradient: colors == null
          ? null
          : LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: colors,
            ),
      color: colors != null
          ? null
          : active
          ? Colors.white
          : Colors.white.withValues(alpha: .16),
      border: colors != null
          ? null
          : Border.all(color: Colors.white.withValues(alpha: .3)),
      boxShadow: colors == null
          ? null
          : [
              BoxShadow(
                color: colors.first.withValues(alpha: .5),
                blurRadius: 20,
                offset: const Offset(0, 6),
              ),
            ],
    );
    Widget button = Opacity(
      opacity: onPressed == null ? .55 : 1,
      child: DecoratedBox(
        decoration: decoration,
        child: Material(
          type: MaterialType.transparency,
          shape: const CircleBorder(),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onPressed,
            child: SizedBox.square(
              dimension: size,
              child: Icon(icon, color: fg, size: iconSize),
            ),
          ),
        ),
      ),
    );
    if (tooltip != null) button = Tooltip(message: tooltip, child: button);
    return button;
  }
}
