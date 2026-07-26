import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paisatrack/data/db/database.dart';
import 'package:paisatrack/data/db/database_provider.dart';
import 'package:paisatrack/features/transactions/transaction_correction_sheet.dart';
import 'package:paisatrack/features/transactions/transaction_detail_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  /// Seeds an in-memory database with a single Swiggy debit transaction.
  Future<AppDatabase> seedDatabase() async {
    final database = AppDatabase(NativeDatabase.memory());
    final now = DateTime.utc(2026, 7, 26);

    await database.into(database.categories).insert(
          CategoriesCompanion.insert(
            id: 'food_cat',
            name: 'Food & Dining',
            icon: 'food',
            isSpending: true,
            sortOrder: 1,
            isUserCreated: false,
          ),
        );

    await database.into(database.merchants).insert(
          MerchantsCompanion.insert(
            id: 'm_swiggy',
            canonicalName: 'Swiggy',
            firstSeen: now,
            lastSeen: now,
          ),
        );

    await database.into(database.transactions).insert(
          TransactionsCompanion.insert(
            id: 'txn_001',
            ts: now.millisecondsSinceEpoch,
            amount: 450.0,
            direction: 'debit',
            channel: 'UPI',
            status: 'needs_review',
            merchantId: const Value('m_swiggy'),
            merchantRaw: const Value('Swiggy'),
            refId: const Value('REF123456'),
            counterpartyVpa: const Value('swiggy@icici'),
            balanceAfter: const Value(12500.0),
            categoryId: const Value('food_cat'),
            parseSource: 'template',
            confidenceJson: '{"parser":{"c":0.74,"src":"template"}}',
            createdAt: now,
            updatedAt: now,
          ),
        );

    return database;
  }

  /// Pumps the TransactionDetailScreen with enough cycles for the
  /// FutureProvider→StreamProvider chain to fully resolve.
  Future<void> pumpDetail(WidgetTester tester, AppDatabase database) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWith((ref) async => database),
        ],
        child: const MaterialApp(
          home: TransactionDetailScreen(txnId: 'txn_001'),
        ),
      ),
    );
    // FutureProvider (appDatabaseProvider) → StreamProvider.family
    // (transactionDetailProvider) needs multiple pump cycles.
    for (int i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  testWidgets('TransactionDetailScreen renders header, merchant, and category',
      (tester) async {
    final database = await seedDatabase();

    await pumpDetail(tester, database);

    expect(find.text('Transaction Detail'), findsOneWidget);
    expect(find.text('Swiggy'), findsOneWidget);
    expect(find.text('Food & Dining'), findsOneWidget);
    expect(find.textContaining('450'), findsOneWidget);

    await database.close();
  });

  testWidgets('TransactionDetailScreen note editing persists to database',
      (tester) async {
    final database = await seedDatabase();

    await pumpDetail(tester, database);

    // Find the note TextField and Save Note button.
    final noteField = find.byType(TextField).first;
    final saveNoteBtn = find.text('Save Note');

    expect(saveNoteBtn, findsOneWidget);

    await tester.ensureVisible(noteField);
    await tester.enterText(noteField, 'Lunch with team');
    await tester.ensureVisible(saveNoteBtn);
    await tester.tap(saveNoteBtn);
    for (int i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    // Verify the note was persisted to the database.
    final updatedTxn = await (database.select(database.transactions)
          ..where((t) => t.id.equals('txn_001')))
        .getSingle();
    expect(updatedTxn.description, equals('Lunch with team'));

    await database.close();
  });

  testWidgets('TransactionDetailScreen shows evidence disclosure',
      (tester) async {
    final database = await seedDatabase();

    await pumpDetail(tester, database);

    // Technical details toggle should be present.
    expect(find.textContaining('Technical details'), findsOneWidget);

    // Parse correction launcher should exist.
    expect(find.textContaining('Edit Parse Details'), findsOneWidget);

    // Suggested category confirm/fix banner.
    expect(find.text('Confirm'), findsOneWidget);
    expect(find.text('Fix Details'), findsOneWidget);

    await database.close();
  });

  testWidgets('TransactionCorrectionSheet renders form elements',
      (tester) async {
    final database = await seedDatabase();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWith((ref) async => database),
        ],
        child: const MaterialApp(
          home: Scaffold(
            body: TransactionCorrectionSheet(
              txnId: 'txn_001',
              initialAmount: 450.0,
              initialDirection: 'debit',
              initialMerchant: 'Swiggy',
            ),
          ),
        ),
      ),
    );
    for (int i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    expect(find.text('Correct Transaction Parse'), findsOneWidget);
    expect(find.text('Save Correction'), findsOneWidget);

    await database.close();
  });
}
