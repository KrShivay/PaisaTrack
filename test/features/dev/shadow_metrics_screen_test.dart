import 'package:drift/native.dart';
import 'package:drift/drift.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paisatrack/data/db/database.dart';
import 'package:paisatrack/features/dev/shadow_metrics_screen.dart';

void main() {
  late AppDatabase database;

  setUp(() {
    database = AppDatabase(NativeDatabase.memory());
  });

  tearDown(() async {
    await database.close();
  });

  test('repository loads local shadow and production counts', () async {
    await database.into(database.shadowTransactions).insert(
          ShadowTransactionsCompanion.insert(
            id: 'candidate-v1:sms_1',
            sourceId: 'sms_1',
            pipelineVersion: 'candidate-v1',
            outcome: 'parsed',
            amountPaise: const Value(44900),
            direction: const Value('debit'),
            observedAt: DateTime.utc(2026, 8, 7),
            updatedAt: DateTime.utc(2026, 8, 7),
          ),
        );

    final metrics = await ShadowMetricsRepository(database).load();

    expect(metrics.shadowRows, 1);
    expect(metrics.productionRows, 0);
    expect(metrics.gained, 1);
    expect(metrics.toJson(), isNot(contains('sms_1')));
  });

  testWidgets('renders metrics and explicit copy action', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          shadowMetricsProvider.overrideWith(
            (ref) async => const ShadowMetrics(
              shadowRows: 2,
              productionRows: 2,
              gained: 0,
              lost: 0,
              amountDeltas: 1,
              labelDisagreements: 0,
            ),
          ),
        ],
        child: const MaterialApp(home: ShadowMetricsScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Shadow metrics (dev)'), findsOneWidget);
    expect(find.text('Amount deltas'), findsOneWidget);
    expect(find.text('Copy local report'), findsOneWidget);
  });
}
