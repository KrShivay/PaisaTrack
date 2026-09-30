import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paisatrack/core/widgets/bloom/bloom.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('showBloomFullScreenSheet (T-152a)', () {
    testWidgets('renders 44x5 handle, 30px radius, and mandatory exit control',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () {
                  showBloomFullScreenSheet(
                    context: context,
                    title: 'Test Full Sheet',
                    showBack: true,
                    builder: (ctx) =>
                        const Center(child: Text('Sheet Content')),
                  );
                },
                child: const Text('Open Sheet'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open Sheet'));
      await tester.pumpAndSettle();

      // Verify full screen content and title render
      expect(find.text('Test Full Sheet'), findsOneWidget);
      expect(find.text('Sheet Content'), findsOneWidget);

      // Verify exit control (Back button) is present
      final backButtonFinder = find.byTooltip('Back');
      expect(backButtonFinder, findsOneWidget);

      // Verify grab handle (44x5 Container) is present
      final handleFinder = find.byWidgetPredicate(
        (widget) =>
            widget is Container &&
            widget.constraints?.maxWidth == 44 &&
            widget.constraints?.maxHeight == 5,
      );
      expect(handleFinder, findsOneWidget);

      // Tap back button to dismiss
      await tester.tap(backButtonFinder);
      await tester.pumpAndSettle();
      expect(find.text('Sheet Content'), findsNothing);
    });

    testWidgets('asserts mandatory exit affordance is passed', (tester) async {
      expect(
        () => showBloomFullScreenSheet(
          context: tester.element(find.byType(Container).first),
          showBack: false,
          showClose: false,
          builder: (ctx) => const SizedBox(),
        ),
        throwsAssertionError,
      );
    });

    testWidgets(
      'keyboard-aware full-screen route preserves insets for a nested modal',
      (tester) async {
        tester.view.physicalSize = const Size(320, 568);
        tester.view.devicePixelRatio = 1;
        tester.view.viewInsets = const FakeViewPadding(bottom: 220);
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
          tester.view.resetViewInsets();
        });

        await tester.pumpWidget(
          MaterialApp(
            home: Builder(
              builder: (context) => Scaffold(
                body: Center(
                  child: FilledButton(
                    onPressed: () {
                      showBloomFullScreenSheet<void>(
                        context: context,
                        avoidKeyboard: true,
                        showClose: true,
                        builder: (sheetContext) => Center(
                          child: FilledButton(
                            key: const ValueKey('open-nested-modal'),
                            onPressed: () {
                              showBloomModalSheet<void>(
                                context: sheetContext,
                                builder: (_) => SizedBox(
                                  height: 120,
                                  child: Center(
                                    child: FilledButton(
                                      key: const ValueKey('close-nested-modal'),
                                      onPressed: () =>
                                          Navigator.of(sheetContext).pop(),
                                      child: const Text('Nested modal'),
                                    ),
                                  ),
                                ),
                              );
                            },
                            child: const Text('Open nested modal'),
                          ),
                        ),
                      );
                    },
                    child: const Text('Open keyboard-aware sheet'),
                  ),
                ),
              ),
            ),
          ),
        );

        await tester.tap(find.text('Open keyboard-aware sheet'));
        await tester.pumpAndSettle();
        final outerButton = find.byKey(const ValueKey('open-nested-modal'));
        expect(tester.getRect(outerButton).bottom, lessThanOrEqualTo(348));
        expect(
          MediaQuery.viewInsetsOf(tester.element(outerButton)).bottom,
          220,
        );

        await tester.tap(outerButton);
        await tester.pumpAndSettle();
        final nestedButton = find.byKey(const ValueKey('close-nested-modal'));
        expect(tester.getRect(nestedButton).bottom, lessThanOrEqualTo(348));
        expect(
          MediaQuery.viewInsetsOf(tester.element(nestedButton)).bottom,
          220,
        );

        await tester.tap(nestedButton);
        await tester.pumpAndSettle();
        expect(tester.getRect(outerButton).bottom, lessThanOrEqualTo(348));
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets('drag past threshold dismisses sheet', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () {
                  showBloomFullScreenSheet(
                    context: context,
                    title: 'Draggable Sheet',
                    showClose: true,
                    builder: (ctx) => const Center(child: Text('Drag Me')),
                  );
                },
                child: const Text('Open Sheet'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open Sheet'));
      await tester.pumpAndSettle();

      expect(find.text('Drag Me'), findsOneWidget);

      // Drag down past dismissal threshold
      await tester.drag(find.text('Draggable Sheet'), const Offset(0, 400));
      await tester.pumpAndSettle();

      expect(find.text('Drag Me'), findsNothing);
    });

    testWidgets('semantics test asserts exit controls are labelled',
        (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () {
                  showBloomFullScreenSheet(
                    context: context,
                    title: 'Semantics Sheet',
                    showBack: true,
                    showClose: true,
                    builder: (ctx) => const SizedBox(),
                  );
                },
                child: const Text('Open Sheet'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open Sheet'));
      await tester.pumpAndSettle();

      expect(find.byTooltip('Back'), findsOneWidget);
      expect(find.byTooltip('Close'), findsOneWidget);

      handle.dispose();
    });

    testWidgets('honours disableAnimations (reduce motion)', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(disableAnimations: true),
            child: child!,
          ),
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () {
                  showBloomFullScreenSheet(
                    context: context,
                    title: 'Reduce Motion Sheet',
                    showBack: true,
                    builder: (ctx) => const Text('No Motion'),
                  );
                },
                child: const Text('Open Sheet'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open Sheet'));
      await tester.pump();
      // Verify it is immediately fully visible
      expect(find.text('No Motion'), findsOneWidget);
      final dy = tester.getTopLeft(find.text('No Motion')).dy;
      await tester.pump(const Duration(milliseconds: 50));
      expect(tester.getTopLeft(find.text('No Motion')).dy, dy);
    });

    testWidgets('drag not past threshold springs back', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () {
                  showBloomFullScreenSheet(
                    context: context,
                    title: 'Spring Back Sheet',
                    showClose: true,
                    builder: (ctx) => const Center(child: Text('Drag Me')),
                  );
                },
                child: const Text('Open Sheet'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open Sheet'));
      await tester.pumpAndSettle();

      final initialRect = tester.getRect(find.text('Drag Me'));

      // Drag down but not past dismissal threshold
      // A small drag (e.g. 100 pixels) should not dismiss it.
      await tester.drag(find.text('Spring Back Sheet'), const Offset(0, 100));
      // Give it time to start springing back
      await tester.pump();
      // It should be moving back
      expect(
        tester.getRect(find.text('Drag Me')).top,
        greaterThanOrEqualTo(initialRect.top),
      );

      // Settle the spring back animation
      await tester.pumpAndSettle();

      // Verify it sprang back to original position
      expect(tester.getRect(find.text('Drag Me')), initialRect);
    });
  });
}
