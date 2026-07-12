import 'dart:math';
import 'dart:typed_data';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paisatrack/data/db/database.dart';
import 'package:paisatrack/data/models/normalized_transaction_record.dart';
import 'package:paisatrack/enrichment/local_classifier.dart';

NormalizedTransactionRecord _record({
  double amount = 449,
  DateTime? ts,
  TransactionChannel channel = TransactionChannel.upi,
}) {
  return NormalizedTransactionRecord(
    amount: amount,
    direction: TransactionDirection.debit,
    channel: channel,
    merchantRaw: 'Swiggy',
    counterpartyVpa: null,
    accountHint: null,
    balanceAfter: null,
    refId: null,
    ts: ts ?? DateTime.utc(2026, 7, 7, 12),
    parseSource: ParseSource.template,
    parseConfidence: 0.97,
  );
}

Future<void> _insertTxn(
  AppDatabase database, {
  required String id,
  required double amount,
  required String categoryId,
  DateTime? ts,
  Uint8List? merchantEmbedding,
}) async {
  String? merchantId;
  if (merchantEmbedding != null) {
    merchantId = 'merchant_$id';
    final now = DateTime.utc(2026, 7, 1);
    await database.into(database.merchants).insertOnConflictUpdate(
          MerchantsCompanion.insert(
            id: merchantId,
            canonicalName: id,
            embedding: Value(merchantEmbedding),
            firstSeen: now,
            lastSeen: now,
          ),
        );
  }
  final timestamp = ts ?? DateTime.utc(2026, 7, 7, 12);
  await database.into(database.transactions).insert(
        TransactionsCompanion.insert(
          id: id,
          ts: timestamp.millisecondsSinceEpoch,
          amount: amount,
          direction: 'debit',
          channel: 'upi',
          merchantRaw: const Value('Swiggy'),
          merchantId: Value(merchantId),
          categoryId: Value(categoryId),
          parseSource: 'template',
          confidenceJson: '{}',
          status: 'confirmed',
          createdAt: timestamp,
          updatedAt: timestamp,
        ),
      );
}

