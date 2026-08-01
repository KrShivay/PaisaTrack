import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paisatrack/capture/parser_cascade.dart';
import 'package:paisatrack/capture/sms_ingestion.dart';
import 'package:paisatrack/capture/template_engine/template_matcher.dart';
import 'package:paisatrack/capture/template_engine/template_registry.dart';
import 'package:paisatrack/data/db/database.dart';
import 'package:paisatrack/data/models/raw_sms.dart';
import 'package:paisatrack/data/repositories/rule_repository.dart';
import 'package:paisatrack/enrichment/categorizer.dart';
import 'package:paisatrack/enrichment/seed_category_map.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase database;
  late SmsIngestor ingestor;

  setUp(() async {
    database = AppDatabase(NativeDatabase.memory());
    await database.seedDefaultCategories();
    ingestor = SmsIngestor(
      database: database,
      parser: ParserCascade(
        templateMatcher: TemplateMatcher(
          registries: Directory('assets/templates')
              .listSync()
              .whereType<File>()
              .where((file) => file.path.endsWith('.json'))
              .map((file) => TemplateRegistry.fromJson(file.readAsStringSync()))
              .toList(growable: false),
        ),
      ),
      categorizer: Categorizer(
        rules: RuleRepository(database),
        seedMap: SeedCategoryMap.fromJson(
          File('assets/seed/category_seed.json').readAsStringSync(),
        ),
      ),
    );
  });

  tearDown(() async {
    await database.close();
  });

  test('salary-credit matrix creates income transactions end to end', () async {
    final matrix = (jsonDecode(
      File('test/fixtures/salary_credit_matrix.json').readAsStringSync(),
    ) as List<Object?>)
        .cast<Map<String, Object?>>();

    expect(matrix, hasLength(3));
    expect(
      matrix.map((entry) => entry['id']).toSet(),
      containsAll(<String>[
        'hdfc_salary_template',
        'icici_salary_template',
        'generic_salary_credit',
      ]),
    );
    expect(
      matrix.map((entry) => entry['id']).toSet(),
      hasLength(matrix.length),
    );

    for (final entry in matrix) {
      final sms = RawSms(
        id: entry['id']! as String,
        sender: entry['sender']! as String,
        body: entry['body']! as String,
        receivedAt: DateTime.parse(entry['receivedAt']! as String),
      );

      await ingestor.ingest(sms);

      final transactionId = 'txn_${entry['id']}';
      final transactions = await (database.select(database.transactions)
            ..where((row) => row.id.equals(transactionId)))
          .get();
      expect(transactions, hasLength(1), reason: entry['id'] as String);
      final transaction = transactions.single;
      expect(
        transaction.amount,
        entry['amount'],
        reason: entry['id'] as String,
      );
      expect(transaction.direction, 'credit', reason: entry['id'] as String);
      expect(
        transaction.parseSource,
        entry['parser'],
        reason: entry['id'] as String,
      );
      expect(
        transaction.categoryId,
        'income_salary',
        reason: entry['id'] as String,
      );
      final confidence = jsonDecode(transaction.confidenceJson);
      final parserEvidence = confidence['parser'] as Map<String, Object?>;
      expect(
        parserEvidence['template_id'],
        entry['templateId'],
        reason: entry['id'] as String,
      );

      final raw = await (database.select(database.rawSms)
            ..where((row) => row.id.equals(entry['id']! as String)))
          .getSingle();
      expect(raw.processed, isTrue, reason: entry['id'] as String);
      expect(raw.failureReason, isNull, reason: entry['id'] as String);
    }
  });
}
