// ignore_for_file: unused_import

@Skip('Scratch debug test; covered by dashboard_screen_test.dart.')
library;

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paisatrack/data/db/database.dart';
import 'package:paisatrack/data/db/database_provider.dart';
import 'package:paisatrack/features/dashboard/dashboard_screen.dart';

Future<void> _seed(AppDatabase database) async {
  final now = DateTime.now().toUtc();
  await database.into(database.transactions).insertOnConflictUpdate(
        TransactionsCompanion.insert(
          id: 'debit_1',
          ts: now.millisecondsSinceEpoch,
          amount: 150,
          direction: 'debit',
          channel: 'upi',
          parseSource: 'template',
          confidenceJson: '{}',
          status: 'auto',
          createdAt: now,
          updatedAt: now,
        ),
      );
}

Future<void> _pump(WidgetTester tester, AppDatabase database) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [appDatabaseProvider.overrideWith((ref) async => database)],
      child: const MaterialApp(home: DashboardScreen()),
    ),
  );
  await tester.pumpAndSettle();
  expect(find.text('Spent'), findsOneWidget);
}

void main() {
  testWidgets('V1 unmount + pump(100ms), no close', (tester) async {
    final database = AppDatabase(NativeDatabase.memory());
    addTearDown(() async => tester.runAsync(database.close));
    await _seed(database);
    await _pump(tester, database);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 100));
  });

  testWidgets('V2 unmount + pump(100ms) + fake-zone close', (tester) async {
    final database = AppDatabase(NativeDatabase.memory());
    await _seed(database);
    await _pump(tester, database);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 100));
    await database.close();
  });
}
