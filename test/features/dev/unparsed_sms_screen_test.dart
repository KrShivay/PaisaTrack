import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paisatrack/data/db/database.dart';
import 'package:paisatrack/data/repositories/raw_sms_repository.dart';
import 'package:paisatrack/features/dev/unparsed_sms_providers.dart';
import 'package:paisatrack/features/dev/unparsed_sms_screen.dart';

void main() {
  Future<void> pumpScreen(
    WidgetTester tester,
    List<UnparsedSms> messages,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          unparsedSmsListProvider.overrideWith(
            (ref) => Stream.value(messages),
          ),
        ],
        child: const MaterialApp(home: UnparsedSmsScreen()),
      ),
    );
    await tester.pump();
    await tester.pump();
  }

  testWidgets('shows an empty state with no unparsed sms', (tester) async {
    await pumpScreen(tester, const []);

    expect(find.text('No unparsed messages'), findsOneWidget);
  });

  testWidgets('lists unprocessed raw sms rows', (tester) async {
    final now = DateTime.utc(2026, 7, 6, 9);

    await pumpScreen(tester, [
      UnparsedSms(
        id: 'sms_unparsed',
        sender: 'AX-UNKNOWN',
        body: 'Some unrecognized bank message format',
        receivedAt: now,
      ),
    ]);

    expect(find.text('AX-UNKNOWN'), findsOneWidget);
    expect(
      find.text('Some unrecognized bank message format'),
      findsOneWidget,
    );
  });

  test('repository lists unprocessed raw sms and excludes processed ones',
      () async {
    final database = AppDatabase(NativeDatabase.memory());
    addTearDown(database.close);
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

    final rows = await RawSmsRepository(database).watchUnparsed().first;

    expect(rows.map((row) => row.id), ['sms_unparsed']);
    expect(rows.single.sender, 'AX-UNKNOWN');
  });
}
