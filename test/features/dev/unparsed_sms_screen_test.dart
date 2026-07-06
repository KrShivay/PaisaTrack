import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paisatrack/data/db/database.dart';
import 'package:paisatrack/data/db/database_provider.dart';
import 'package:paisatrack/features/dev/unparsed_sms_screen.dart';

void main() {
  late AppDatabase database;

  setUp(() {
    database = AppDatabase(NativeDatabase.memory());
  });

  tearDown(() async {
    await database.close();
  });

  Future<void> pumpScreen(WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWith((ref) async => database),
        ],
        child: const MaterialApp(home: UnparsedSmsScreen()),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('shows an empty state with no unparsed sms', (tester) async {
    await pumpScreen(tester);

    expect(find.text('No unparsed messages'), findsOneWidget);

    // flutter_test disposes the widget tree (and drift's watch() stream)
    // before any tearDown/addTearDown callback runs, so close() must happen
    // here, before the test body returns, or drift's markAsClosed() schedules
    // a debounce Timer.run that outlives the test — see the comment in
    // drift's StreamQueryStore.markAsClosed.
    await database.close();
  });

  testWidgets('lists unprocessed raw sms and excludes processed ones',
      (tester) async {
    final now = DateTime.utc(2026, 7, 6, 9);

    await database.into(database.rawSms).insertOnConflictUpdate(
          RawSmsCompanion.insert(
            id: 'sms_unparsed',
            sender: 'AX-UNKNOWN',
            body: 'Some unrecognized bank message format',
            receivedAt: now,
            purgeAfter: now.add(const Duration(days: 30)),
          ),
        );
    await database.into(database.rawSms).insertOnConflictUpdate(
          RawSmsCompanion.insert(
            id: 'sms_parsed',
            sender: 'AX-SBIINB',
            body: 'Your a/c is debited',
            receivedAt: now,
            purgeAfter: now.add(const Duration(days: 30)),
            processed: const Value(true),
          ),
        );

    await pumpScreen(tester);

    expect(find.text('AX-UNKNOWN'), findsOneWidget);
    expect(
      find.text('Some unrecognized bank message format'),
      findsOneWidget,
    );
    expect(find.text('AX-SBIINB'), findsNothing);

    await database.close();
  });
}
