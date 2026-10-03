import 'dart:async';
import 'dart:typed_data';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paisatrack/data/db/database.dart';
import 'package:paisatrack/core/undo/undo_controller.dart';
import 'package:paisatrack/data/db/database_provider.dart';
import 'package:paisatrack/data/models/normalized_transaction_record.dart';
import 'package:paisatrack/data/repositories/rule_repository.dart';
import 'package:paisatrack/enrichment/categorizer.dart';
import 'package:paisatrack/enrichment/seed_category_map.dart';
import 'package:paisatrack/features/review/weekly_review_screen.dart';
import 'package:paisatrack/features/settings/app_settings.dart';

import '../../support/drift_widget_teardown.dart';

class _FakeAppSettingsController extends AppSettingsController {
  @override
  Future<AppSettings> build() async => const AppSettings();
}

/// The real rule-first categorizer, held until the test releases it so the
/// "guess is updating" state can be observed.
class _GatedCategorizer implements Categorizer {
  _GatedCategorizer(AppDatabase database)
      : _inner = Categorizer(
          rules: RuleRepository(database),
          seedMap: SeedCategoryMap(const {}),
        );

  final Categorizer _inner;
  Completer<void> gate = Completer<void>()..complete();
  bool fail = false;

  @override
  Future<CategorizationResult> categorize(
    NormalizedTransactionRecord record, {
    String? merchantId,
    Float32List? merchantEmbedding,
  }) async {
    await gate.future;
    if (fail) throw StateError('synthetic categorizer failure');
    return _inner.categorize(record, merchantId: merchantId);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<AppDatabase> seed() async {
    final database = AppDatabase(NativeDatabase.memory());
    for (final (id, name) in [
      ('food_delivery', 'Food Delivery'),
      ('transport_cab_auto', 'Cab & Auto'),
      ('transfers', 'Transfers'),
    ]) {
      await database.into(database.categories).insert(
            CategoriesCompanion.insert(
              id: id,
              name: name,
              icon: 'category',
              isSpending: id != 'transfers',
              sortOrder: 1,
              isUserCreated: false,
            ),
          );
    }
    final now = DateTime.utc(2026, 10, 1, 9);
    // A user-taught rule decides the corrected payee deterministically.
    await database.into(database.rules).insert(
          RulesCompanion.insert(
            id: 'rule_uber',
            matchType: 'merchant',
            matchValue: 'UBER',
            setCategoryId: const Value('transport_cab_auto'),
            createdAt: now,
          ),
        );
    await database.into(database.transactions).insert(
          TransactionsCompanion.insert(
            id: 'txn_sort',
            ts: now.millisecondsSinceEpoch,
            amount: 230,
            direction: 'debit',
            channel: 'upi',
            merchantRaw: const Value('SWIGGY'),
            // The guess was computed for the misparsed payee.
            categoryId: const Value('food_delivery'),
            parseSource: 'template',
            confidenceJson: '{}',
            status: 'needs_review',
            createdAt: now,
            updatedAt: now,
          ),
        );
    return database;
  }

  Future<void> pumpSort(
    WidgetTester tester,
    AppDatabase database,
    Categorizer categorizer,
  ) async {
    tester.view.physicalSize = const Size(402, 874);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWith((ref) async => database),
          categorizerProvider.overrideWith((ref) async => categorizer),
          appSettingsControllerProvider
              .overrideWith(_FakeAppSettingsController.new),
        ],
        child: const MaterialApp(home: WeeklyReviewScreen()),
      ),
    );
    await pumpDriftFrames(tester);
  }

  Future<Transaction> stored(AppDatabase database) =>
      (database.select(database.transactions)
            ..where((row) => row.id.equals('txn_sort')))
          .getSingle();

  Future<void> correctPayee(WidgetTester tester, String payee) async {
    await tester.tap(find.text('Not right?'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Wrong payee or amount'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, payee);
    await tester.tap(find.text('Save Correction'));
    await pumpDriftFrames(tester);
    await tester.pumpAndSettle();
  }

  bool keepEnabled(WidgetTester tester) => tester
      .widget<Semantics>(find.bySemanticsLabel('Keep').first)
      .properties
      .enabled!;

  testWidgets(
      'T-154b correcting the payee refreshes the guess before Keep and '
      'teaches nothing from the stale guess', (tester) async {
    final database = await seed();
    final categorizer = _GatedCategorizer(database);
    await pumpSort(tester, database, categorizer);
    expect(find.textContaining('Food Delivery'), findsOneWidget);

    categorizer.gate = Completer<void>();
    await correctPayee(tester, 'UBER');

    // Keep is disabled while the guess is recomputed for the new payee.
    expect(find.text('Updating guess…'), findsOneWidget);
    final keep = find.bySemanticsLabel('Keep');
    expect(keepEnabled(tester), isFalse);

    // Keep does nothing while disabled.
    await tester.tap(keep.first, warnIfMissed: false);
    await pumpDriftFrames(tester);
    expect((await stored(database)).status, 'needs_review');

    categorizer.gate.complete();
    await pumpDriftFrames(tester);
    await tester.pumpAndSettle();
    expect(find.text('Updating guess…'), findsNothing);
    expect(find.textContaining('Cab & Auto'), findsOneWidget);
    expect(find.text('Guess updated for the corrected payee'), findsOneWidget);

    await tester.tap(keep.first);
    await pumpDriftFrames(tester);

    final txn = await stored(database);
    expect(txn.status, 'confirmed');
    expect(txn.merchantRaw, 'UBER');
    expect(txn.categoryId, 'transport_cab_auto');
    final rules = await database.select(database.rules).get();
    expect(rules.map((rule) => rule.id), ['rule_uber']);
    final categoryFeedback = await (database.select(database.feedback)
          ..where((row) => row.field.equals('category_id')))
        .get();
    expect(categoryFeedback, isEmpty);

    await unmountAndCloseDatabase(tester, database);
  });

  testWidgets('T-154b "Not a spend" files the row under Transfers',
      (tester) async {
    final database = await seed();
    await pumpSort(tester, database, _GatedCategorizer(database));

    await tester.tap(find.text('Not right?'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Not a spend (transfer or refund)'));
    await pumpDriftFrames(tester);

    final txn = await stored(database);
    expect(txn.categoryId, 'transfers');
    await unmountAndCloseDatabase(tester, database);
  });

  testWidgets('T-154b Undo of a quick correction restores the refreshed guess',
      (tester) async {
    final database = await seed();
    await pumpSort(tester, database, _GatedCategorizer(database));
    await correctPayee(tester, 'UBER');
    expect(find.textContaining('Cab & Auto'), findsOneWidget);

    await tester.tap(find.text('Not right?'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Not a spend (transfer or refund)'));
    await pumpDriftFrames(tester);
    expect((await stored(database)).categoryId, 'transfers');

    final container = ProviderScope.containerOf(
      tester.element(find.byType(WeeklyReviewScreen)),
    );
    await container.read(undoControllerProvider.notifier).undo();
    await pumpDriftFrames(tester);
    expect(find.text('Guess updated for the corrected payee'), findsOneWidget);

    await tester.tap(find.bySemanticsLabel('Keep').first);
    await pumpDriftFrames(tester);
    final txn = await stored(database);
    expect(txn.categoryId, 'transport_cab_auto');
    expect(txn.status, 'confirmed');
    await tester.pump(const Duration(seconds: 11));
    await unmountAndCloseDatabase(tester, database);
  });

  testWidgets('T-154b a failed guess refresh keeps Keep disabled',
      (tester) async {
    final database = await seed();
    final categorizer = _GatedCategorizer(database)..fail = true;
    await pumpSort(tester, database, categorizer);
    await correctPayee(tester, 'UBER');

    expect(
      find.text("Couldn't update the guess. Choose a category."),
      findsOneWidget,
    );
    expect(keepEnabled(tester), isFalse);
    await tester.tap(find.bySemanticsLabel('Keep').first, warnIfMissed: false);
    await pumpDriftFrames(tester);
    expect((await stored(database)).status, 'needs_review');
    await unmountAndCloseDatabase(tester, database);
  });
}
