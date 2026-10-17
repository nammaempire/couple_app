import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:couple_app/features/avatar/models/avatar_config.dart';
import 'package:couple_app/features/avatar/widgets/avatar_view.dart';
import 'package:couple_app/features/stickers/models/sticker_scene.dart';
import 'package:couple_app/features/stickers/widgets/sticker_props_painter.dart';

/// A couple sticker: both partners' avatars posed per [scene], its props,
/// and [quote] on a paper ribbon underneath, on a soft gradient card.
///
/// [sender] is always drawn on the left and [partner] on the right, facing
/// them. A null avatar is drawn as a soft grey stand-in, so stickers work
/// before anyone has made an avatar. Everything scales with [width].
class CoupleStickerView extends StatelessWidget {
  const CoupleStickerView({
    super.key,
    required this.scene,
    required this.sender,
    required this.partner,
    required this.quote,
    this.width = 240,
    this.showQuote = true,
  });

  final StickerScene scene;
  final AvatarConfig? sender;
  final AvatarConfig? partner;
  final String quote;
  final double width;

  /// False draws only the picture, e.g. for a thumbnail in a reply quote.
  final bool showQuote;

  /// Art height as a fraction of [width].
  static const artRatio = .72;

  static const _darkBase = Color(0xFF2A2030);

  /// The card's border width at [width].
  static double _borderWidth(double width) => math.max(1, width * .004);

  /// The height a card [width] wide takes with [quote] on it, for laying
  /// out fixed-size grid cells without building the card.
  static double heightFor(
    BuildContext context, {
    required String quote,
    required double width,
  }) {
    final w = width;
    final ribbon = _QuoteRibbon(
      quote: quote,
      width: w,
      accent: const Color(0xFF000000),
      dark: false,
    );
    final painter = TextPainter(
      text: ribbon._span(Theme.of(context)),
      textAlign: TextAlign.center,
      textDirection: Directionality.maybeOf(context) ?? TextDirection.ltr,
      maxLines: _QuoteRibbon._maxLines,
      ellipsis: '…',
      textScaler: _QuoteRibbon._textScaler(context),
    )..layout(maxWidth: math.max(0, w - _QuoteRibbon._innerInset(w)));
    final textHeight = painter.height;
    painter.dispose();
    return w * artRatio -
        w * .07 +
        _QuoteRibbon._outerExtent(w) +
        textHeight +
        _borderWidth(w) * 2;
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final w = width;
    final artHeight = w * artRatio;
    final colors = [
      for (final c in scene.gradient) dark ? Color.lerp(c, _darkBase, .74)! : c,
    ];
    final radius = BorderRadius.circular(w * .085);

    // The art is costly to paint and rarely changes, so it gets its own
    // layer: scrolling, ribbon edits and selection don't repaint it.
    final art = RepaintBoundary(
      child: _StickerArt(
        scene: scene,
        sender: sender,
        partner: partner,
        width: w,
        height: artHeight,
        dark: dark,
      ),
    );

    return Semantics(
      label: showQuote
          ? 'Sticker, ${scene.label}: $quote'
          : 'Sticker, ${scene.label}',
      excludeSemantics: true,
      child: Container(
        width: w,
        decoration: BoxDecoration(
          borderRadius: radius,
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: colors,
          ),
          border: Border.all(
            color: Colors.white.withValues(alpha: dark ? .08 : .7),
            width: _borderWidth(w),
          ),
          boxShadow: [
            BoxShadow(
              color: (dark ? Colors.black : scene.accent).withValues(
                alpha: dark ? .3 : .14,
              ),
              blurRadius: w * .05,
              offset: Offset(0, w * .015),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: radius,
          child: showQuote
              ? Stack(
                  children: [
                    Positioned(
                      top: 0,
                      left: 0,
                      right: 0,
                      height: artHeight,
                      child: art,
                    ),
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        SizedBox(height: artHeight - w * .07),
                        _QuoteRibbon(
                          quote: quote,
                          width: w,
                          accent: scene.accent,
                          dark: dark,
                        ),
                      ],
                    ),
                  ],
                )
              : SizedBox(height: artHeight, child: art),
        ),
      ),
    );
  }
}

