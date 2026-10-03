import 'package:drift/drift.dart';

/// Captured SMS bodies.
///
/// Rows contain sensitive raw financial SMS text. The SMS behind a transaction
/// or disposition is kept as provenance; unlinked rows expire after
/// `AppConstants.rawSmsRetentionDays` (ADR 0021, `RawSmsRetention`).
class RawSms extends Table {
  TextColumn get id => text()();
  TextColumn get sender => text()();
  TextColumn get body => text()();
  DateTimeColumn get receivedAt => dateTime()();
  BoolColumn get processed => boolean().withDefault(const Constant(false))();
  IntColumn get parserVersion => integer().nullable()();
  TextColumn get failureReason => text().nullable()();
  DateTimeColumn get purgeAfter => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}
