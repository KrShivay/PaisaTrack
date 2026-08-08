import 'package:flutter/material.dart';

import '../../data/repositories/category_correction.dart';
import '../theme/app_tokens.dart';
import 'bloom/bloom_sheet_scaffold.dart';

Future<CorrectionScope?> showCorrectionScopeSheet({
  required BuildContext context,
  required String categoryName,
  required Set<CorrectionScope> availableScopes,
  required CorrectionScope initialScope,
  int matchingCount = 0,
}) {
  final effectiveInitial = availableScopes.contains(initialScope)
      ? initialScope
      : CorrectionScope.thisTransaction;
  return showBloomModalSheet<CorrectionScope>(
    context: context,
    builder: (context) => CorrectionScopeSheet(
      categoryName: categoryName,
      availableScopes: availableScopes,
      initialScope: effectiveInitial,
      matchingCount: matchingCount,
    ),
  );
}

class CorrectionScopeSheet extends StatefulWidget {
  const CorrectionScopeSheet({
    super.key,
    required this.categoryName,
    required this.availableScopes,
    required this.initialScope,
    this.matchingCount = 0,
  });

  final String categoryName;
  final Set<CorrectionScope> availableScopes;
  final CorrectionScope initialScope;
  final int matchingCount;

  @override
  State<CorrectionScopeSheet> createState() => _CorrectionScopeSheetState();
}

class _CorrectionScopeSheetState extends State<CorrectionScopeSheet> {
  late CorrectionScope _scope = widget.initialScope;

  @override
  Widget build(BuildContext context) {
    final scopes = CorrectionScope.values
        .where(widget.availableScopes.contains)
        .toList(growable: false);
    return BloomSheetScaffold(
      showBack: false,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            0,
            AppSpacing.lg,
            AppSpacing.lg,
          ),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Apply ${widget.categoryName} to:',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: AppSpacing.md),
                RadioGroup<CorrectionScope>(
                  groupValue: _scope,
                  onChanged: (value) {
                    if (value != null) setState(() => _scope = value);
                  },
                  child: Column(
                    children: [
                      for (final scope in scopes)
                        RadioListTile<CorrectionScope>(
                          contentPadding: EdgeInsets.zero,
                          value: scope,
                          title: Text(_scopeLabel(scope, widget.matchingCount)),
                          subtitle: Text(_scopeExplanation(scope)),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),
                FilledButton(
                  onPressed: () => Navigator.pop(context, _scope),
                  child: const Text('Apply category'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

String _scopeLabel(CorrectionScope scope, int matchingCount) {
  return switch (scope) {
    CorrectionScope.thisTransaction => 'This transaction only',
    CorrectionScope.futureMatching => 'Future transactions from this merchant',
    CorrectionScope.existingAndFuture =>
      'Existing and future matching transactions',
    CorrectionScope.matchingGroup => matchingCount > 0
        ? 'Matching transactions in this group ($matchingCount)'
        : 'Matching transactions in this group',
    CorrectionScope.updateFutureRule => 'Update the future rule',
  };
}

String _scopeExplanation(CorrectionScope scope) {
  return switch (scope) {
    CorrectionScope.thisTransaction =>
      'Only this transaction changes. Similar transactions stay unchanged.',
    CorrectionScope.futureMatching =>
      'This transaction changes and PaisaTrack learns for future matches.',
    CorrectionScope.existingAndFuture =>
      'Matching history changes now, and future matches use this category.',
    CorrectionScope.matchingGroup =>
      'Only the transactions shown in this review group change.',
    CorrectionScope.updateFutureRule =>
      'Future matches use this category. Existing history stays unchanged.',
  };
}
