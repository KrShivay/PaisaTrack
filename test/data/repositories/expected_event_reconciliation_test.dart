import 'package:drift/drift.dart' show Value;
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

  test(
      'Sequence fixture: reminder -> debit -> fulfilled; both rows remain visible',
      () async {
    final expectedDate = DateTime.utc(2026, 7, 10);
    await repository.recordExpectedEvent(
      source: 'sms_reminder',
      counterpartyId: 'billpay@upi',
      label: 'Electricity Bill',
      expectedAmountPaise: 450000,
      currencyCode: 'INR',
      currencySymbol: '₹',
      expectedDate: expectedDate,
      confidence: 0.95,
    );

    // Insert debit transaction matching expected event date and amount
    await database.into(database.transactions).insert(
          TransactionsCompanion.insert(
            id: 'txn_debit_1',
            ts: expectedDate.millisecondsSinceEpoch,
            amount: 4500.0,
            currencyCode: const Value('INR'),
            currencySymbol: const Value('₹'),
            direction: 'debit',
            channel: 'upi',
            counterpartyVpa: const Value(' BillPay@UPI '),
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

  test('same date and amount from a different VPA does not fulfil', () async {
    final expectedDate = DateTime.utc(2026, 7, 10);
    await repository.recordExpectedEvent(
      source: 'sms_reminder',
      counterpartyId: 'electricity@upi',
      label: 'Electricity Bill',
      expectedAmountPaise: 450000,
      expectedDate: expectedDate,
      confidence: 0.95,
    );
    await _insertDebit(
      database,
      id: 'unrelated_debit',
      ts: expectedDate,
      amount: 4500,
      counterpartyVpa: 'groceries@upi',
    );

    await repository.reconcileExpectedEvents(today: expectedDate);

    final event = (await repository.getExpectedEvents()).single;
    expect(event.state, 'expected');
    expect(event.fulfilledTxnId, isNull);
  });

  test('USD expectation never fulfils against a same-nominal INR debit',
      () async {
    final expectedDate = DateTime.utc(2026, 7, 10);
    await repository.recordExpectedEvent(
      source: 'sms_reminder',
      counterpartyId: 'billpay@upi',
      label: 'Foreign bill',
      expectedAmountPaise: 450000,
      currencyCode: 'USD',
      currencySymbol: r'$',
      expectedDate: expectedDate,
      confidence: 0.95,
    );
    await _insertDebit(
      database,
      id: 'inr_debit',
      ts: expectedDate,
      amount: 4500,
      counterpartyVpa: 'billpay@upi',
    );

    await repository.reconcileExpectedEvents(today: expectedDate);

    final event = (await repository.getExpectedEvents()).single;
    expect(event.currencyCode, 'USD');
    expect(event.state, 'expected');
    expect(event.fulfilledTxnId, isNull);
  });

  test('unknown legacy expectation matches only unknown legacy debit',
      () async {
    final expectedDate = DateTime.utc(2026, 7, 10);
    await repository.recordExpectedEvent(
      source: 'sms_reminder',
      counterpartyId: 'billpay@upi',
      label: 'Legacy bill',
      expectedAmountPaise: 450000,
      expectedDate: expectedDate,
      confidence: 0.95,
    );
    await _insertDebit(
      database,
      id: 'legacy_unknown_debit',
      ts: expectedDate,
      amount: 4500,
      counterpartyVpa: 'billpay@upi',
      currencyCode: null,
      currencySymbol: null,
    );

    await repository.reconcileExpectedEvents(today: expectedDate);

    final event = (await repository.getExpectedEvents()).single;
    expect(event.currencyCode, isNull);
    expect(event.state, 'fulfilled');
    expect(event.fulfilledTxnId, 'legacy_unknown_debit');
  });

  test('ambiguous overlapping expectations do not share one debit', () async {
    final firstDate = DateTime.utc(2026, 7, 10);
    await repository.recordExpectedEvent(
      source: 'sms_reminder',
      counterpartyId: 'billpay@upi',
      label: 'Bill A',
      expectedAmountPaise: 450000,
      expectedDate: firstDate,
      confidence: 0.95,
    );
    await repository.recordExpectedEvent(
      source: 'sms_reminder',
      counterpartyId: 'billpay@upi',
      label: 'Bill B',
      expectedAmountPaise: 450000,
      expectedDate: firstDate.add(const Duration(days: 1)),
      confidence: 0.95,
    );
    await _insertDebit(
      database,
      id: 'ambiguous_debit',
      ts: firstDate,
      amount: 4500,
      counterpartyVpa: 'billpay@upi',
    );

    await repository.reconcileExpectedEvents(today: firstDate);

    final events = await repository.getExpectedEvents();
    expect(events, hasLength(2));
    expect(events.map((event) => event.state), everyElement('expected'));
    expect(events.map((event) => event.fulfilledTxnId), everyElement(isNull));
  });

  test('multiple same-identity debits remain ambiguous for one event',
      () async {
    final expectedDate = DateTime.utc(2026, 7, 10);
    await repository.recordExpectedEvent(
      source: 'sms_reminder',
      counterpartyId: 'billpay@upi',
      label: 'Electricity Bill',
      expectedAmountPaise: 450000,
      expectedDate: expectedDate,
      confidence: 0.95,
    );
    await _insertDebit(
      database,
      id: 'candidate_one',
      ts: expectedDate,
      amount: 4500,
      counterpartyVpa: 'billpay@upi',
    );
    await _insertDebit(
      database,
      id: 'candidate_two',
      ts: expectedDate.add(const Duration(hours: 1)),
      amount: 4500,
      counterpartyVpa: 'billpay@upi',
    );

    await repository.reconcileExpectedEvents(today: expectedDate);

    final event = (await repository.getExpectedEvents()).single;
    expect(event.state, 'expected');
    expect(event.fulfilledTxnId, isNull);
  });

  test('unidentified event and ineligible debits stay unfulfilled', () async {
    final expectedDate = DateTime.utc(2026, 7, 10);
    for (final (id, counterparty) in [
      ('no_identity', null),
      ('deleted', 'deleted@upi'),
      ('duplicate', 'duplicate@upi'),
      ('not_settled', 'pending@upi'),
    ]) {
      final dayOffset = [
        'no_identity',
        'deleted',
        'duplicate',
        'not_settled',
      ].indexOf(id);
      await repository.recordExpectedEvent(
        source: 'sms_reminder',
        counterpartyId: counterparty,
        label: id,
        expectedAmountPaise: 450000,
        expectedDate: expectedDate.add(Duration(days: dayOffset)),
        confidence: 0.95,
      );
    }
    await _insertDebit(
      database,
      id: 'unidentified_debit',
      ts: expectedDate,
      amount: 4500,
      counterpartyVpa: null,
    );
    await _insertDebit(
      database,
      id: 'deleted_debit',
      ts: expectedDate.add(const Duration(days: 1)),
      amount: 4500,
      counterpartyVpa: 'deleted@upi',
      isDeleted: true,
    );
    await _insertDebit(
      database,
      id: 'duplicate_source',
      ts: expectedDate.add(const Duration(days: 2)),
      amount: 4500,
      counterpartyVpa: 'duplicate@upi',
      status: 'needs_review',
    );
    await _insertDebit(
      database,
      id: 'duplicate_debit',
      ts: expectedDate.add(const Duration(days: 2)),
      amount: 4500,
      counterpartyVpa: 'duplicate@upi',
      duplicateOfTxnId: 'duplicate_source',
    );
    await _insertDebit(
      database,
      id: 'pending_debit',
      ts: expectedDate.add(const Duration(days: 3)),
      amount: 4500,
      counterpartyVpa: 'pending@upi',
      lifecycleState: 'pending',
    );

    await repository.reconcileExpectedEvents(
      today: expectedDate.add(const Duration(days: 3)),
    );

    final events = await repository.getExpectedEvents();
    expect(events.map((event) => event.state), everyElement('expected'));
  });

  test('repeated reminder cannot reset a fulfilled event', () async {
    final expectedDate = DateTime.utc(2026, 7, 10);
    final event = {
      'source': 'sms_reminder',
      'counterpartyId': 'billpay@upi',
      'label': 'Electricity Bill',
      'expectedAmountPaise': 450000,
      'currencyCode': 'INR',
      'currencySymbol': '₹',
      'expectedDate': expectedDate,
      'confidence': 0.95,
    };
    await repository.recordExpectedEvent(
      source: event['source']! as String,
      counterpartyId: event['counterpartyId']! as String,
      label: event['label']! as String,
      expectedAmountPaise: event['expectedAmountPaise']! as int,
      currencyCode: event['currencyCode']! as String,
      currencySymbol: event['currencySymbol']! as String,
      expectedDate: event['expectedDate']! as DateTime,
      confidence: event['confidence']! as double,
    );
    await _insertDebit(
      database,
      id: 'fulfilled_debit',
      ts: expectedDate,
      amount: 4500,
      counterpartyVpa: 'billpay@upi',
    );
    await repository.reconcileExpectedEvents(today: expectedDate);
    await repository.recordExpectedEvent(
      source: event['source']! as String,
      counterpartyId: event['counterpartyId']! as String,
      label: event['label']! as String,
      expectedAmountPaise: event['expectedAmountPaise']! as int,
      currencyCode: event['currencyCode']! as String,
      currencySymbol: event['currencySymbol']! as String,
      expectedDate: event['expectedDate']! as DateTime,
      confidence: event['confidence']! as double,
    );

    final updated = (await repository.getExpectedEvents()).single;
    expect(updated.state, 'fulfilled');
    expect(updated.fulfilledTxnId, 'fulfilled_debit');
  });

  test('Reminder with no debit past window -> missed; both rows remain visible',
      () async {
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

Future<void> _insertDebit(
  AppDatabase database, {
  required String id,
  required DateTime ts,
  required double amount,
  required String? counterpartyVpa,
  String status = 'confirmed',
  String lifecycleState = 'settled',
  String? currencyCode = 'INR',
  String? currencySymbol = '₹',
  bool isDeleted = false,
  String? duplicateOfTxnId,
}) async {
  await database.into(database.transactions).insert(
        TransactionsCompanion.insert(
          id: id,
          ts: ts.millisecondsSinceEpoch,
          amount: amount,
          currencyCode: Value(currencyCode),
          currencySymbol: Value(currencySymbol),
          direction: 'debit',
          channel: 'upi',
          counterpartyVpa: Value(counterpartyVpa),
          duplicateOfTxnId: Value(duplicateOfTxnId),
          parseSource: 'template',
          confidenceJson: '{}',
          status: status,
          isDeleted: Value(isDeleted),
          lifecycleState: Value(lifecycleState),
          createdAt: ts,
          updatedAt: ts,
        ),
      );
}
