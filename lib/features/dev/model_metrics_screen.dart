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
          ..orderBy([(f) => OrderingTerm.desc(f.createdAt)])
          ..limit(100))
        .get();
    final categoryFeedback =
        feedback.where((f) => f.field == 'category_id').toList();
    final corrected =
        categoryFeedback.where((f) => f.oldValue != f.newValue).length;
    final transactions = await _database.select(_database.transactions).get();
    final asked = transactions.where((t) => t.status == 'asked').length;
    final rates = <String, double>{};
    for (final item in categoryFeedback) {
      final category = item.newValue;
      if (category == null) continue;
      final bucket =
          categoryFeedback.where((f) => f.newValue == category).toList();
      rates[category] =
          bucket.where((f) => f.oldValue != f.newValue).length / bucket.length;
    }
    return ModelMetrics(
      accuracy: categoryFeedback.isEmpty
          ? 0
          : 1 - corrected / categoryFeedback.length,
      askRate: transactions.isEmpty ? 0 : asked / transactions.length,
      correctionRates: rates,
    );
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
