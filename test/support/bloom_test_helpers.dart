import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paisatrack/core/theme/app_theme.dart';

/// Loads Space Grotesk and IBM Plex Mono font files so golden tests render
/// the correct glyphs instead of Ahem rectangles.
///
/// Call this in [setUpAll] or [setUp] before any golden test.
Future<void> loadBloomFonts() async {
  TestWidgetsFlutterBinding.ensureInitialized();

  await _loadFont('SpaceGrotesk', [
    'assets/fonts/SpaceGrotesk/SpaceGrotesk-Regular.ttf',
    'assets/fonts/SpaceGrotesk/SpaceGrotesk-Medium.ttf',
    'assets/fonts/SpaceGrotesk/SpaceGrotesk-Bold.ttf',
    'assets/fonts/SpaceGrotesk/SpaceGrotesk-Variable.ttf',
  ]);

  await _loadFont('IBMPlexMono', [
    'assets/fonts/IBMPlexMono/IBMPlexMono-Regular.ttf',
    'assets/fonts/IBMPlexMono/IBMPlexMono-Medium.ttf',
    'assets/fonts/IBMPlexMono/IBMPlexMono-SemiBold.ttf',
  ]);
}

Future<void> _loadFont(String family, List<String> paths) async {
  final loader = FontLoader(family);
  for (final path in paths) {
    final file = File(path);
    if (await file.exists()) {
      final bytes = await file.readAsBytes();
      loader.addFont(Future.value(ByteData.view(bytes.buffer)));
    }
  }
  await loader.load();
}

/// Pumps a [widget] inside a Bloom-themed [MaterialApp] at the specified
/// [size] (defaults to 402×874 — the design reference viewport).
///
/// Use [brightness] to test light or dark variants.
Future<void> pumpBloomWidget(
  WidgetTester tester,
  Widget widget, {
  Brightness brightness = Brightness.light,
  Size size = const Size(402, 874),
}) async {
  // Set logical viewport size.
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;

  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });

  final theme = brightness == Brightness.light
      ? AppTheme.bloomLight()
      : AppTheme.bloomDark();

  await tester.pumpWidget(
    MaterialApp(
      theme: theme,
      darkTheme: AppTheme.bloomDark(),
      themeMode:
          brightness == Brightness.light ? ThemeMode.light : ThemeMode.dark,
      home: Scaffold(body: widget),
      debugShowCheckedModeBanner: false,
    ),
  );
}

/// Pumps a [widget] inside a Bloom-themed [MaterialApp] at 320px width
/// (narrow viewport) for responsive layout testing.
Future<void> pumpBloomWidgetNarrow(
  WidgetTester tester,
  Widget widget, {
  Brightness brightness = Brightness.light,
}) async {
  await pumpBloomWidget(
    tester,
    widget,
    brightness: brightness,
    size: const Size(320, 568),
  );
}

/// Pumps with [MediaQuery.disableAnimations] set to true for reduce-motion
/// testing.
Future<void> pumpBloomWidgetReducedMotion(
  WidgetTester tester,
  Widget widget, {
  Brightness brightness = Brightness.light,
  Size size = const Size(402, 874),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;

  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });

  final theme = brightness == Brightness.light
      ? AppTheme.bloomLight()
      : AppTheme.bloomDark();

  await tester.pumpWidget(
    MediaQuery(
      data: const MediaQueryData(disableAnimations: true),
      child: MaterialApp(
        theme: theme,
        darkTheme: AppTheme.bloomDark(),
        themeMode:
            brightness == Brightness.light ? ThemeMode.light : ThemeMode.dark,
        home: Scaffold(body: widget),
        debugShowCheckedModeBanner: false,
      ),
    ),
  );
}