/// Where the avatars stand for one [StickerLayout], as fractions of the
/// card width: avatar size, each avatar's left edge, and the lean.
class _Pose {
  const _Pose(this.size, this.senderX, this.partnerX, this.tilt);

  final double size;
  final double senderX;
  final double partnerX;

  /// Radians each head leans toward the other (negative leans away).
  final double tilt;

  /// How far the avatar's bottom edge sits below the art, so shoulders run
  /// under the quote ribbon.
  static const drop = .03;

  static _Pose of(StickerLayout layout) => switch (layout) {
    StickerLayout.together => const _Pose(.56, .03, .41, .08),
    StickerLayout.heads => const _Pose(.58, .04, .4, .14),
    StickerLayout.hug => const _Pose(.6, .07, .344, .06),
    StickerLayout.apart => const _Pose(.46, -.03, .57, 0),
    StickerLayout.solo => const _Pose(.72, .14, 0, 0),
  };

  /// Approximate head centre of an avatar whose left edge is at [x],
  /// leaning by [angle], in an art box [w] wide and [h] tall.
  Offset headCentre(double x, double angle, double w, double h) {
    final s = size * w;
    final pivot = Offset(x * w + s / 2, h + drop * w);
    final up = s * .64;
    return pivot + Offset(up * math.sin(angle), -up * math.cos(angle));
  }
}

class _StickerArt extends StatelessWidget {
  const _StickerArt({
    required this.scene,
    required this.sender,
    required this.partner,
    required this.width,
    required this.height,
    required this.dark,
  });

  final StickerScene scene;
  final AvatarConfig? sender;
  final AvatarConfig? partner;
  final double width;
  final double height;
  final bool dark;

  @override
  Widget build(BuildContext context) {
    final w = width;
    final pose = _Pose.of(scene.layout);
    final solo = scene.isSolo;
    final size = pose.size * w;
    final bottom = -_Pose.drop * w;

    final heads = [
      pose.headCentre(pose.senderX, pose.tilt, w, height),
      if (!solo) pose.headCentre(pose.partnerX, -pose.tilt, w, height),
    ];

    StickerPropsPainter painter({required bool front}) => StickerPropsPainter(
      props: scene.props,
      front: front,
      layout: scene.layout,
      heads: heads,
      accent: scene.accent,
      dark: dark,
    );

    Widget figure(
      AvatarConfig? config,
      AvatarExpression expression, {
      required double left,
      required double angle,
      required bool mirror,
    }) {
      return Positioned(
        left: left * w,
        bottom: bottom,
        width: size,
        height: size,
        child: Transform.rotate(
          angle: angle,
          alignment: Alignment.bottomCenter,
          child: _Figure(
            config: config,
            expression: expression,
            size: size,
            mirror: mirror,
            dark: dark,
          ),
        ),
      );
    }

    final senderFigure = figure(
      sender,
      scene.senderExpression,
      left: pose.senderX,
      angle: pose.tilt,
      mirror: false,
    );

    return Stack(
      clipBehavior: Clip.hardEdge,
      children: [
        Positioned.fill(child: CustomPaint(painter: painter(front: false))),
        if (!solo)
          figure(
            partner,
            scene.partnerExpression,
            left: pose.partnerX,
            angle: -pose.tilt,
            mirror: true,
          ),
        senderFigure,
        Positioned.fill(child: CustomPaint(painter: painter(front: true))),
      ],
    );
  }
}

/// One avatar, or a soft grey stand-in when [config] is null.
class _Figure extends StatelessWidget {
  const _Figure({
    required this.config,
    required this.expression,
    required this.size,
    required this.mirror,
    required this.dark,
  });

