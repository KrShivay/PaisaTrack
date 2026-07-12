import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:drift/drift.dart';

import '../data/db/database.dart';
import '../data/models/normalized_transaction_record.dart';

const classifierModelMetaKey = 'classifier_v1';

class ClassificationPrediction {
  const ClassificationPrediction(this.categoryId, this.confidence);
  final String categoryId;
  final double confidence;
}

/// Small, serializable softmax classifier. It has no native or cloud runtime;
/// weights live in `model_meta` and absence is an intentional no-op.
class LocalClassifier {
  LocalClassifier(this._database);
  final AppDatabase _database;

  Future<ClassificationPrediction?> predict(
    NormalizedTransactionRecord record, {
    Float32List? merchantEmbedding,
  }) async {
    final meta = await (_database.select(_database.modelMeta)
          ..where((row) => row.key.equals(classifierModelMetaKey)))
        .getSingleOrNull();
    if (meta == null) return null;
    final model = ClassifierModel.tryParse(meta.value);
    if (model == null) return null;
    final values = _features(record, merchantEmbedding, model.featureCount);
    if (values.length != model.featureCount) return null;
    final scores = <double>[];
    for (var row = 0; row < model.categories.length; row++) {
      var score = model.biases[row];
      for (var col = 0; col < values.length; col++) {
        score += model.weights[row][col] * values[col];
      }
      scores.add(score);
    }
    final maxScore = scores.reduce(max);
    final exponentials = scores.map((score) => exp(score - maxScore)).toList();
    final total = exponentials.reduce((a, b) => a + b);
    var winner = 0;
    for (var i = 1; i < exponentials.length; i++) {
      if (exponentials[i] > exponentials[winner]) winner = i;
    }
    return ClassificationPrediction(
      model.categories[winner],
      exponentials[winner] / total,
    );
  }

  static List<double> features(
    NormalizedTransactionRecord record,
    Float32List? merchantEmbedding, {
    int embeddingDimensions = 16,
  }) =>
      _features(record, merchantEmbedding, embeddingDimensions + 4);

  static List<double> _features(
    NormalizedTransactionRecord record,
    Float32List? embedding,
    int featureCount,
  ) {
    final embeddingDimensions = max(0, featureCount - 4);
    final result = <double>[];
    for (var i = 0; i < embeddingDimensions; i++) {
      result.add(embedding != null && i < embedding.length ? embedding[i] : 0);
    }
    final date = record.ts.toLocal();
    result
      ..add(log(record.amount + 1) / 16)
      ..add(date.hour / 23)
      ..add(date.weekday / 7)
      ..add(
        record.channel.index / max(1, TransactionChannel.values.length - 1),
      );
    return result;
  }
}

class ClassifierModel {
  const ClassifierModel({
    required this.categories,
    required this.weights,
    required this.biases,
  });
  final List<String> categories;
  final List<List<double>> weights;
  final List<double> biases;
  int get featureCount => weights.isEmpty ? 0 : weights.first.length;

  String toJson() => jsonEncode({
        'version': 1,
        'categories': categories,
        'weights': weights,
        'biases': biases,
      });

  static ClassifierModel? tryParse(String source) {
    try {
      final json = jsonDecode(source) as Map<String, Object?>;
      final categories = (json['categories'] as List).cast<String>();
      final weights = (json['weights'] as List)
          .map(
            (row) => (row as List).map((v) => (v as num).toDouble()).toList(),
          )
          .toList();
      final biases =
          (json['biases'] as List).map((v) => (v as num).toDouble()).toList();
      if (categories.isEmpty ||
          weights.length != categories.length ||
          biases.length != categories.length ||
          weights.any((row) => row.length != weights.first.length)) {
        return null;
      }
      return ClassifierModel(
        categories: categories,
        weights: weights,
        biases: biases,
      );
    } on FormatException {
      return null;
    } on TypeError {
      return null;
    }
  }
}

/// Deterministic bounded SGD trainer over category feedback. Raw SMS is never
/// read: only the normalized transaction columns and stored merchant vectors.
class ClassifierTrainer {
  ClassifierTrainer(this._database);
  final AppDatabase _database;

