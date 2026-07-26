import 'dart:convert';

import 'package:drift/drift.dart' hide Column;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_tokens.dart';
import '../../data/confidence_payload.dart';
import '../../data/db/database.dart';
import '../../data/db/database_provider.dart';

class ModelMetrics {
  const ModelMetrics({
    required this.accuracy,
    required this.askRate,
    required this.correctionRates,
    this.totalTransactions = 0,
    this.parseSourceCounts = const {},
    this.averageParseConfidence = 0.0,
    this.averageParseConfidenceBySource = const {},
  });

  final double accuracy;
  final double askRate;
  final Map<String, double> correctionRates;
  final int totalTransactions;
  final Map<String, int> parseSourceCounts;
  final double averageParseConfidence;
  final Map<String, double?> averageParseConfidenceBySource;
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

    final sourceCounts = <String, int>{};
    final confidenceBySource = <String, ({double sum, int n})>{};
    double totalConfidence = 0.0;
    int confidenceCount = 0;

    for (final txn in transactions) {
      final src = txn.parseSource;
      sourceCounts[src] = (sourceCounts[src] ?? 0) + 1;
      final conf = parseConfidenceFromJson(txn.confidenceJson);
      if (conf != null) {
        totalConfidence += conf;
        confidenceCount++;
        final prior = confidenceBySource[src] ?? (sum: 0.0, n: 0);
        confidenceBySource[src] = (sum: prior.sum + conf, n: prior.n + 1);
      }
    }

    final bySourceAvg = <String, double?>{
      for (final entry in confidenceBySource.entries)
        entry.key: entry.value.n > 0 ? entry.value.sum / entry.value.n : null,
    };

    return ModelMetrics(
      accuracy: classifierFeedback.isEmpty
          ? 0
          : 1 - corrected / classifierFeedback.length,
      askRate:
          transactions.isEmpty ? 0 : askedTxnIds.length / transactions.length,
      correctionRates: rates,
      totalTransactions: transactions.length,
      parseSourceCounts: sourceCounts,
      averageParseConfidence:
          confidenceCount > 0 ? totalConfidence / confidenceCount : 0.0,
      averageParseConfidenceBySource: bySourceAvg,
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
            padding: const EdgeInsets.all(AppSpacing.md),
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.lg),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceAround,
                        children: [
                          _MetricStat(
                            label: 'Accuracy',
                            value:
                                '${(value.accuracy * 100).toStringAsFixed(1)}%',
                          ),
                          _MetricStat(
                            label: 'Ask Rate',
                            value:
                                '${(value.askRate * 100).toStringAsFixed(1)}%',
                          ),
                          _MetricStat(
                            label: 'Transactions',
                            value: '${value.totalTransactions}',
                          ),
                        ],
                      ),
                      if (value.averageParseConfidence > 0) ...[
                        const Divider(height: AppSpacing.xl),
                        Text(
                          'Avg Parse Confidence: ${(value.averageParseConfidence * 100).toStringAsFixed(1)}%',
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              if (value.parseSourceCounts.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.md),
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
                  child: Text(
                    'Parse Source Breakdown',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                ...value.parseSourceCounts.entries.map((entry) {
                  final avgConf =
                      value.averageParseConfidenceBySource[entry.key];
                  final avgText = avgConf != null
                      ? ' · Avg conf ${(avgConf * 100).toStringAsFixed(1)}%'
                      : '';
                  return ListTile(
                    title: Text(entry.key),
                    subtitle: avgText.isNotEmpty ? Text(avgText.trim()) : null,
                    trailing: Text('${entry.value}'),
                  );
                }),
              ],
              if (value.correctionRates.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.md),
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
                  child: Text(
                    'Category Correction Rates',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                ...value.correctionRates.entries.map(
                  (entry) => ListTile(
                    title: Text('${entry.key} correction rate'),
                    trailing:
                        Text('${(entry.value * 100).toStringAsFixed(1)}%'),
                  ),
                ),
              ],
            ],
          ),
        AsyncError() =>
          const Center(child: Text('Could not load model metrics')),
        _ => const Center(child: CircularProgressIndicator()),
      },
    );
  }
}

class _MetricStat extends StatelessWidget {
  const _MetricStat({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          value,
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
              ),
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          label,
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }
}
