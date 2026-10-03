import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paisatrack/features/transactions/merchant_category_suggestion_provider.dart';

void main() {
  test('production gate defaults to no category-memory suggestion', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    expect(
      await container.read(merchantCategorySuggestionProvider('txn').future),
      isNull,
    );
    expect(container.read(categoryMemorySuggestionsEnabledProvider), isFalse);
  });
}
