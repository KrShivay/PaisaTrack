import 'package:drift/drift.dart';

import 'merchants_table.dart';

/// Detected repeating payments and income, maintained by the nightly scanner.
@TableIndex(name: 'idx_recurring_series_merchant_id', columns: {#merchantId})
@TableIndex(
  name: 'idx_recurring_series_next_expected_date',
  columns: {#nextExpectedDate},
)
class RecurringSeries extends Table {
  TextColumn get id => text()();
  TextColumn get merchantId => text().references(Merchants, #id)();
  TextColumn get label => text()();
  RealColumn get expectedAmount => real()();
  RealColumn get tolerancePct => real()();
  TextColumn get period => text()();
  IntColumn get periodDays => integer()();
  DateTimeColumn get nextExpectedDate => dateTime()();
  RealColumn get lastAmount => real()();
  TextColumn get amountTrend => text()();
  IntColumn get occurrences => integer()();
  TextColumn get status => text()();
  TextColumn get kind => text()();

  @override
  Set<Column> get primaryKey => {id};
}
