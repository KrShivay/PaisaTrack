import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paisatrack/core/widgets/bloom/bloom.dart';
import 'package:paisatrack/data/db/database.dart';
import 'package:paisatrack/data/db/database_provider.dart';
import 'package:paisatrack/data/models/transaction_confidence_trail.dart';
import 'package:paisatrack/data/repositories/transaction_repository.dart';
import 'package:paisatrack/features/transactions/transaction_detail_screen.dart';
import 'package:paisatrack/features/transactions/transactions_providers.dart';

final _detail = TransactionDetail(
  txn: Transaction(
    id: 'txn_keyboard',
    ts: DateTime.utc(2026, 7, 6, 9).millisecondsSinceEpoch,
    amount: 449,
    direction: 'debit',
    channel: 'upi',
    categoryId: 'food_dining',
    description: 'Original note',
    merchantRaw: 'Swiggy',
    parseSource: 'template',
    confidenceJson: '{}',
    status: 'confirmed',
    isDeleted: false,
    isNotTransaction: false,
    isAnalyticsExcluded: false,
    lifecycleState: 'settled',
    createdAt: DateTime.utc(2026, 7, 6, 9),
    updatedAt: DateTime.utc(2026, 7, 6, 9),
  ),
  merchantName: 'Swiggy',
  categoryName: 'Food & Dining',
  parseConfidence: 0.98,
  confidenceTrail: TransactionConfidenceTrail.fromJson('{}'),
  isLowTrustParse: false,
);

Future<AppDatabase> _seedDatabase() async {
  final database = AppDatabase(NativeDatabase.memory());
  final now = DateTime.utc(2026, 7, 6, 9);
  await database.into(database.categories).insert(
        CategoriesCompanion.insert(
          id: 'food_dining',
          name: 'Food & Dining',
          icon: 'restaurant',
          isSpending: true,
          sortOrder: 1,
          isUserCreated: false,
        ),
      );
  await database.into(database.transactions).insert(
        TransactionsCompanion.insert(
          id: 'txn_keyboard',
          ts: now.millisecondsSinceEpoch,
          amount: 449,
          direction: 'debit',
          channel: 'upi',
          categoryId: const Value('food_dining'),
          description: const Value('Original note'),
          merchantRaw: const Value('Swiggy'),
          parseSource: 'template',
          confidenceJson: '{}',
          status: 'confirmed',
          createdAt: now,
          updatedAt: now,
        ),
      );
  return database;
}

