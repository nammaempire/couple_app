import 'package:couple_app/core/widgets/entrance_animation.dart';
import 'package:couple_app/core/widgets/motion_policy.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Opacity of the item labelled [label], or 1 when it isn't faded.
double _opacityOf(WidgetTester tester, String label) {
  final opacities = tester.widgetList<Opacity>(
    find.ancestor(of: find.text(label), matching: find.byType(Opacity)),
  );
  return opacities.isEmpty ? 1 : opacities.first.opacity;
}

Widget _list() => MaterialApp(
  home: Scaffold(
    body: ListView(
      children: [
        for (var i = 0; i < 60; i++)
          EntranceAnimation(
            index: i,
            child: SizedBox(height: 180, child: Text('card $i')),
          ),
      ],
    ),
  ),
);

void main() {
  // Motion is frozen for every other test; this one needs it running.
  setUp(() => MotionPolicy.frozen = false);
  tearDown(() => MotionPolicy.frozen = true);

  testWidgets('the first view still fades in', (tester) async {
    await tester.pumpWidget(_list());
    expect(_opacityOf(tester, 'card 1'), lessThan(1));
    await tester.pumpAndSettle();
    expect(_opacityOf(tester, 'card 1'), 1);
  });

  testWidgets('cards built while scrolling fast show at once (no blank page)', (
    tester,
  ) async {
    await tester.pumpWidget(_list());
    await tester.pumpAndSettle();

    // A fast fling down the page, checked a frame later.
    await tester.fling(find.byType(ListView), const Offset(0, -3000), 8000);
    await tester.pump(const Duration(milliseconds: 16));
    await tester.pump(const Duration(milliseconds: 16));

    final visible = find.textContaining('card ').evaluate().toList();
    expect(visible, isNotEmpty);
    for (final e in visible) {
      final label = (e.widget as Text).data!;
      expect(_opacityOf(tester, label), 1, reason: '$label was still fading in');
    }

    // And scrolling back up doesn't fade the top cards in again.
    await tester.pumpAndSettle();
    await tester.fling(find.byType(ListView), const Offset(0, 3000), 8000);
    await tester.pump(const Duration(milliseconds: 16));
    await tester.pump(const Duration(milliseconds: 16));
    for (final e in find.textContaining('card ').evaluate()) {
      final label = (e.widget as Text).data!;
      expect(_opacityOf(tester, label), 1, reason: '$label faded in again');
    }
  });
}
