import 'package:drift/drift.dart';

/// Rolling aggregate statistics used by the nightly anomaly detector.
class Baselines extends Table {
  TextColumn get key => text()();
  RealColumn get mean => real()();
  RealColumn get std => real()();
  IntColumn get n => integer()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {key};
}
