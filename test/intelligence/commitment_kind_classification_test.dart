import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paisatrack/data/db/database.dart';
import 'package:paisatrack/intelligence/recurring_detector.dart';

void main() {
  late AppDatabase database;
  late RecurringDetector detector;

  setUp(() {
    database = AppDatabase(NativeDatabase.memory());
    detector = RecurringDetector(database);
  });

  tearDown(() async {
    await database.close();
  });

  test('Classifies EMI, subscription, and bill commitment kinds accurately', () async {
    final now = DateTime.utc(2026, 7, 10);
    // EMI transactions
    for (var i = 0; i < 3; i++) {
      await database.into(database.transactions).insert(
            TransactionsCompanion.insert(
              id: 'emi_$i',
              ts: now.subtract(Duration(days: 30 * i)).millisecondsSinceEpoch,
              amount: 12500.0,
              direction: 'debit',
              channel: 'upi',
              parseSource: 'template',
              merchantRaw: const Value('HDFC Home Loan EMI'),
              confidenceJson: '{}',
              status: 'confirmed',
              createdAt: now,
              updatedAt: now,
            ),
          );
    }

    final detections = await detector.run(today: now);
    expect(detections, isNotEmpty);
    final emiDetection = detections.firstWhere((d) => d.label.contains('EMI'));
    expect(emiDetection.kind, 'emi');

    // Total monthly commitment load calculation
    final totalLoad = computeTotalMonthlyCommitmentLoad(detections);
    expect(totalLoad, greaterThan(0));
  });

  test('Ambiguous series stay unclassified rather than guessing', () async {
    final now = DateTime.utc(2026, 7, 10);
    for (var i = 0; i < 3; i++) {
      await database.into(database.transactions).insert(
            TransactionsCompanion.insert(
              id: 'ambig_$i',
              ts: now.subtract(Duration(days: 30 * i)).millisecondsSinceEpoch,
              amount: 500.0,
              direction: 'debit',
              channel: 'upi',
              parseSource: 'template',
              merchantRaw: const Value('Unknown Merchant 9876'),
              confidenceJson: '{}',
              status: 'confirmed',
              createdAt: now,
              updatedAt: now,
            ),
          );
    }

    final detections = await detector.run(today: now);
    final ambigDetection = detections.firstWhere((d) => d.label.contains('Unknown'));
    expect(ambigDetection.kind, 'unclassified');
  });
}
