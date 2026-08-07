import 'package:drift/drift.dart';

/// Privacy-safe output snapshots from the experimental shadow pipeline.
///
/// This table deliberately stores normalized fields only. Raw SMS text stays
/// in `raw_sms` and is never copied into shadow results.
class ShadowTransactions extends Table {
  TextColumn get id => text()();
  TextColumn get sourceId => text()();
  TextColumn get pipelineVersion => text()();
  TextColumn get outcome => text()();
  IntColumn get amountPaise => integer().nullable()();
  TextColumn get direction => text().nullable()();
  TextColumn get merchantKey => text().nullable()();
  TextColumn get categoryId => text().nullable()();
  DateTimeColumn get observedAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}
