import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paisatrack/data/db/database.dart';
import 'package:paisatrack/features/dev/model_metrics_screen.dart';

Future<void> _insertTxn(
  AppDatabase database, {
  required String id,
  required String status,
  String categorySource = 'classifier',
}) {
  final now = DateTime.utc(2026, 7, 8);
  return database.into(database.transactions).insert(
        TransactionsCompanion.insert(
          id: id,
          ts: now.millisecondsSinceEpoch,
          amount: 100,
          direction: 'debit',
          channel: 'upi',
          parseSource: 'template',
          confidenceJson: '{"category":{"src":"$categorySource"}}',
          status: status,
          createdAt: now,
          updatedAt: now,
        ),
      );
}

Future<void> _insertFeedback(
  AppDatabase database, {
  required String id,
  required String txnId,
  required String field,
  String? oldValue,
  String? newValue,
  String context = 'weekly_review',
}) {
  return database.into(database.feedback).insert(
        FeedbackCompanion.insert(
          id: id,
          txnId: txnId,
          field: field,
          oldValue: Value(oldValue),
          newValue: Value(newValue),
          context: context,
          createdAt: DateTime.utc(2026, 7, 8),
        ),
      );
}

void main() {
  group('ModelMetricsRepository.load', () {
    late AppDatabase database;

    setUp(() async {
      database = AppDatabase(NativeDatabase.memory());
    });

    tearDown(() async {
      await database.close();
    });

    test('empty database reports zeroed metrics', () async {
      final metrics = await ModelMetricsRepository(database).load();
      expect(metrics.accuracy, 0);
      expect(metrics.askRate, 0);
      expect(metrics.correctionRates, isEmpty);
    });

    test(
        'computes accuracy from category corrections and ask rate from '
        'transaction status', () async {
      await _insertTxn(database, id: 'txn_1', status: 'confirmed');
      await _insertTxn(database, id: 'txn_2', status: 'asked');
      await _insertTxn(database, id: 'txn_3', status: 'auto');

      // txn_1's category feedback is a correction (old != new).
      await _insertFeedback(
        database,
        id: 'fb_1',
        txnId: 'txn_1',
        field: 'category_id',
        oldValue: 'other',
        newValue: 'food_dining',
      );
      // txn_2's category feedback confirms the guess (old == new).
      await _insertFeedback(
        database,
        id: 'fb_2',
        txnId: 'txn_2',
        field: 'category_id',
        oldValue: 'food_dining',
        newValue: 'food_dining',
        context: 'ask_now',
      );

      final metrics = await ModelMetricsRepository(database).load();

      expect(metrics.accuracy, closeTo(0.5, 1e-9));
      expect(metrics.askRate, closeTo(1 / 3, 1e-9));
      expect(metrics.correctionRates['other'], 1);
      expect(metrics.correctionRates['food_dining'], 0);
    });

    test('classifier accuracy excludes seed-map outcomes', () async {
      await _insertTxn(
        database,
        id: 'txn_seed',
        status: 'confirmed',
        categorySource: 'seed',
      );
      await _insertFeedback(
        database,
        id: 'fb_seed',
        txnId: 'txn_seed',
        field: 'category_id',
        oldValue: 'other',
        newValue: 'food_dining',
      );

      final metrics = await ModelMetricsRepository(database).load();

      expect(metrics.accuracy, 0);
      expect(metrics.correctionRates['other'], 1);
    });

    test('ask rate retains answered ask-now transactions', () async {
      await _insertTxn(database, id: 'txn_answered', status: 'confirmed');
      await _insertTxn(database, id: 'txn_auto', status: 'auto');
      await _insertFeedback(
        database,
        id: 'fb_answered',
        txnId: 'txn_answered',
        field: 'category_id',
        oldValue: 'other',
        newValue: 'food_dining',
        context: 'ask_now',
      );

      final metrics = await ModelMetricsRepository(database).load();

      expect(metrics.askRate, 0.5);
    });

    test('ignores feedback rows that are not category_id corrections',
        () async {
      await _insertTxn(database, id: 'txn_1', status: 'confirmed');
      await _insertFeedback(
        database,
        id: 'fb_status',
        txnId: 'txn_1',
        field: 'status',
        oldValue: 'asked',
        newValue: 'confirmed',
      );

      final metrics = await ModelMetricsRepository(database).load();

      expect(metrics.accuracy, 0);
      expect(metrics.correctionRates, isEmpty);
    });

    test('only considers the most recent 100 feedback rows', () async {
      for (var i = 0; i < 105; i++) {
        final id = 'txn_$i';
        await _insertTxn(database, id: id, status: 'confirmed');
        await database.into(database.feedback).insert(
              FeedbackCompanion.insert(
                id: 'fb_$i',
                txnId: id,
                field: 'category_id',
                oldValue: const Value('other'),
                // The first 5 (oldest) rows are corrections; make sure they
                // are excluded by the most-recent-100 window.
                newValue: Value(i < 5 ? 'food_dining' : 'other'),
                context: 'weekly_review',
                createdAt: DateTime.utc(2026, 7, 8).add(Duration(minutes: i)),
              ),
            );
      }

      final metrics = await ModelMetricsRepository(database).load();

      expect(metrics.accuracy, 1);
    });
  });

  group('ModelMetricsScreen', () {
    testWidgets('renders accuracy, ask rate, and per-category correction rates',
        (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            modelMetricsProvider.overrideWith(
              (ref) async => const ModelMetrics(
                accuracy: 0.842,
                askRate: 0.157,
                correctionRates: {'food_dining': 0.2},
              ),
            ),
          ],
          child: const MaterialApp(home: ModelMetricsScreen()),
        ),
      );
      await tester.pump();

      expect(find.text('Model metrics (dev)'), findsOneWidget);
      expect(find.text('84.2%'), findsOneWidget);
      expect(find.text('15.7%'), findsOneWidget);
      expect(find.text('food_dining correction rate'), findsOneWidget);
      expect(find.text('20.0%'), findsOneWidget);
    });

    testWidgets('shows an error state when metrics fail to load',
        (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            modelMetricsProvider.overrideWith(
              (ref) async => Future<ModelMetrics>.error('boom'),
            ),
          ],
          child: const MaterialApp(home: ModelMetricsScreen()),
        ),
      );
      await tester.pump();

      expect(find.text('Could not load model metrics'), findsOneWidget);
    });
  });
}