Future<ProviderContainer> _pumpLauncher(
  WidgetTester tester,
  AppDatabase? database, {
  required bool fullScreen,
  required double textScale,
  Size size = const Size(402, 874),
  TransactionDetail? detail,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  tester.view.viewInsets = const FakeViewPadding();
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
    tester.view.resetViewInsets();
  });

  final container = ProviderContainer(
    overrides: [
      if (database != null)
        appDatabaseProvider.overrideWith((ref) async => database),
      transactionDetailProvider('txn_keyboard')
          .overrideWith((ref) => Stream.value(detail ?? _detail)),
      categoryListProvider.overrideWith((ref) => Stream.value([])),
      suggestedCategoriesProvider('txn_keyboard')
          .overrideWith((ref) async => const <String>[]),
    ],
  );
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            disableAnimations: true,
            textScaler: TextScaler.linear(textScale),
          ),
          child: child!,
        ),
        home: Scaffold(
          body: Center(
            child: Builder(
              builder: (context) => FilledButton(
                key: const Key('open-detail'),
                onPressed: () {
                  if (fullScreen) {
                    showBloomFullScreenSheet<void>(
                      context: context,
                      showClose: true,
                      builder: (_) =>
                          const TransactionDetailScreen(txnId: 'txn_keyboard'),
                    );
                  } else {
                    showBloomModalSheet<void>(
                      context: context,
                      isScrollControlled: true,
                      builder: (_) =>
                          const TransactionDetailScreen(txnId: 'txn_keyboard'),
                    );
                  }
                },
                child: const Text('Open detail'),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
  return container;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final fullScreen in [false, true]) {
    final presentation = fullScreen ? 'full-screen sheet' : 'modal sheet';
    for (final scale in [1.0, 1.5, 2.0]) {
      testWidgets(
        'T-186 $presentation keeps detail usable with keyboard at ${scale}x text',
        (tester) async {
          final container = await _pumpLauncher(
            tester,
            null,
            fullScreen: fullScreen,
            textScale: scale,
          );
          addTearDown(container.dispose);

          await tester.tap(find.byKey(const Key('open-detail')));
          await tester.pumpAndSettle();
          expect(find.text('Swiggy'), findsOneWidget);

          final noteField = find.byType(TextField);
          await tester.tap(noteField);
          await tester.pump();
          tester.view.viewInsets = const FakeViewPadding(bottom: 320);
          await tester.pump(const Duration(milliseconds: 300));

          final detail = find.byType(TransactionDetailScreen);
          final detailScaffold = find.descendant(
            of: detail,
            matching: find.byType(Scaffold),
          );
          final scrollView = find.descendant(
            of: detail,
            matching: find.byType(SingleChildScrollView),
          );
          expect(tester.getSize(detailScaffold).height, greaterThan(400));
          expect(tester.getSize(scrollView.first).height, greaterThan(300));
          expect(find.text('Swiggy'), findsOneWidget);

          final saveButton = find.widgetWithText(TextButton, 'Save Note');
          await tester.ensureVisible(saveButton);
          expect(tester.getRect(saveButton).bottom, lessThanOrEqualTo(554));
        },
      );
    }
  }

  // Production callers present transaction detail only in one of these sheets;
  // keep this persistence path keyboard-visible to cover the actual route.
  testWidgets(
      'T-186 sheet saves with keyboard open and restores note on reopen',
      (tester) async {
    final database = await _seedDatabase();
    final container = await _pumpLauncher(
      tester,
      database,
      fullScreen: false,
      textScale: 1,
    );

    await tester.tap(find.byKey(const Key('open-detail')));
    await tester.pumpAndSettle();
    final noteField = find.byType(TextField);
    await tester.enterText(noteField, 'Work lunch refund');
    tester.view.viewInsets = const FakeViewPadding(bottom: 320);
    await tester.pump(const Duration(milliseconds: 300));
    final saveButton = find.widgetWithText(TextButton, 'Save Note');
    await tester.ensureVisible(saveButton);
    expect(tester.getRect(saveButton).bottom, lessThanOrEqualTo(554));
    await tester.tap(saveButton);
    await tester.pumpAndSettle();

    final saved = await tester.runAsync(
      () => (database.select(database.transactions)
            ..where((row) => row.id.equals('txn_keyboard')))
          .getSingle(),
    );
    expect(saved?.description, 'Work lunch refund');
    final reopenedDetail = await tester.runAsync(
      () => TransactionRepository(database).watchDetail('txn_keyboard').first,
    );
    expect(reopenedDetail?.txn.description, 'Work lunch refund');

    Navigator.of(tester.element(find.byType(TransactionDetailScreen))).pop();
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    container.dispose();
    final reopenedContainer = await _pumpLauncher(
      tester,
      database,
      fullScreen: false,
      textScale: 1,
      detail: reopenedDetail,
    );
    await tester.tap(find.byKey(const Key('open-detail')));
    await tester.pumpAndSettle();
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      'Work lunch refund',
    );
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    reopenedContainer.dispose();
  });

  for (final size in [const Size(320, 568), const Size(600, 900)]) {
    for (final scale in [1.5, 2.0]) {
      testWidgets(
          'full-screen detail fits ${size.width.toInt()}px at $scale× text',
          (tester) async {
        final container = await _pumpLauncher(
          tester,
          null,
          fullScreen: true,
          textScale: scale,
          size: size,
        );
        addTearDown(() async {
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pump();
          container.dispose();
        });

        await tester.tap(find.byKey(const Key('open-detail')));
        await tester.pumpAndSettle();

        expect(find.text('Swiggy'), findsWidgets);
        expect(find.text('Save Note'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  }
}
