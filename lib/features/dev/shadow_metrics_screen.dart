import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../capture/shadow_pipeline.dart';
import '../../data/db/database.dart';
import '../../data/db/database_provider.dart';

class ShadowMetrics {
  const ShadowMetrics({
    required this.shadowRows,
    required this.productionRows,
    required this.gained,
    required this.lost,
    required this.amountDeltas,
    required this.labelDisagreements,
  });

  final int shadowRows;
  final int productionRows;
  final int gained;
  final int lost;
  final int amountDeltas;
  final int labelDisagreements;

  Map<String, Object> toJson() {
    return {
      'shadow_rows': shadowRows,
      'production_rows': productionRows,
      'gained': gained,
      'lost': lost,
      'amount_deltas': amountDeltas,
      'label_disagreements': labelDisagreements,
    };
  }
}

final shadowMetricsProvider = FutureProvider<ShadowMetrics>((ref) async {
  final database = await ref.watch(appDatabaseProvider.future);
  return ShadowMetricsRepository(database).load();
});

class ShadowMetricsRepository {
  const ShadowMetricsRepository(this._database);

  final AppDatabase _database;

  Future<ShadowMetrics> load() async {
    final shadowRows =
        await _database.select(_database.shadowTransactions).get();
    final productionRows = await (_database.select(_database.transactions)
          ..where((row) => row.smsId.isNotNull()))
        .get();
    final diff = const ShadowDiffCalculator().compare(
      shadow: shadowRows.map(
        (row) => ShadowSnapshot(
          sourceId: row.sourceId,
          outcome: _outcome(row.outcome),
          amountPaise: row.amountPaise,
          direction: row.direction,
          merchantKey: row.merchantKey,
          categoryId: row.categoryId,
          updatedAt: row.updatedAt,
        ),
      ),
      production: productionRows.map(
        (row) => ProductionSnapshot(
          sourceId: row.smsId!,
          amountPaise: (row.amount * 100).round(),
          direction: row.direction,
          merchantKey: row.merchantId ?? row.merchantRaw,
          categoryId: row.categoryId,
        ),
      ),
    );
    return ShadowMetrics(
      shadowRows: shadowRows.length,
      productionRows: productionRows.length,
      gained: diff.gained,
      lost: diff.lost,
      amountDeltas: diff.amountDeltas,
      labelDisagreements: diff.labelDisagreements,
    );
  }

  ShadowOutcome _outcome(String value) {
    return switch (value) {
      'parsed' => ShadowOutcome.parsed,
      'unparsed' => ShadowOutcome.unparsed,
      _ => ShadowOutcome.error,
    };
  }
}

class ShadowMetricsScreen extends ConsumerWidget {
  const ShadowMetricsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final metrics = ref.watch(shadowMetricsProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Shadow metrics (dev)')),
      body: metrics.when(
        data: (value) => ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Text(
              'All measurements stay on this device. The shadow pipeline is '
              'never promoted from this screen.',
            ),
            const SizedBox(height: 16),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    _MetricRow('Shadow rows', value.shadowRows),
                    _MetricRow('Production rows', value.productionRows),
                    _MetricRow('Records gained', value.gained),
                    _MetricRow('Records lost', value.lost),
                    _MetricRow('Amount deltas', value.amountDeltas),
                    _MetricRow(
                      'Label disagreements',
                      value.labelDisagreements,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: () => _copyReport(context, value),
              icon: const Icon(Icons.copy),
              label: const Text('Copy local report'),
            ),
          ],
        ),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) =>
            Center(child: Text('Unable to load metrics: $error')),
      ),
    );
  }

  Future<void> _copyReport(BuildContext context, ShadowMetrics metrics) async {
    await Clipboard.setData(ClipboardData(text: jsonEncode(metrics.toJson())));
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Local shadow report copied')),
      );
    }
  }
}

class _MetricRow extends StatelessWidget {
  const _MetricRow(this.label, this.value);

  final String label;
  final int value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [Text(label), Text('$value')],
      ),
    );
  }
}
