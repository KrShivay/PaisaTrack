import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/db/database_provider.dart';
import '../../data/repositories/merchant_category_suggestion_repository.dart';
import 'transactions_providers.dart';

/// Release gate stays closed until the existing T-177a/T-177f exit criteria
/// authorize production suggestions. Tests may override this provider.
final categoryMemorySuggestionsEnabledProvider = Provider<bool>((ref) => false);

final merchantCategorySuggestionProvider =
    FutureProvider.autoDispose.family<MerchantCategorySuggestion?, String>(
  (ref, transactionId) async {
    if (!ref.watch(categoryMemorySuggestionsEnabledProvider)) return null;
    final detail =
        ref.watch(transactionDetailProvider(transactionId)).valueOrNull;
    if (detail == null) return null;
    final database = await ref.watch(appDatabaseProvider.future);
    return MerchantCategorySuggestionRepository(database)
        .suggestionFor(transactionId);
  },
);
