import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:drift/drift.dart';

import '../../data/db/database.dart';
import '../../data/db/database_provider.dart';

class ModelMetrics {
  const ModelMetrics({
    required this.accuracy,
    required this.askRate,
    required this.correctionRates,
  });
  final double accuracy;
  final double askRate;
  final Map<String, double> correctionRates;
}

final modelMetricsProvider = FutureProvider<ModelMetrics>((ref) async {
  final db = await ref.watch(appDatabaseProvider.future);
  return ModelMetricsRepository(db).load();
});

class ModelMetricsRepository {
  ModelMetricsRepository(this._database);
  final AppDatabase _database;
  Future<ModelMetrics> load() async {
    final feedback = await (_database.select(_database.feedback)
          ..where((f) => f.field.equals('category_id'))
          ..orderBy([(f) => OrderingTerm.desc(f.createdAt)])
          ..limit(100))
        .get();
    final transactions = await _database.select(_database.transactions).get();
    final transactionsById = {for (final row in transactions) row.id: row};
    final classifierFeedback = feedback.where((item) {
      final transaction = transactionsById[item.txnId];
      return transaction != null &&
          _categorySource(transaction) == 'classifier';
    }).toList();
    final corrected =
        classifierFeedback.where((f) => f.oldValue != f.newValue).length;
    final askedTxnIds =
        transactions.where((t) => t.status == 'asked').map((t) => t.id).toSet();
    askedTxnIds.addAll(
      (await (_database.select(_database.feedback)
                ..where((f) => f.context.equals('ask_now')))
              .get())
          .map((f) => f.txnId),
    );
    final rates = <String, double>{};
    for (final item in feedback) {
      final category = item.oldValue ?? item.newValue;
      if (category == null) continue;
      final bucket = feedback
          .where((f) => (f.oldValue ?? f.newValue) == category)
          .toList();
      rates[category] =
          bucket.where((f) => f.oldValue != f.newValue).length / bucket.length;
    }
    return ModelMetrics(
      accuracy: classifierFeedback.isEmpty
          ? 0
          : 1 - corrected / classifierFeedback.length,
      askRate:
          transactions.isEmpty ? 0 : askedTxnIds.length / transactions.length,
      correctionRates: rates,
    );
  }

  String? _categorySource(Transaction transaction) {
    try {
      final decoded =
          jsonDecode(transaction.confidenceJson) as Map<String, Object?>;
      final category = decoded['category'] as Map<String, Object?>?;
      return category?['src'] as String?;
    } on FormatException {
      return null;
    } on TypeError {
      return null;
    }
  }
}

class ModelMetricsScreen extends ConsumerWidget {
  const ModelMetricsScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final metrics = ref.watch(modelMetricsProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Model metrics (dev)')),
      body: switch (metrics) {
        AsyncData(:final value) => ListView(
            children: [
              ListTile(
                title: const Text('Classifier accuracy (last 100 feedback)'),
                trailing: Text('${(value.accuracy * 100).toStringAsFixed(1)}%'),
              ),
              ListTile(
                title: const Text('Ask rate'),
                trailing: Text('${(value.askRate * 100).toStringAsFixed(1)}%'),
              ),
              ...value.correctionRates.entries.map(
                (entry) => ListTile(
                  title: Text('${entry.key} correction rate'),
                  trailing: Text('${(entry.value * 100).toStringAsFixed(1)}%'),
                ),
              ),
            ],
          ),
        AsyncError() =>
          const Center(child: Text('Could not load model metrics')),
        _ => const Center(child: CircularProgressIndicator()),
      },
    );
  }
}
