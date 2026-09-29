import 'package:drift/drift.dart';

/// Durable user decisions keyed by the stable SMS provider row ID.
///
/// This table intentionally stores no message content and has no foreign key
/// to `raw_sms`, so suppression survives ordinary raw-SMS expiry.
class SmsDispositions extends Table {
  TextColumn get smsId => text()();
  TextColumn get transactionId => text()();
  TextColumn get disposition => text()();
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column> get primaryKey => {smsId};
}
