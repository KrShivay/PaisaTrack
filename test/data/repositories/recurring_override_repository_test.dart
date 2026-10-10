import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paisatrack/data/db/database.dart';
import 'package:paisatrack/data/repositories/recurring_override_repository.dart';
import 'package:paisatrack/data/repositories/recurring_repository.dart';
import 'package:paisatrack/intelligence/recurring_detector.dart';

void main() {
  late AppDatabase database;
  late RecurringOverrideRepository repo;

  setUp(() {
    database = AppDatabase(NativeDatabase.memory());
    repo = RecurringOverrideRepository(
      database,
      clock: () => DateTime.utc(2026, 4, 10),
    );
  });
  tearDown(() => database.close());

  Future<void> insertTxn(String id, DateTime date) async {
    const amount = 499.0;
    await database.into(database.transactions).insert(
          TransactionsCompanion.insert(
            id: id,
            ts: date.millisecondsSinceEpoch,
            amount: amount,
            direction: 'debit',
            channel: 'card',
            merchantRaw: const Value('StreamFlix'),
            parseSource: 'template',
            confidenceJson: '{}',
            status: 'auto',
            createdAt: date,
            updatedAt: date,
          ),
        );
  }

  test('wire mapping', () {
    expect(recurringOverrideToWire(RecurringOverride.automatic), isNull);
    expect(recurringOverrideToWire(RecurringOverride.recurring), 'recurring');
    expect(
      recurringOverrideToWire(RecurringOverride.notRecurring),
      'not_recurring',
    );
    expect(recurringOverrideFromWire(null), RecurringOverride.automatic);
    expect(recurringOverrideFromWire('bogus'), RecurringOverride.automatic);
    expect(recurringOverrideFromWire('recurring'), RecurringOverride.recurring);
    expect(
      recurringOverrideFromWire('not_recurring'),
      RecurringOverride.notRecurring,
    );
  });

  test('setOverride touches only override and updatedAt', () async {
    await insertTxn('a', DateTime.utc(2026, 1, 1));
    final before = await (database.select(database.transactions)
          ..where((t) => t.id.equals('a')))
        .getSingle();
    await repo.setOverride('a', RecurringOverride.recurring);
    final after = await (database.select(database.transactions)
          ..where((t) => t.id.equals('a')))
        .getSingle();
    expect(await repo.overrideFor('a'), RecurringOverride.recurring);
    expect(after.updatedAt.isAtSameMomentAs(DateTime.utc(2026, 4, 10)), isTrue);
    expect(
      after.toJson()
        ..remove('recurringOverride')
        ..remove('updatedAt'),
      before.toJson()
        ..remove('recurringOverride')
        ..remove('updatedAt'),
    );
    await repo.setOverride('a', RecurringOverride.automatic);
    expect(await repo.overrideFor('a'), RecurringOverride.automatic);
    expect(await repo.overrideFor('missing'), RecurringOverride.automatic);
  });

  test('not_recurring rebuilds projection and keeps cancelled status',
      () async {
    for (final entry in [
      ('a', DateTime.utc(2026, 1, 1)),
      ('b', DateTime.utc(2026, 1, 31)),
      ('c', DateTime.utc(2026, 3, 2)),
    ]) {
      await insertTxn(entry.$1, entry.$2);
    }
    await rebuildRecurringProjection(
      database,
      today: DateTime.utc(2026, 4, 10),
    );
    var series = await database.select(database.recurringSeries).get();
    expect(series, hasLength(1));
    expect(await repo.isDetectedRecurring('a'), isTrue);
    await RecurringRepository(database)
        .setStatus(seriesId: series.single.id, status: 'cancelled');

    await repo.setOverride('b', RecurringOverride.notRecurring);
    series = await database.select(database.recurringSeries).get();
    expect(series, isEmpty);
    expect(await repo.isDetectedRecurring('a'), isFalse);

    await repo.setOverride('b', RecurringOverride.automatic);
    series = await database.select(database.recurringSeries).get();
    expect(series, hasLength(1));
    expect(series.single.status, 'cancelled');
  });
}
