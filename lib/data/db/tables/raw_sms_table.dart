import 'package:drift/drift.dart';

/// Temporary storage for captured SMS bodies before purge.
///
/// Rows in this table can contain sensitive raw financial SMS text and must
/// obey the retention window documented in `AppConstants.rawSmsRetentionDays`.
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
