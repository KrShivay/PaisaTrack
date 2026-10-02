import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paisatrack/core/widgets/bloom/bloom.dart';
import 'package:paisatrack/data/db/database.dart';
import 'package:paisatrack/data/db/database_provider.dart';
import 'package:paisatrack/features/home/home_shell.dart';

void _setViewport(
  WidgetTester tester, {
  required Size size,
  required double bottomInset,
  double leftInset = 0,
  double rightInset = 0,
}) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  tester.view.padding = FakeViewPadding(
    left: leftInset,
    right: rightInset,
    bottom: bottomInset,
  );
  tester.view.viewPadding = FakeViewPadding(
    left: leftInset,
    right: rightInset,
    bottom: bottomInset,
  );
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

  for (final rotation in [
    (name: 'right-side', leftInset: 0.0, rightInset: 40.0),
    (name: 'left-side', leftInset: 40.0, rightInset: 0.0),
    (name: 'both-side cutout', leftInset: 40.0, rightInset: 40.0),
  ]) {
    testWidgets(
      'production pill and Ask orb clear ${rotation.name} landscape insets',
      (tester) async {
        const size = Size(964, 434);
        _setViewport(
          tester,
          size: size,
          bottomInset: 0,
          leftInset: rotation.leftInset,
          rightInset: rotation.rightInset,
        );
        await _pumpHomeShell(tester, textScale: 2);

        final pill = find.byType(HomeFloatingNavPill);
        final rect = tester.getRect(pill);
        expect(rect.left, greaterThanOrEqualTo(rotation.leftInset));
        expect(rect.right, lessThanOrEqualTo(size.width - rotation.rightInset));
        expect(
          tester.getRect(find.bySemanticsLabel('Ask PaisaTrack')).right,
          lessThanOrEqualTo(size.width - rotation.rightInset),
        );
        final tabContent = BloomBottomInset.forTabContent(
          MediaQuery.of(tester.element(pill)),
        );
        expect(tabContent.padding.left, rotation.leftInset);
        expect(tabContent.padding.right, rotation.rightInset);
        expect(tester.takeException(), isNull);
      },
    );
  }

  for (final scenario in [
    (
      name: 'compact 2x viewport',
      size: const Size(320, 568),
      textScale: 2.0,
      imeInset: 220.0,
    ),
    (
      name: 'phone-like portrait viewport',
      size: const Size(434, 964),
      textScale: 1.0,
      imeInset: 370.0,
    ),
  ]) {
    testWidgets(
      'production Ask modal clears the IME and closes at ${scenario.name}',
      (tester) async {
        _setViewport(
          tester,
          size: scenario.size,
          bottomInset: 24,
        );
        await _pumpHomeShell(tester, textScale: scenario.textScale);

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

        // Edge-to-edge Flutter keeps the full viewport and reports the IME inset.
        tester.view.viewInsets = FakeViewPadding(bottom: scenario.imeInset);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 250));

        final visibleBottom = scenario.size.height - scenario.imeInset;
        final close = find.byTooltip('Close');
        expect(close, findsOneWidget);
        expect(tester.getRect(close).bottom, lessThanOrEqualTo(visibleBottom));
        expect(
          tester.getRect(composer).bottom,
          lessThanOrEqualTo(visibleBottom),
        );
        expect(
          MediaQuery.sizeOf(tester.element(composer)).height,
          scenario.size.height,
        );
        expect(
          MediaQuery.viewInsetsOf(tester.element(composer)).bottom,
          scenario.imeInset,
        );
        expect(tester.takeException(), isNull);

        tester.view.viewInsets = const FakeViewPadding();
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 250));
        await tester.tap(close);
        await tester.pumpAndSettle();

        expect(
          find.byKey(const ValueKey('assistant_sheet_surface')),
          findsNothing,
        );
        expect(find.byType(HomeFloatingNavPill), findsOneWidget);
        expect(tester.takeException(), isNull);

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
      },
    );
  }
}
