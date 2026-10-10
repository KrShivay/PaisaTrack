import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paisatrack/core/undo/undo_controller.dart';
import 'package:paisatrack/core/widgets/bloom/bloom_bottom_inset.dart';
import 'package:paisatrack/core/widgets/bloom/bloom_sheet.dart';
import 'package:paisatrack/core/widgets/bloom/bloom_sheet_scaffold.dart';
import 'package:paisatrack/core/widgets/bloom/bloom_undo_toast.dart';
import 'package:paisatrack/data/db/database.dart';
import 'package:paisatrack/data/db/database_provider.dart';
import 'package:paisatrack/features/home/home_shell.dart';
import 'package:paisatrack/features/transactions/transaction_correction_sheet.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<BloomUndoToastRouteObserver> pumpApp(
    WidgetTester tester, {
    bool openCorrectionSheet = false,
    bool openFullScreenSheet = false,
    bool openDialog = false,
    bool pushPopSameFrame = false,
  }) async {
    tester.view.physicalSize = const Size(402, 874);
    tester.view.devicePixelRatio = 1;
    tester.view.padding = const FakeViewPadding(bottom: 24);
    tester.view.viewPadding = const FakeViewPadding(bottom: 24);
    tester.view.viewInsets = const FakeViewPadding();
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
      tester.view.resetPadding();
      tester.view.resetViewPadding();
      tester.view.resetViewInsets();
    });

    final routeObserver = BloomUndoToastRouteObserver();
    final navigatorKey = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWith(
            (ref) => Completer<AppDatabase>().future,
          ),
        ],
        child: MaterialApp(
          navigatorKey: navigatorKey,
          navigatorObservers: [routeObserver],
          builder: (context, child) => buildBloomUndoToastAppBuilder(
            context,
            Stack(
              fit: StackFit.expand,
              children: [
                child!,
                Positioned(
                  top: 8,
                  left: 8,
                  child: Material(
                    child: Builder(
                      builder: (context) => FilledButton(
                        onPressed: () {
                          if (openDialog) {
                            showDialog<void>(
                              context: navigatorKey.currentContext!,
                              builder: (context) => AlertDialog(
                                title: const Text('Blocking dialog'),
                                actions: [
                                  TextButton(
                                    onPressed: () => Navigator.pop(context),
                                    child: const Text('Close dialog'),
                                  ),
                                ],
                              ),
                            );
                            return;
                          }
                          if (openCorrectionSheet) {
                            showBloomModalSheet<void>(
                              context: navigatorKey.currentContext!,
                              builder: (_) => const TransactionCorrectionSheet(
                                txnId: 'synthetic-undo-toast',
                                initialAmount: 120,
                                initialDirection: 'debit',
                              ),
                            );
                            return;
                          }
                          if (openFullScreenSheet) {
                            showBloomFullScreenSheet<void>(
                              context: navigatorKey.currentContext!,
                              title: 'Full screen sheet',
                              builder: (_) => const Text('Full screen content'),
                            );
                            return;
                          }
                          final navigator = navigatorKey.currentState!;
                          navigator.push<void>(
                            MaterialPageRoute<void>(
                              builder: (_) => Scaffold(
                                body: const Center(child: Text('Detail route')),
                                bottomNavigationBar: SafeArea(
                                  child: Padding(
                                    padding: const EdgeInsets.all(20),
                                    child: FilledButton(
                                      onPressed: () {},
                                      child: const Text('Save Note'),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          );
                          if (pushPopSameFrame) navigator.pop();
                        },
                        child: const Text('Open detail'),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            routeObserver: routeObserver,
            homeNavigationVisible: true,
          ),
          home: const HomeShell(),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    return routeObserver;
  }

  testWidgets('same-frame push and pop settles on the current route state',
      (tester) async {
    final routeObserver = await pumpApp(tester, pushPopSameFrame: true);
    await tester.tap(find.text('Open detail'));
    await tester.pump();

    expect(routeObserver.hasPushedRoute.value, isFalse);
  });

  testWidgets('root host shows one tappable undo above a pushed route',
      (tester) async {
    await pumpApp(tester);
    await tester.tap(find.text('Open detail'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    await tester.pump();

    var didUndo = false;
    final context = tester.element(find.text('Detail route'));
    ProviderScope.containerOf(context)
        .read(undoControllerProvider.notifier)
        .pushUndo(
          UndoToken(
            id: 'detail-action',
            message: 'Currency updated',
            undoAction: () async => didUndo = true,
          ),
        );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.text('Currency updated'), findsOneWidget);
    expect(find.text('Undo'), findsOneWidget);
    expect(
      tester.getSize(find.byKey(const Key('bloom-undo-button'))).height,
      greaterThanOrEqualTo(48),
    );
    final toast = find.text('Currency updated');
    final footer = find.text('Save Note');
    expect(tester.getRect(toast).bottom, lessThan(tester.getRect(footer).top));
    expect(
      tester.getRect(find.byKey(const Key('bloom-undo-toast'))).bottom,
      lessThanOrEqualTo(874 - 300),
    );
    expect(
      tester
          .getSemantics(toast)
          .getSemanticsData()
          .flagsCollection
          .isLiveRegion,
      isTrue,
    );

    await tester.tap(find.text('Undo'));
    await tester.pump();
    expect(didUndo, isTrue);
    expect(find.text('Undo'), findsNothing);
  });

  testWidgets('toast clears the production correction sheet save action',
      (tester) async {
    await pumpApp(tester, openCorrectionSheet: true);
    await tester.tap(find.text('Open detail'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    final context = tester.element(find.text('Save Correction'));
    ProviderScope.containerOf(context)
        .read(undoControllerProvider.notifier)
        .pushUndo(
          UndoToken(
            id: 'correction-action',
            message: 'Correction applied',
            undoAction: () async {},
          ),
        );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    final save = find.text('Save Correction');
    final toast = find.byKey(const Key('bloom-undo-toast'));
    expect(save, findsOneWidget);
    expect(tester.getRect(toast).bottom, lessThan(tester.getRect(save).top));
  });

  testWidgets('toast remains visible above a full-screen Bloom sheet',
      (tester) async {
    await pumpApp(tester, openFullScreenSheet: true);
    final context = tester.element(find.text('Open detail'));
    ProviderScope.containerOf(context)
        .read(undoControllerProvider.notifier)
        .pushUndo(
          UndoToken(
            id: 'full-screen-sheet-action',
            message: 'Full-screen action',
            undoAction: () async {},
          ),
        );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    await tester.tap(find.text('Open detail'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Full screen content'), findsOneWidget);
    expect(find.text('Undo'), findsOneWidget);
  });

  testWidgets('toast hides for dialogs and returns while its token is live',
      (tester) async {
    final routeObserver = await pumpApp(tester, openDialog: true);
    var didUndo = false;
    final homeContext = tester.element(find.text('Open detail'));
    ProviderScope.containerOf(homeContext)
        .read(undoControllerProvider.notifier)
        .pushUndo(
          UndoToken(
            id: 'dialog-action',
            message: 'Dialog action',
            undoAction: () async => didUndo = true,
          ),
        );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text('Undo'), findsOneWidget);

    await tester.tap(find.text('Open detail'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Blocking dialog'), findsOneWidget);
    expect(find.text('Undo'), findsNothing);

    await tester.tap(find.text('Close dialog'));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));
    expect(routeObserver.hasBlockingPopupRoute.value, isFalse);
    expect(find.text('Undo'), findsOneWidget);

    await tester.tap(find.text('Undo'));
    await tester.pump();
    expect(didUndo, isTrue);
  });

  testWidgets('home offset is unchanged and repeated pushes render one toast',
      (tester) async {
    await pumpApp(tester);
    final container = ProviderScope.containerOf(
      tester.element(find.text('Open detail')),
    );
    container.read(undoControllerProvider.notifier)
      ..pushUndo(
        UndoToken(
          id: 'first',
          message: 'First action',
          undoAction: () async {},
        ),
      )
      ..pushUndo(
        UndoToken(
          id: 'second',
          message: 'Second action',
          undoAction: () async {},
        ),
      );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    const expectedBottom =
        874 - (24 + kBottomNavHeight + kBottomNavBottomGap + 8);
    final pill = find.byType(HomeFloatingNavPill);
    expect(
      tester.getRect(find.byKey(const Key('bloom-undo-toast'))).bottom,
      expectedBottom,
    );
    expect(
      tester.getRect(find.byKey(const Key('bloom-undo-toast'))).bottom,
      lessThan(tester.getRect(pill).top),
    );
    expect(find.text('Second action'), findsOneWidget);
    expect(find.text('Undo'), findsOneWidget);
    expect(find.text('First action'), findsNothing);
  });

  testWidgets('toast expires after six seconds', (tester) async {
    await pumpApp(tester);
    final container = ProviderScope.containerOf(
      tester.element(find.text('Open detail')),
    );
    container.read(undoControllerProvider.notifier).pushUndo(
          UndoToken(
            id: 'expires',
            message: 'Temporary action',
            undoAction: () async {},
          ),
        );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text('Undo'), findsOneWidget);

    await tester.pump(const Duration(seconds: 6));
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text('Undo'), findsNothing);
  });
}