  final AvatarConfig? config;
  final AvatarExpression expression;
  final double size;
  final bool mirror;
  final bool dark;

  @override
  Widget build(BuildContext context) {
    final real = config;
    if (real != null) {
      return AvatarView(
        config: real,
        expression: expression,
        size: size,
        showBackground: false,
        mirror: mirror,
      );
    }
    // Greyscale, lifted towards the card so it reads as "someone, soon".
    final lift = dark ? 70.0 : 120.0;
    final keep = dark ? .45 : .5;
    final row = [.2126 * keep, .7152 * keep, .0722 * keep, 0.0, lift];
    return Opacity(
      opacity: .9,
      child: ColorFiltered(
        colorFilter: ColorFilter.matrix([
          ...row,
          ...row,
          ...row,
          0,
          0,
          0,
          1,
          0,
        ]),
        child: AvatarView(
          config: const AvatarConfig(),
          size: size,
          showBackground: false,
          mirror: mirror,
        ),
      ),
    );
  }
}

/// The quote on a frosted paper strip at the foot of the sticker.
class _QuoteRibbon extends StatelessWidget {
  const _QuoteRibbon({
    required this.quote,
    required this.width,
    required this.accent,
    required this.dark,
  });

  final String quote;
  final double width;
  final Color accent;
  final bool dark;

  static const _maxLines = 4;

  /// Horizontal space taken by the ribbon's margin, padding and border.
  static double _innerInset(double w) => w * .045 * 2 + w * .05 * 2 + 2;

  /// Vertical space taken by the ribbon besides its text: bottom margin,
  /// padding and border.
  static double _outerExtent(double w) => w * .045 + w * .035 + w * .04 + 2;

  static TextScaler _textScaler(BuildContext context) =>
      MediaQuery.textScalerOf(context).clamp(maxScaleFactor: 1.3);

  /// The quote between curly marks, styled for this ribbon.
  TextSpan _span(ThemeData theme) {
    final w = width;
    final ink = dark ? const Color(0xFFF8EAF0) : const Color(0xFF4A2638);
    final mark = dark ? Color.lerp(accent, Colors.white, .35)! : accent;
    final fontSize = math.max(10.5, w * .062);
    final base = (theme.textTheme.titleMedium ?? const TextStyle()).copyWith(
      fontFamily: 'serif',
      fontFamilyFallback: const ['Georgia', 'Noto Serif', 'Times New Roman'],
      fontSize: fontSize,
      fontStyle: FontStyle.italic,
      fontWeight: FontWeight.w600,
      height: 1.28,
      letterSpacing: .1,
      color: ink,
    );
    final markStyle = base.copyWith(
      color: mark,
      fontWeight: FontWeight.w800,
      fontStyle: FontStyle.normal,
      fontSize: fontSize * 1.25,
      height: 1,
    );
    return TextSpan(
      style: base,
      children: [
        TextSpan(text: '“', style: markStyle),
        TextSpan(text: quote.trim()),
        TextSpan(text: '”', style: markStyle),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final w = width;
    return Container(
      margin: EdgeInsets.fromLTRB(w * .045, 0, w * .045, w * .045),
      padding: EdgeInsets.fromLTRB(w * .05, w * .035, w * .05, w * .04),
      decoration: BoxDecoration(
        color: dark
            ? const Color(0xFF241C27).withValues(alpha: .94)
            : Colors.white.withValues(alpha: .94),
        borderRadius: BorderRadius.circular(w * .055),
        border: Border.all(
          color: dark
              ? Colors.white.withValues(alpha: .06)
              : Colors.white.withValues(alpha: .9),
        ),
      ),
      child: Text.rich(
        _span(Theme.of(context)),
        textAlign: TextAlign.center,
        maxLines: _maxLines,
        overflow: TextOverflow.ellipsis,
        textScaler: _textScaler(context),
      ),
    );
  }
}