  Future<bool> train({
    int seed = 7,
    int epochs = 40,
    int minimumNewFeedback = 30,
  }) async {
    final lastTrained = await (_database.select(_database.modelMeta)
          ..where((row) => row.key.equals('classifier_last_trained_at')))
        .getSingleOrNull();
    final lastTrainedAt = DateTime.tryParse(lastTrained?.value ?? '');
    final rows = await (_database.select(_database.feedback).join([
      innerJoin(
        _database.transactions,
        _database.transactions.id.equalsExp(_database.feedback.txnId),
      ),
      leftOuterJoin(
        _database.merchants,
        _database.merchants.id.equalsExp(_database.transactions.merchantId),
      ),
    ])
          ..where(
            _database.feedback.field.equals('category_id') &
                (lastTrainedAt == null
                    ? const Constant(true)
                    : _database.feedback.createdAt
                        .isBiggerThanValue(lastTrainedAt)),
          ))
        .get();
    if (rows.length < minimumNewFeedback) return false;
    final samples = <({String label, List<double> values})>[];
    for (final row in rows) {
      final label = row.readTable(_database.feedback).newValue;
      if (label == null || label.isEmpty) continue;
      final txn = row.readTable(_database.transactions);
      final merchant = row.readTableOrNull(_database.merchants);
      final blob = merchant?.embedding;
      final vector = blob == null
          ? null
          : Float32List.view(
              blob.buffer,
              blob.offsetInBytes,
              blob.lengthInBytes ~/ 4,
            );
      samples.add(
        (
          label: label,
          values: LocalClassifier.features(_recordFrom(txn), vector)
        ),
      );
    }
    final categories = samples.map((s) => s.label).toSet().toList()..sort();
    if (categories.length < 2) return false;
    final n = samples.first.values.length;
    final random = Random(seed);
    final weights = List.generate(
      categories.length,
      (_) => List.generate(n, (_) => (random.nextDouble() - .5) * .01),
    );
    final biases = List<double>.filled(categories.length, 0);
    for (var epoch = 0; epoch < epochs; epoch++) {
      for (final sample in samples) {
        final scores = List<double>.generate(
          categories.length,
          (r) =>
              biases[r] +
              List<double>.generate(
                n,
                (c) => weights[r][c] * sample.values[c],
              ).reduce((a, b) => a + b),
        );
        final maximum = scores.reduce(max);
        final probabilities = scores.map((s) => exp(s - maximum)).toList();
        final total = probabilities.reduce((a, b) => a + b);
        for (var r = 0; r < categories.length; r++) {
          final error = probabilities[r] / total -
              (categories[r] == sample.label ? 1 : 0);
          for (var c = 0; c < n; c++) {
            weights[r][c] -= .05 * error * sample.values[c];
          }
          biases[r] -= .05 * error;
        }
      }
    }
    await _database.into(_database.modelMeta).insertOnConflictUpdate(
          ModelMetaCompanion.insert(
            key: classifierModelMetaKey,
            value: ClassifierModel(
              categories: categories,
              weights: weights,
              biases: biases,
            ).toJson(),
          ),
        );
    await _database.into(_database.modelMeta).insertOnConflictUpdate(
          ModelMetaCompanion.insert(
            key: 'classifier_last_trained_at',
            value: DateTime.now().toUtc().toIso8601String(),
          ),
        );
    return true;
  }

  NormalizedTransactionRecord _recordFrom(Transaction txn) =>
      NormalizedTransactionRecord(
        amount: txn.amount,
        direction: TransactionDirection.values.byName(txn.direction),
        channel: TransactionChannel.values.byName(txn.channel),
        merchantRaw: txn.merchantRaw,
        counterpartyVpa: txn.counterpartyVpa,
        accountHint: txn.accountHint,
        balanceAfter: txn.balanceAfter,
        refId: txn.refId,
        ts: DateTime.fromMillisecondsSinceEpoch(txn.ts, isUtc: true),
        parseSource: ParseSource.values
            .firstWhere((source) => source.wireName == txn.parseSource),
        parseConfidence: 1,
      );
}
