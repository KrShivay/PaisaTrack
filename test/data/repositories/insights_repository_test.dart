import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paisatrack/data/db/database.dart';
import 'package:paisatrack/data/repositories/insights_repository.dart';

void main() {
  late AppDatabase database;
  late InsightsRepository repository;

  setUp(() async {
    database = AppDatabase(NativeDatabase.memory());
    repository = InsightsRepository(database);

    await database.into(database.insights).insert(
          InsightsCompanion.insert(
            id: 'forecast:2026-07',
            period: '2026-07',
            kind: 'forecast',
            payloadJson: '{}',
          ),
        );
  });

  tearDown(() async {
    await database.close();
  });

  Future<Insight> fetchInsight() =>
      (database.select(database.insights)
            ..where((i) => i.id.equals('forecast:2026-07')))
          .getSingle();

  test('dismiss sets dismissed=true', () async {
    await repository.dismiss(id: 'forecast:2026-07');
    final row = await fetchInsight();
    expect(row.dismissed, isTrue);
  });

  test('dismiss on unknown id is a no-op and does not throw', () async {
    await expectLater(
      repository.dismiss(id: 'nonexistent'),
      completes,
    );
    final row = await fetchInsight();
    expect(row.dismissed, isFalse);
  });

  test('newly inserted insight is not dismissed by default', () async {
    final row = await fetchInsight();
    expect(row.dismissed, isFalse);
  });
}
