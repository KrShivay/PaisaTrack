import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paisatrack/data/db/database.dart';
import 'package:paisatrack/data/db/database_provider.dart';
import 'package:paisatrack/features/home/home_shell.dart';

void _setViewport(
  WidgetTester tester, {
  required Size size,
  required double bottomInset,
}) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  tester.view.padding = FakeViewPadding(bottom: bottomInset);
  tester.view.viewPadding = FakeViewPadding(bottom: bottomInset);
  tester.view.viewInsets = const FakeViewPadding();
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
    tester.view.resetPadding();
    tester.view.resetViewPadding();
    tester.view.resetViewInsets();
  });
}

Future<void> _pumpHomeShell(
  WidgetTester tester, {
  double textScale = 1,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      // Home's initial page remains in loading state. Keeping the database
      // unopened exercises shell and modal lifecycle without Drift timers.
      overrides: [
        appDatabaseProvider.overrideWith(
          (ref) => Completer<AppDatabase>().future,
        ),
      ],
      child: MaterialApp(
        home: const HomeShell(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            disableAnimations: true,
            textScaler: TextScaler.linear(textScale),
          ),
          child: child!,
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 250));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final bottomInset in [24.0, 48.0]) {
    final mode = bottomInset == 24 ? 'gesture' : 'three-button';
    testWidgets(
      'HomeShell production pill and Ask modal work with $mode navigation',
      (tester) async {
        _setViewport(
          tester,
          size: const Size(402, 874),
          bottomInset: bottomInset,
        );
        await _pumpHomeShell(tester);

        final pill = find.byType(HomeFloatingNavPill);
        expect(pill, findsOneWidget);
        expect(
          tester.getRect(pill).bottom,
          lessThanOrEqualTo(874 - bottomInset),
        );

        await tester.tap(find.bySemanticsLabel('Ask PaisaTrack'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 250));

        final composer = find.byKey(const ValueKey('assistant_composer'));
        expect(composer, findsOneWidget);
        expect(
          find.byKey(const ValueKey('assistant_sheet_surface')),
          findsOneWidget,
        );
        expect(tester.getRect(composer).bottom, lessThanOrEqualTo(874));
        expect(tester.takeException(), isNull);

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
      },
    );
  }

  testWidgets(
    'production Ask modal keeps its close target and composer above compact keyboard',
    (tester) async {
      _setViewport(
        tester,
        size: const Size(320, 568),
        bottomInset: 24,
      );
      await _pumpHomeShell(tester, textScale: 2);

      await tester.tap(find.bySemanticsLabel('Ask PaisaTrack'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));

      final composer = find.byKey(const ValueKey('assistant_composer'));
      final field = find.descendant(
        of: composer,
        matching: find.byType(TextField),
      );
      expect(field, findsOneWidget);
      await tester.tap(field);

      // Android adjustResize reduces the viewport once; viewInsets stays zero.
      tester.view.physicalSize = const Size(320, 348);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));

      final close = find.byTooltip('Close');
      expect(close, findsOneWidget);
      expect(tester.getRect(close).height, greaterThanOrEqualTo(48));
      expect(tester.getRect(close).bottom, lessThanOrEqualTo(348));
      expect(tester.getRect(composer).bottom, lessThanOrEqualTo(348));
      expect(MediaQuery.viewInsetsOf(tester.element(composer)).bottom, 0);
      expect(tester.takeException(), isNull);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    },
  );
}
