import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/db/database_provider.dart';
import '../../enrichment/source_currency_repair_service.dart';

/// Read-only source-evidence proposal for the transaction currently in detail.
final sourceCurrencyRepairPreviewProvider =
    FutureProvider.autoDispose.family<SourceCurrencyRepairPreview?, String>(
  (ref, transactionId) async {
    final database = await ref.watch(appDatabaseProvider.future);
    return SourceCurrencyRepairService(database).preview(transactionId);
  },
);
