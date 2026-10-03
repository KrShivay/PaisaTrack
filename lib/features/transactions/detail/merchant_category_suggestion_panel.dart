import 'package:flutter/material.dart';

import '../../../data/repositories/merchant_category_suggestion_repository.dart';

class MerchantCategorySuggestionPanel extends StatelessWidget {
  const MerchantCategorySuggestionPanel({
    super.key,
    required this.suggestion,
    required this.onAccept,
    this.isSaving = false,
  });

  final MerchantCategorySuggestion suggestion;
  final VoidCallback onAccept;
  final bool isSaving;

  @override
  Widget build(BuildContext context) => Card(
        key: const ValueKey('merchant-category-suggestion'),
        margin: const EdgeInsets.only(top: 12),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Based on your past category choices',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 4),
              Text(
                '${suggestion.supportingTransactionCount} prior transactions '
                'for this payee have this category.',
              ),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: isSaving ? null : onAccept,
                  child: Text(
                    isSaving ? 'Saving…' : 'Use ${suggestion.categoryName}',
                  ),
                ),
              ),
            ],
          ),
        ),
      );
}