Future<void> _insertFeedback(
  AppDatabase database, {
  required String id,
  required String txnId,
  required String newValue,
}) {
  return database.into(database.feedback).insert(
        FeedbackCompanion.insert(
          id: id,
          txnId: txnId,
          field: 'category_id',
          newValue: Value(newValue),
          context: 'ask_now',
          createdAt: DateTime.utc(2026, 7, 8),
        ),
      );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('LocalClassifier.features', () {
    test('pads a short embedding with zeros to the requested dimension', () {
      final values = LocalClassifier.features(
        _record(amount: 99, channel: TransactionChannel.card),
        Float32List.fromList([0.5, -0.5]),
        embeddingDimensions: 5,
      );
      expect(values, hasLength(9));
      expect(values.sublist(0, 5), [0.5, -0.5, 0, 0, 0]);
    });

    test('truncates an embedding longer than the requested dimension', () {
      final values = LocalClassifier.features(
        _record(),
        Float32List.fromList([1, 2, 3, 4]),
        embeddingDimensions: 2,
      );
      expect(values.sublist(0, 2), [1, 2]);
      expect(values, hasLength(6));
    });

    test('null embedding fills the embedding slots with zero', () {
      final values =
          LocalClassifier.features(_record(), null, embeddingDimensions: 3);
      expect(values.sublist(0, 3), [0, 0, 0]);
    });

    test('trailing four features are log-amount, hour, dow, channel bands', () {
      final ts = DateTime.utc(2026, 7, 7, 12); // Tuesday
      final record = _record(
        amount: 99,
        ts: ts,
        channel: TransactionChannel.card,
      );
      final values =
          LocalClassifier.features(record, null, embeddingDimensions: 0);
      final local = ts.toLocal();
      expect(values, [
        log(100) / 16,
        local.hour / 23,
        local.weekday / 7,
        TransactionChannel.card.index / (TransactionChannel.values.length - 1),
      ]);
    });
  });

  group('ClassifierModel', () {
    test('round-trips through JSON', () {
      const model = ClassifierModel(
        categories: ['food_dining', 'shopping'],
        weights: [
          [0.1, 0.2],
          [-0.1, 0.3],
        ],
        biases: [0.0, 1.0],
      );
      final parsed = ClassifierModel.tryParse(model.toJson());
      expect(parsed, isNotNull);
      expect(parsed!.categories, model.categories);
      expect(parsed.weights, model.weights);
      expect(parsed.biases, model.biases);
      expect(parsed.featureCount, 2);
    });

    test('rejects malformed JSON', () {
      expect(ClassifierModel.tryParse('not json'), isNull);
    });

    test('rejects a shape mismatch between weights and categories', () {
      const badJson =
          '{"version":1,"categories":["a","b"],"weights":[[0.1]],"biases":[0,0]}';
      expect(ClassifierModel.tryParse(badJson), isNull);
    });

    test('rejects ragged weight rows', () {
      const badJson = '{"version":1,"categories":["a","b"],'
          '"weights":[[0.1,0.2],[0.1]],"biases":[0,0]}';
      expect(ClassifierModel.tryParse(badJson), isNull);
    });
  });

  group('LocalClassifier.predict', () {
    late AppDatabase database;

    setUp(() async {
      database = AppDatabase(NativeDatabase.memory());
    });

    tearDown(() async {
      await database.close();
    });

    test('no stored model -> null (ladder falls through unchanged)', () async {
      final classifier = LocalClassifier(database);
      expect(await classifier.predict(_record()), isNull);
    });

    test('malformed model_meta value -> null', () async {
      await database.into(database.modelMeta).insertOnConflictUpdate(
            ModelMetaCompanion.insert(
              key: classifierModelMetaKey,
              value: 'not json',
            ),
          );
      final classifier = LocalClassifier(database);
      expect(await classifier.predict(_record()), isNull);
    });

    test('picks the highest-scoring category via softmax', () async {
      // Zero feature weights so only the bias decides: food_dining wins
      // regardless of the input record's feature values.
      const model = ClassifierModel(
        categories: ['food_dining', 'shopping'],
        weights: [
          [0.0, 0.0, 0.0, 0.0],
          [0.0, 0.0, 0.0, 0.0],
        ],
        biases: [5.0, 0.0],
      );
      await database.into(database.modelMeta).insertOnConflictUpdate(
            ModelMetaCompanion.insert(
              key: classifierModelMetaKey,
              value: model.toJson(),
            ),
          );
      final classifier = LocalClassifier(database);

      final prediction = await classifier.predict(_record());

      expect(prediction, isNotNull);
      expect(prediction!.categoryId, 'food_dining');
      final expectedConfidence = exp(5.0) / (exp(5.0) + exp(0.0));
      expect(prediction.confidence, closeTo(expectedConfidence, 1e-9));
    });

    test('feature-vector length mismatch against stored weights -> null',
        () async {
      // 4-feature model (0 embedding dims) but the classifier will build a
      // longer default (16-dim embedding + 4) vector — length mismatch.
      const model = ClassifierModel(
        categories: ['food_dining', 'shopping'],
        weights: [
          [0.0, 0.0, 0.0],
          [0.0, 0.0, 0.0],
        ],
        biases: [1.0, 0.0],
      );
      await database.into(database.modelMeta).insertOnConflictUpdate(
            ModelMetaCompanion.insert(
              key: classifierModelMetaKey,
              value: model.toJson(),
            ),
          );
      final classifier = LocalClassifier(database);
      // featureCount = 3 -> embeddingDimensions = max(0, 3-4) = 0 -> 4
      // features produced, which mismatches the 3-wide weight rows.
      expect(await classifier.predict(_record()), isNull);
    });
  });

  group('ClassifierTrainer', () {
    late AppDatabase database;

    setUp(() async {
      database = AppDatabase(NativeDatabase.memory());
      await database.seedDefaultCategories();
    });

    tearDown(() async {
      await database.close();
    });

    test('no feedback rows -> false, no model written', () async {
      final trained = await ClassifierTrainer(database).train();
      expect(trained, isFalse);
      expect(await database.select(database.modelMeta).get(), isEmpty);
    });

    test('fewer than two distinct categories -> false', () async {
      await _insertTxn(
        database,
        id: 'txn_1',
        amount: 100,
        categoryId: 'food_dining',
      );
      await _insertFeedback(
        database,
        id: 'fb_1',
        txnId: 'txn_1',
        newValue: 'food_dining',
      );
      await _insertTxn(
        database,
        id: 'txn_2',
        amount: 120,
        categoryId: 'food_dining',
      );
      await _insertFeedback(
        database,
        id: 'fb_2',
        txnId: 'txn_2',
        newValue: 'food_dining',
      );

      final trained = await ClassifierTrainer(database).train();

      expect(trained, isFalse);
      expect(await database.select(database.modelMeta).get(), isEmpty);
    });

    test('trains and persists weights + last_trained_at from feedback rows',
        () async {
      await _insertTxn(
        database,
        id: 'txn_1',
        amount: 150,
        categoryId: 'food_dining',
      );
      await _insertFeedback(
        database,
        id: 'fb_1',
        txnId: 'txn_1',
        newValue: 'food_dining',
      );
      await _insertTxn(
        database,
        id: 'txn_2',
        amount: 4000,
        categoryId: 'shopping',
      );
      await _insertFeedback(
        database,
        id: 'fb_2',
        txnId: 'txn_2',
        newValue: 'shopping',
      );

      final trainer = ClassifierTrainer(database);
      expect(await trainer.train(seed: 7, epochs: 5), isFalse);
      final trained = await trainer.train(
        seed: 7,
        epochs: 200,
        minimumNewFeedback: 2,
      );

      expect(trained, isTrue);
      final meta = await (database.select(database.modelMeta)
            ..where((m) => m.key.equals(classifierModelMetaKey)))
          .getSingle();
      final model = ClassifierModel.tryParse(meta.value);
      expect(model, isNotNull);
      expect(model!.categories, ['food_dining', 'shopping']);
      expect(model.weights, hasLength(2));
      expect(model.biases, hasLength(2));
      expect(
        (await LocalClassifier(database).predict(_record(amount: 150)))
            ?.categoryId,
        'food_dining',
      );
      expect(
        (await LocalClassifier(database).predict(_record(amount: 4000)))
            ?.categoryId,
        'shopping',
      );

      final trainedAt = await (database.select(database.modelMeta)
            ..where((m) => m.key.equals('classifier_last_trained_at')))
          .getSingle();
      expect(DateTime.tryParse(trainedAt.value), isNotNull);
    });

    test('ignores feedback rows whose field is not category_id', () async {
      await _insertTxn(
        database,
        id: 'txn_1',
        amount: 150,
        categoryId: 'food_dining',
      );
      await _insertFeedback(
        database,
        id: 'fb_1',
        txnId: 'txn_1',
        newValue: 'food_dining',
      );
      await _insertTxn(
        database,
        id: 'txn_2',
        amount: 4000,
        categoryId: 'shopping',
      );
      await database.into(database.feedback).insert(
            FeedbackCompanion.insert(
              id: 'fb_status',
              txnId: 'txn_2',
              field: 'status',
              newValue: const Value('confirmed'),
              context: 'ask_now',
              createdAt: DateTime.utc(2026, 7, 8),
            ),
          );

      final trained = await ClassifierTrainer(database).train();

      // Only one category_id-labeled sample exists -> below the 2-category
      // minimum, regardless of the unrelated status feedback row.
      expect(trained, isFalse);
    });

    test('same seed on the same feedback set trains deterministically',
        () async {
      await _insertTxn(
        database,
        id: 'txn_1',
        amount: 150,
        categoryId: 'food_dining',
      );
      await _insertFeedback(
        database,
        id: 'fb_1',
        txnId: 'txn_1',
        newValue: 'food_dining',
      );
      await _insertTxn(
        database,
        id: 'txn_2',
        amount: 4000,
        categoryId: 'shopping',
      );
      await _insertFeedback(
        database,
        id: 'fb_2',
        txnId: 'txn_2',
        newValue: 'shopping',
      );
      await _insertTxn(
        database,
        id: 'txn_3',
        amount: 90,
        categoryId: 'food_dining',
      );
      await _insertFeedback(
        database,
        id: 'fb_3',
        txnId: 'txn_3',
        newValue: 'food_dining',
      );

      final trainer = ClassifierTrainer(database);
      await trainer.train(
        seed: 42,
        epochs: 10,
        minimumNewFeedback: 3,
      );
      final first = await (database.select(database.modelMeta)
            ..where((m) => m.key.equals(classifierModelMetaKey)))
          .getSingle();

      await (database.delete(database.modelMeta)
            ..where((m) => m.key.equals('classifier_last_trained_at')))
          .go();
      await trainer.train(
        seed: 42,
        epochs: 10,
        minimumNewFeedback: 3,
      );
      final second = await (database.select(database.modelMeta)
            ..where((m) => m.key.equals(classifierModelMetaKey)))
          .getSingle();

      expect(second.value, first.value);
    });
  });
}
