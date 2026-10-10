import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paisatrack/core/theme/app_theme.dart';
import 'package:paisatrack/core/undo/undo_controller.dart';
import 'package:paisatrack/core/widgets/bloom/bloom_undo_toast.dart';

void main() {
  late int undoCount;
  late int backgroundTaps;

  Future<ProviderContainer> pumpHost(WidgetTester tester) async {
    undoCount = 0;
    backgroundTaps = 0;
    tester.view.physicalSize = const Size(402, 874);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: AppTheme.light(),
          home: BloomUndoToastHost(
            bottomOffset: 40,
            child: Scaffold(
              body: SizedBox.expand(
                child: InkWell(
                  key: const Key('behind'),
                  onTap: () => backgroundTaps++,
                ),
              ),
            ),
          ),
        ),
      ),
    );
    final container = ProviderScope.containerOf(
      tester.element(find.byKey(const Key('behind'))),
    );
    container.read(undoControllerProvider.notifier).pushUndo(
          UndoToken(
            id: 't',
            message: 'Filed under Food',
            undoAction: () async => undoCount++,
          ),
        );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    return container;
  }

  testWidgets('close button dismisses without undo', (tester) async {
    final handle = tester.ensureSemantics();
    final c = await pumpHost(tester);
    final close = find.byKey(const Key('bloom-undo-dismiss-button'));
    expect(tester.getSize(close).width, greaterThanOrEqualTo(48));
    expect(tester.getSize(close).height, greaterThanOrEqualTo(48));
    expect(tester.getSemantics(close).label, contains('Dismiss'));
    await tester.tap(close);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('bloom-undo-toast')), findsNothing);
    expect(c.read(undoControllerProvider), isNull);
    expect(undoCount, 0);
    handle.dispose();
  });

  testWidgets('horizontal swipe dismisses without undo', (tester) async {
    final c = await pumpHost(tester);
    await tester.fling(
      find.byKey(const Key('bloom-undo-toast')),
      const Offset(400, 0),
      1500,
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('bloom-undo-toast')), findsNothing);
    expect(c.read(undoControllerProvider), isNull);
    expect(undoCount, 0);
  });

  testWidgets('downward swipe dismisses without undo', (tester) async {
    final c = await pumpHost(tester);
    await tester.fling(
      find.byKey(const Key('bloom-undo-toast')),
      const Offset(0, 200),
      1500,
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('bloom-undo-toast')), findsNothing);
    expect(c.read(undoControllerProvider), isNull);
    expect(undoCount, 0);
  });

  testWidgets('area outside the toast receives taps while visible',
      (tester) async {
    await pumpHost(tester);
    final toast = tester.getRect(find.byKey(const Key('bloom-undo-toast')));
    // Above the toast, and beside it in the 20dp gutter on the same row.
    await tester.tapAt(Offset(200, toast.top - 4));
    await tester.tapAt(Offset(10, toast.center.dy));
    await tester.tapAt(Offset(392, toast.center.dy));
    expect(backgroundTaps, 3);
    expect(find.byKey(const Key('bloom-undo-toast')), findsOneWidget);
  });

  testWidgets('undo still works', (tester) async {
    final c = await pumpHost(tester);
    await tester.tap(find.byKey(const Key('bloom-undo-button')));
    await tester.pumpAndSettle();
    expect(undoCount, 1);
    expect(c.read(undoControllerProvider), isNull);
  });

  testWidgets('theme snackbars show a close icon and dismiss', (tester) async {
    for (final theme in [
      AppTheme.light(),
      AppTheme.dark(),
      AppTheme.bloomLight(),
      AppTheme.bloomDark(),
    ]) {
      expect(theme.snackBarTheme.showCloseIcon, isTrue);
      expect(theme.snackBarTheme.dismissDirection, isNotNull);
    }
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.bloomLight(),
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: const Text('Saved'),
                  action: SnackBarAction(label: 'Undo', onPressed: () {}),
                ),
              ),
              child: const Text('go'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.close), findsOneWidget);
    await tester.tap(find.byIcon(Icons.close));
    await tester.pumpAndSettle();
    expect(find.text('Saved'), findsNothing);
  });
}
