import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart' hide Column;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paisatrack/data/db/database.dart';
import 'package:paisatrack/data/db/database_provider.dart';
import 'package:paisatrack/data/repositories/transaction_repository.dart';
import 'package:paisatrack/data/models/normalized_transaction_record.dart';
import 'package:paisatrack/features/transactions/transaction_detail_screen.dart';
import 'package:paisatrack/features/transactions/transactions_providers.dart';
import 'package:paisatrack/features/transactions/transactions_screen.dart';

void main() {
  late AppDatabase database;
  late TransactionRepository repository;

  setUp(() async {
    database = AppDatabase(NativeDatabase.memory());
    repository = TransactionRepository(database);
    await database.into(database.categories).insertOnConflictUpdate(
          CategoriesCompanion.insert(
            id: 'food_dining',
            name: 'Food & Dining',
            icon: 'restaurant',
            isSpending: true,
            sortOrder: 10,
            isUserCreated: false,
          ),
        );
    await database.into(database.categories).insertOnConflictUpdate(
          CategoriesCompanion.insert(
            id: 'shopping',
            name: 'Shopping',
            icon: 'shopping_bag',
            isSpending: true,
            sortOrder: 20,
            isUserCreated: false,
          ),
        );
    final ts = DateTime.utc(2026, 7, 6, 9);
    await database.into(database.transactions).insertOnConflictUpdate(
          TransactionsCompanion.insert(
            id: 'txn_1',
            ts: ts.millisecondsSinceEpoch,
            amount: 449,
            direction: 'debit',
            channel: 'upi',
            merchantRaw: const Value('AMZN*MKTPLC'),
            counterpartyVpa: const Value('amazon@ybl'),
            accountHint: const Value('xx4521'),
            balanceAfter: const Value(12384.50),
            refId: const Value('615223847712'),
            categoryId: const Value('food_dining'),
            parseSource: 'template',
            confidenceJson: '{"parse":{"source":"template","confidence":0.97}}',
            status: 'auto',
            createdAt: ts,
            updatedAt: ts,
          ),
        );
  });

  tearDown(() async {
    await database.close();
  });

  group('repository.updateWithFeedback', () {
    test('writes one feedback row per changed field, atomically with the '
        'update', () async {
      final clockNow = DateTime.utc(2026, 7, 7, 15);

      final written = await repository.updateWithFeedback(
        txnId: 'txn_1',
        categoryId: const Value('shopping'),
        description: const Value('Books order'),
        clock: () => clockNow,
      );
      expect(written, 2);

      final txn = await (database.select(database.transactions)
            ..where((t) => t.id.equals('txn_1')))
          .getSingle();
      expect(txn.categoryId, 'shopping');
      expect(txn.description, 'Books order');
      expect(txn.updatedAt.toUtc(), clockNow);

      final feedbackRows = await database.select(database.feedback).get();
      expect(feedbackRows, hasLength(2));
      final byField = {for (final row in feedbackRows) row.field: row};

      final categoryFeedback = byField['category_id']!;
      expect(categoryFeedback.txnId, 'txn_1');
      expect(categoryFeedback.oldValue, 'food_dining');
      expect(categoryFeedback.newValue, 'shopping');
      expect(categoryFeedback.context, 'detail_edit');
      expect(categoryFeedback.modelConfidenceAtTime, 0.97);
      expect(categoryFeedback.createdAt.toUtc(), clockNow);

      final descriptionFeedback = byField['description']!;
      expect(descriptionFeedback.oldValue, isNull);
      expect(descriptionFeedback.newValue, 'Books order');
      expect(descriptionFeedback.context, 'detail_edit');
    });

    test('unchanged values write neither an update nor feedback', () async {
      final before = await (database.select(database.transactions)
            ..where((t) => t.id.equals('txn_1')))
          .getSingle();

      final written = await repository.updateWithFeedback(
        txnId: 'txn_1',
        categoryId: const Value('food_dining'),
        description: const Value(null),
      );
      expect(written, 0);

      final after = await (database.select(database.transactions)
            ..where((t) => t.id.equals('txn_1')))
          .getSingle();
      expect(after.updatedAt, before.updatedAt);
      expect(await database.select(database.feedback).get(), isEmpty);
    });

    test('a failing feedback insert rolls the whole edit back (atomicity)',
        () async {
      // Occupy the id the injected factory will produce for the *second*
      // staged field, so its insert throws after the update and the first
      // feedback insert have already executed inside the transaction.
      final now = DateTime.utc(2026, 7, 7, 16);
      await database.into(database.feedback).insert(
            FeedbackCompanion.insert(
              id: 'fb_conflict_description',
              txnId: 'txn_1',
              field: 'description',
              oldValue: const Value(null),
              newValue: const Value('occupied'),
              context: 'test_setup',
              createdAt: now,
            ),
          );

      await expectLater(
        repository.updateWithFeedback(
          txnId: 'txn_1',
          categoryId: const Value('shopping'),
          description: const Value('Books order'),
          feedbackIdFactory: (field) => 'fb_conflict_$field',
        ),
        throwsA(anything),
      );

      // The update and the category feedback row must have rolled back too.
      final txn = await (database.select(database.transactions)
            ..where((t) => t.id.equals('txn_1')))
          .getSingle();
      expect(txn.categoryId, 'food_dining');
      expect(txn.description, isNull);

      final feedbackRows = await database.select(database.feedback).get();
      expect(feedbackRows, hasLength(1));
      expect(feedbackRows.single.context, 'test_setup');
    });
  });

  group('detail screen', () {
    Future<void> pumpDetail(WidgetTester tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            appDatabaseProvider.overrideWith((ref) async => database),
          ],
          child: const MaterialApp(
            home: TransactionDetailScreen(txnId: 'txn_1'),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();
      await tester.pump();
    }

    testWidgets('renders the frozen-contract fields and confidence trail '
        'placeholder', (tester) async {
      await pumpDetail(tester);

      expect(find.text('-₹449.00'), findsOneWidget);
      expect(find.text('AMZN*MKTPLC'), findsOneWidget);
      expect(find.text('amazon@ybl'), findsOneWidget);
      expect(find.text('xx4521'), findsOneWidget);
      expect(find.text('₹12,384.50'), findsOneWidget);
      expect(find.text('615223847712'), findsOneWidget);
      expect(find.text('auto'), findsOneWidget);
      expect(find.text('Confidence trail'), findsOneWidget);
      expect(find.text('template'), findsOneWidget);
      expect(find.text('0.97'), findsOneWidget);
      expect(find.text('Food & Dining'), findsOneWidget);
    });

    testWidgets('editing category and description saves and writes feedback',
        (tester) async {
      await pumpDetail(tester);

      await tester.tap(find.text('Food & Dining'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Shopping').last);
      await tester.pumpAndSettle();

      await tester.enterText(
        find.widgetWithText(TextFormField, 'Description'),
        'Books order',
      );

      await tester.ensureVisible(find.text('Save changes'));
      await tester.tap(find.text('Save changes'));
      await tester.pumpAndSettle();

      final txn = await (database.select(database.transactions)
            ..where((t) => t.id.equals('txn_1')))
          .getSingle();
      expect(txn.categoryId, 'shopping');
      expect(txn.description, 'Books order');

      final feedbackRows = await database.select(database.feedback).get();
      expect(feedbackRows, hasLength(2));
      expect(
        feedbackRows.map((row) => row.context).toSet(),
        {'detail_edit'},
      );
    });

    testWidgets('tapping a transactions list row opens the detail screen',
        (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            appDatabaseProvider.overrideWith((ref) async => database),
            transactionListProvider.overrideWith(
              (ref) => Stream.value([
                TransactionListItem(
                  id: 'txn_1',
                  ts: DateTime.utc(2026, 7, 6, 9),
                  amount: 449,
                  direction: TransactionDirection.debit,
                  displayName: 'AMZN*MKTPLC',
                  categoryName: 'Food & Dining',
                  categoryId: 'food_dining',
                  categoryIcon: 'restaurant',
                ),
              ]),
            ),
          ],
          child: const MaterialApp(home: TransactionsScreen()),
        ),
      );
      await tester.pump();
      await tester.pump();

      await tester.tap(find.text('AMZN*MKTPLC'));
      await tester.pumpAndSettle();

      expect(find.byType(TransactionDetailScreen), findsOneWidget);
      expect(find.text('-₹449.00'), findsOneWidget);
    });
  });
}
