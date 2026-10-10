import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paisatrack/core/theme/app_theme.dart';
import 'package:paisatrack/core/widgets/bloom/bloom_sheet_scaffold.dart';

void main() {
  testWidgets('tall sheet header stays below status bar and cutout',
      (tester) async {
    tester.view.physicalSize = const Size(402, 874);
    tester.view.devicePixelRatio = 1;
    tester.view.padding = const FakeViewPadding(top: 48);
    tester.view.viewPadding = const FakeViewPadding(top: 48);
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => showBloomModalSheet<void>(
                context: context,
                builder: (_) => const BloomSheetScaffold(
                  title: 'Header',
                  child: SizedBox(height: 2000),
                ),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(
      tester.getTopLeft(find.byType(BloomSheetScaffold)).dy,
      greaterThanOrEqualTo(48),
    );
    expect(tester.getTopLeft(find.text('Header')).dy, greaterThanOrEqualTo(48));
  });

  test('overlay style is transparent with brightness-correct icons', () {
    final dark = AppTheme.edgeToEdgeOverlayStyle(Brightness.dark);
    final light = AppTheme.edgeToEdgeOverlayStyle(Brightness.light);
    expect(dark.statusBarColor, Colors.transparent);
    expect(dark.systemNavigationBarColor, Colors.transparent);
    expect(dark.statusBarIconBrightness, Brightness.light);
    expect(light.statusBarIconBrightness, Brightness.dark);
    expect(
      AppTheme.bloomDark().appBarTheme.systemOverlayStyle?.statusBarColor,
      Colors.transparent,
    );
    expect(
      AppTheme.light().appBarTheme.systemOverlayStyle?.statusBarIconBrightness,
      Brightness.dark,
    );
  });
}
