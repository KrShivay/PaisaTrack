import 'package:drift/drift.dart';

/// Expected events schema (T-138a) for bill-due, autopay, and recurring payment obligations.
/// Invariant: Expected events are NEVER transactions and NEVER enter spending aggregates.
@DataClassName('ExpectedEvent')
class ExpectedEvents extends Table {
  TextColumn get id => text()();
  TextColumn get source => text()();
  TextColumn get originSmsId => text().nullable()();
  TextColumn get seriesId => text().nullable()();
  TextColumn get counterpartyId => text().nullable()();
  TextColumn get label => text()();
  IntColumn get expectedAmountPaise => integer()();
  IntColumn get amountLowPaise => integer().nullable()();
  IntColumn get amountHighPaise => integer().nullable()();
  DateTimeColumn get expectedDate => dateTime()();
  IntColumn get dateWindowDays => integer().withDefault(const Constant(3))();
  TextColumn get cadence => text().nullable()();
  TextColumn get state => text()(); // 'expected' | 'fulfilled' | 'missed' | 'cancelled' | 'snoozed'
  TextColumn get fulfilledTxnId => text().nullable()();
  RealColumn get confidence => real()();
  TextColumn get dedupKey => text()();

  @override
  Set<Column> get primaryKey => {id};
}

/// Composite unique index on (dedup_key, expected_date) to collapse repeated reminders for one obligation.
final idxExpectedEventsDedup = Index(
  'idx_expected_events_dedup',
  'CREATE UNIQUE INDEX idx_expected_events_dedup ON expected_events (dedup_key, expected_date);',
);
