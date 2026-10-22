import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:couple_app/core/theme/app_theme.dart';
import 'package:couple_app/core/widgets/brand_splash.dart';

void main() {
  for (final dark in [false, true]) {
    testWidgets('splash shows the brand (${dark ? 'dark' : 'light'})', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: dark ? AppTheme.dark() : AppTheme.light(),
          home: const BrandSplash(),
        ),
      );
      expect(find.text('Us'), findsOneWidget);
      expect(find.text('just the two of you'), findsOneWidget);
      final powered = tester.widget<RichText>(
        find.descendant(
          of: find.byKey(const Key('powered-by')),
          matching: find.byType(RichText),
        ),
      );
      expect(powered.text.toPlainText(), 'powered by RESET95');
      // Bottom right of the screen.
      final box = tester.getBottomRight(find.byKey(const Key('powered-by')));
      final size = tester.view.physicalSize / tester.view.devicePixelRatio;
      expect(box.dx, greaterThan(size.width - 40));
      expect(box.dy, greaterThan(size.height - 60));
      expect(find.bySemanticsLabel(RegExp('just the two of you')), findsOne);
    });
  }
}
