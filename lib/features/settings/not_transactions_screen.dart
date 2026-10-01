import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format.dart';
import '../../data/db/database.dart' show Transaction;
import '../../data/db/database_provider.dart';
import '../../data/repositories/sms_disposition_repository.dart';
import '../../intelligence/derived_reads_service.dart';

/// Persisted corrections remain reversible even after the source SMS expires.
class NotTransactionsScreen extends ConsumerStatefulWidget {
  const NotTransactionsScreen({super.key});

  @override
  ConsumerState<NotTransactionsScreen> createState() =>
      _NotTransactionsScreenState();
}

class _NotTransactionsScreenState extends ConsumerState<NotTransactionsScreen> {
  Future<List<({Transaction transaction, String smsId})>>? _rows;

  Future<List<({Transaction transaction, String smsId})>> _load() async {
    final database = await ref.read(appDatabaseProvider.future);
    return SmsDispositionRepository(database).listMarkedTransactions();
  }

  @override
  Widget build(BuildContext context) {
    _rows ??= _load();
    return Scaffold(
      appBar: AppBar(title: const Text('Not transactions')),
      body: FutureBuilder<List<({Transaction transaction, String smsId})>>(
        future: _rows,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          final rows = snapshot.data ?? const [];
          if (rows.isEmpty) {
            return const Center(child: Text('No corrected messages.'));
          }
          return ListView.builder(
            itemCount: rows.length,
            itemBuilder: (context, index) {
              final row = rows[index];
              final transaction = row.transaction;
              return ListTile(
                title: Text(transaction.merchantRaw ?? 'Unlabeled message'),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      DateTime.fromMillisecondsSinceEpoch(transaction.ts)
                          .toLocal()
                          .toString()
                          .substring(0, 16),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      formatSourceAmount(
                        transaction.amount,
                        currencyCode: transaction.currencyCode,
                        currencySymbol: transaction.currencySymbol,
                      ),
                    ),
                  ],
                ),
                onTap: () async {
                  final database = await ref.read(appDatabaseProvider.future);
                  final dispositions = SmsDispositionRepository(
                    database,
                    derivedReadsService:
                        await ref.read(derivedReadsServiceProvider.future),
                  );
                  await dispositions.restore(row.smsId);
                  if (mounted) {
                    setState(() {
                      _rows = _load();
                    });
                  }
                },
                leading: const Icon(Icons.undo),
              );
            },
          );
        },
      ),
    );
  }
}
