import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paisatrack/data/db/database.dart';
import 'package:paisatrack/data/repositories/expected_event_repository.dart';

void main() {
  late AppDatabase database;
  late ExpectedEventRepository repository;

  setUp(() {
    database = AppDatabase(NativeDatabase.memory());
    repository = ExpectedEventRepository(database);
  });

  tearDown(() async {
    await database.close();
  });

  test('Sequence fixture: reminder -> debit -> fulfilled; both rows remain visible', () async {
    final expectedDate = DateTime.utc(2026, 7, 10);
    await repository.recordExpectedEvent(
      source: 'sms_reminder',
      label: 'Electricity Bill',
      expectedAmountPaise: 450000,
      expectedDate: expectedDate,
      confidence: 0.95,
    );

    // Insert debit transaction matching expected event date and amount
    await database.into(database.transactions).insert(
          TransactionsCompanion.insert(
            id: 'txn_debit_1',
            ts: expectedDate.millisecondsSinceEpoch,
            amount: 4500.0,
            direction: 'debit',
            channel: 'upi',
            parseSource: 'template',
            confidenceJson: '{}',
            status: 'confirmed',
            createdAt: expectedDate,
            updatedAt: expectedDate,
          ),
        );

    await repository.reconcileExpectedEvents(today: expectedDate);

    final events = await repository.getExpectedEvents();
    expect(events, hasLength(1));
    expect(events.first.state, 'fulfilled');
    expect(events.first.fulfilledTxnId, 'txn_debit_1');

    // AC: Both rows remain visible
    final txns = await database.select(database.transactions).get();
    expect(txns, hasLength(1));
  });

  test('Reminder with no debit past window -> missed; both rows remain visible', () async {
    final expectedDate = DateTime.utc(2026, 7, 10);
    await repository.recordExpectedEvent(
      source: 'sms_reminder',
      label: 'Water Bill',
      expectedAmountPaise: 120000,
      expectedDate: expectedDate,
      dateWindowDays: 3,
      confidence: 0.95,
    );

    // Reconcile 5 days after expected date (past window of 3 days) with no matching debit
    final today = DateTime.utc(2026, 7, 16);
    await repository.reconcileExpectedEvents(today: today);

    final events = await repository.getExpectedEvents();
    expect(events, hasLength(1));
    expect(events.first.state, 'missed');
  });

  test('Snooze and cancel update event state correctly', () async {
    final expectedDate = DateTime.utc(2026, 7, 10);
    await repository.recordExpectedEvent(
      source: 'sms_reminder',
      label: 'Internet Bill',
      expectedAmountPaise: 99900,
      expectedDate: expectedDate,
      confidence: 0.95,
    );

    final events = await repository.getExpectedEvents();
    final eventId = events.first.id;

    await repository.snoozeEvent(eventId, days: 2);
    var updated = await repository.getExpectedEvents();
    expect(updated.first.state, 'snoozed');
    expect(updated.first.expectedDate.toUtc(), DateTime.utc(2026, 7, 12));

    await repository.cancelEvent(eventId);
    updated = await repository.getExpectedEvents();
    expect(updated.first.state, 'cancelled');
  });
}
