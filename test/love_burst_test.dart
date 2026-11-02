import 'package:couple_app/features/avatar/models/avatar_config.dart';
import 'package:couple_app/features/avatar/widgets/avatar_view.dart';
import 'package:couple_app/features/home/models/love_tap.dart';
import 'package:couple_app/features/home/widgets/love_burst.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<OverlayState> host(WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: Text('home'))),
    );
    return tester.state<OverlayState>(find.byType(Overlay).first);
  }

  testWidgets('plays over the screen with the avatar, then goes away', (
    tester,
  ) async {
    final overlay = await host(tester);
    LoveBurst.play(
      LoveTap.kiss,
      avatar: const AvatarConfig(),
      overlay: overlay,
    );
    await tester.pump();
    expect(find.byType(LoveBurstView), findsOneWidget);
    final big = tester.widget<AvatarView>(
      find.descendant(
        of: find.byType(LoveBurstView),
        matching: find.byType(AvatarView),
      ),
    );
    expect(big.expression, AvatarExpression.kiss);
    // Touches go through to the screen underneath.
    await tester.tap(find.text('home'));

    await tester.pump(const Duration(milliseconds: 1200));
    expect(find.byType(LoveBurstView), findsOneWidget);
    await tester.pump(LoveBurst.duration);
    await tester.pump();
    expect(find.byType(LoveBurstView), findsNothing);
  });

  testWidgets('without an avatar it shows the emoji; a new tap replaces it', (
    tester,
  ) async {
    final overlay = await host(tester);
    LoveBurst.play(LoveTap.hug, overlay: overlay);
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('🤗'), findsOneWidget);
    LoveBurst.play(LoveTap.love, overlay: overlay);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(LoveBurstView), findsOneWidget);
    expect(find.text('❤️'), findsOneWidget);
    // The animation starts on the first frame after the tap.
    await tester.pump(LoveBurst.duration);
    await tester.pump();
    expect(find.byType(LoveBurstView), findsNothing);
  });

  testWidgets('reduced motion skips the burst', (tester) async {
    await tester.pumpWidget(
      const MediaQuery(
        data: MediaQueryData(disableAnimations: true),
        child: MaterialApp(home: Scaffold()),
      ),
    );
    LoveBurst.play(
      LoveTap.love,
      overlay: tester.state<OverlayState>(find.byType(Overlay).first),
    );
    await tester.pump();
    expect(find.byType(LoveBurstView), findsNothing);
  });

  testWidgets('a reaction holds the face for a moment', (tester) async {
    AvatarReactions.react('ann', AvatarExpression.love);
    expect(AvatarReactions.faces.value['ann'], AvatarExpression.love);
    await tester.pump(AvatarReactions.hold + const Duration(milliseconds: 10));
    expect(AvatarReactions.faces.value.containsKey('ann'), isFalse);
  });

  test('every love tap has a face, emojis and a glow', () {
    for (final tap in LoveTap.values) {
      expect(tap.particles, isNotEmpty);
      expect(tap.tint.a, greaterThan(0));
    }
    expect(LoveTap.missYou.expression, AvatarExpression.sad);
  });
}
