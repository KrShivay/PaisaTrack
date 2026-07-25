import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format.dart';
import '../../core/theme/app_tokens.dart';
import '../../core/widgets/app_state_views.dart';
import '../../core/widgets/category_picker_sheet.dart';
import '../../core/widgets/correction_scope_sheet.dart';
import '../../core/widgets/transaction_components.dart';
import '../../data/db/database.dart' show Category;
import '../../data/db/database_provider.dart';
import '../../data/repositories/category_correction.dart';
import '../../data/repositories/transaction_repository.dart';
import '../settings/settings_screen.dart';
import '../transactions/transaction_detail_screen.dart';
import '../transactions/transaction_source_actions.dart';
import '../transactions/transactions_providers.dart';

class WeeklyReviewScreen extends ConsumerStatefulWidget {
  const WeeklyReviewScreen({super.key});

  @override
  ConsumerState<WeeklyReviewScreen> createState() => _WeeklyReviewScreenState();
}

class _WeeklyReviewScreenState extends ConsumerState<WeeklyReviewScreen> {
  final Set<String> _selectedIds = {};
  _ReviewMode _mode = _ReviewMode.quick;
  String _searchQuery = '';

  List<TransactionReviewItem> _filtered(List<TransactionReviewItem> items) {
    if (_searchQuery.isEmpty) return items;
    final q = _searchQuery.toLowerCase();
    return items.where((item) =>
        item.displayName.toLowerCase().contains(q) ||
        item.categoryName?.toLowerCase().contains(q) == true ||
        item.counterpartyKey?.toLowerCase().contains(q) == true,
    ).toList(growable: false);
  }

  @override
  Widget build(BuildContext context) {
    final queue = ref.watch(reviewQueueProvider);
    final summary = ref.watch(reviewQueueSummaryProvider).valueOrNull;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Review'),
        actions: [
          IconButton(
            tooltip: 'Settings',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const SettingsScreen(),
              ),
            ),
            icon: const Icon(Icons.settings_outlined),
          ),
        ],
      ),
      body: switch (queue) {
        AsyncData(:final value) when value.isEmpty => const _EmptyReviewState(),
        AsyncData(:final value) => _ReviewCentre(
            items: value,
            searchQuery: _searchQuery,
            onSearchChanged: (q) => setState(() => _searchQuery = q),
            summary: summary,
            mode: _mode,
            selectedIds: _visibleSelection(_filtered(value)),
            onModeChanged: (mode) => setState(() {
              _mode = mode;
              if (mode != _ReviewMode.list) _selectedIds.clear();
            }),
            onToggle: _toggle,
            onSelectAll: () => _selectAll(_filtered(value)),
            onConfirmSelected: () => _confirm(
              _visibleSelection(_filtered(value)),
              successLabel: 'transactions confirmed',
            ),
            onConfirmGroup: (ids) => _confirm(
              ids,
              successLabel: 'group transactions confirmed',
            ),
            onConfirmOne: (id) => _confirm(
              [id],
              successLabel: 'transaction confirmed',
            ),
            onLoadMore: () => ref
                .read(reviewQueueLimitProvider.notifier)
                .state += reviewPageSize,
          ),
        AsyncError() => const ErrorStateView(
            message: 'Could not load the review queue.',
          ),
        _ => const ListLoadingSkeleton(),
      },
    );
  }

  Set<String> _visibleSelection(List<TransactionReviewItem> items) {
    final visibleIds = items.map((item) => item.id).toSet();
    return _selectedIds.where(visibleIds.contains).toSet();
  }

  void _toggle(String id, bool selected) {
    setState(() {
      if (selected) {
        _selectedIds.add(id);
      } else {
        _selectedIds.remove(id);
      }
    });
  }

  void _selectAll(List<TransactionReviewItem> items) {
    final ids = items.map((item) => item.id).toSet();
    setState(() {
      if (ids.every(_selectedIds.contains)) {
        _selectedIds.removeAll(ids);
      } else {
        _selectedIds.addAll(ids);
      }
    });
  }

  Future<void> _confirm(
    Iterable<String> ids, {
    required String successLabel,
  }) async {
    final selected = ids.toSet();
    if (selected.isEmpty) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      final count = await _repository(ref).confirmMany(txnIds: selected);
      if (!mounted) return;
      setState(() => _selectedIds.removeAll(selected));
      messenger.showSnackBar(
        SnackBar(content: Text('$count $successLabel')),
      );
    } catch (error) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text('Confirmation failed: $error')),
      );
    }
  }
}

enum _ReviewMode { quick, list }

class _ReviewCentre extends StatelessWidget {
  const _ReviewCentre({
    required this.items,
    required this.searchQuery,
    required this.onSearchChanged,
    required this.summary,
    required this.mode,
    required this.selectedIds,
    required this.onModeChanged,
    required this.onToggle,
    required this.onSelectAll,
    required this.onConfirmSelected,
    required this.onConfirmGroup,
    required this.onConfirmOne,
    required this.onLoadMore,
  });

  final List<TransactionReviewItem> items;
  final String searchQuery;
  final ValueChanged<String> onSearchChanged;
  final ReviewQueueSummary? summary;
  final _ReviewMode mode;
  final Set<String> selectedIds;
  final ValueChanged<_ReviewMode> onModeChanged;
  final void Function(String id, bool selected) onToggle;
  final VoidCallback onSelectAll;
  final VoidCallback onConfirmSelected;
  final void Function(Set<String> ids) onConfirmGroup;
  final ValueChanged<String> onConfirmOne;
  final VoidCallback onLoadMore;

  @override
  Widget build(BuildContext context) {
    final loadedTotal = items.fold<double>(0, (sum, item) => sum + item.amount);
    final loadedMerchants = items
        .map((item) => item.counterpartyKey ?? item.displayName)
        .toSet()
        .length;
    final totalCount = summary?.count ?? items.length;
    final totalAmount = summary?.amount ?? loadedTotal;
    final merchantCount = summary?.merchantCount ?? loadedMerchants;
    return Column(
      children: [
        Padding(
          padding: AppSpacing.screen.copyWith(bottom: AppSpacing.sm),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                '$totalCount transactions need review',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                '${formatInr(totalAmount)} total · From $merchantCount merchants',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
              const SizedBox(height: AppSpacing.md),
              SegmentedButton<_ReviewMode>(
                segments: const [
                  ButtonSegment(
                    value: _ReviewMode.quick,
                    label: Text('One by one'),
                    icon: Icon(Icons.bolt_outlined),
                  ),
                  ButtonSegment(
                    value: _ReviewMode.list,
                    label: Text('All'),
                    icon: Icon(Icons.view_list_outlined),
                  ),
                ],
                selected: {mode},
                onSelectionChanged: (value) => onModeChanged(value.single),
              ),
            ],
          ),
        ),
        Expanded(
          child: switch (mode) {
            _ReviewMode.quick => _QuickReview(
                item: items.first,
                remainingCount: totalCount - 1,
                matchingGroupIds: {
                  for (final item in items)
                    if (item.counterpartyKey == items.first.counterpartyKey)
                      item.id,
                },
                onConfirm: () => onConfirmOne(items.first.id),
              ),
            _ReviewMode.list => _ReviewList(
                items: items,
                searchQuery: searchQuery,
                onSearchChanged: onSearchChanged,
                selectedIds: selectedIds,
                onToggle: onToggle,
                onSelectAll: onSelectAll,
                onConfirmSelected: onConfirmSelected,
                onConfirmGroup: onConfirmGroup,
                remainingCount: totalCount - items.length,
                onLoadMore: onLoadMore,
              ),
          },
        ),
      ],
    );
  }
}

class _QuickReview extends ConsumerWidget {
  const _QuickReview({
    required this.item,
    required this.remainingCount,
    required this.matchingGroupIds,
    required this.onConfirm,
  });

  final TransactionReviewItem item;
  final int remainingCount;
  final Set<String> matchingGroupIds;
  final VoidCallback onConfirm;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    return ListView(
      padding: AppSpacing.screen,
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TransactionAmount(
                  amount: item.amount,
                  direction: item.direction,
                  style: theme.textTheme.headlineMedium,
                ),
                const SizedBox(height: AppSpacing.sm),
                Text(item.displayName, style: theme.textTheme.titleLarge),
                const SizedBox(height: AppSpacing.lg),
                Text('Suggested category', style: theme.textTheme.labelLarge),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  item.categoryName ?? 'Choose a category',
                  style: theme.textTheme.titleMedium,
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  _reviewReason(item),
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                TransactionSourceActions(
                  txnId: item.id,
                  fallbackVpa: _vpaFromReviewItem(item),
                ),
                const SizedBox(height: AppSpacing.lg),
                FilledButton(
                  onPressed: onConfirm,
                  child: const Text('Category is correct'),
                ),
                const SizedBox(height: AppSpacing.sm),
                OutlinedButton(
                  onPressed: () => _showCorrectionSheet(
                    context,
                    ref,
                    item,
                    matchingGroupIds: matchingGroupIds,
                  ),
                  child: const Text('Change category'),
                ),
                TextButton.icon(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => TransactionDetailScreen(txnId: item.id),
                    ),
                  ),
                  icon: const Icon(Icons.open_in_new),
                  label: const Text('Review transaction details'),
                ),
                const SizedBox(height: AppSpacing.md),
                Text(
                  '${formatTxnTime(item.ts)}${remainingCount > 0 ? ' · $remainingCount remaining' : ''}',
                  style: theme.textTheme.bodySmall,
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

String _reviewReason(TransactionReviewItem item) {
  if (item.isLowTrustParse) {
    return 'Some transaction details need confirmation.';
  }
  if (item.categoryId == null) {
    return 'New merchant · Choose where this belongs.';
  }
  return 'Previously used for similar transactions.';
}

String? _vpaFromReviewItem(TransactionReviewItem item) {
  final key = item.counterpartyKey;
  return key?.startsWith('vpa:') == true ? key!.substring(4) : null;
}

class _ReviewList extends StatefulWidget {
  const _ReviewList({
    required this.items,
    required this.searchQuery,
    required this.onSearchChanged,
    required this.selectedIds,
    required this.onToggle,
    required this.onSelectAll,
    required this.onConfirmSelected,
    required this.onConfirmGroup,
    required this.remainingCount,
    required this.onLoadMore,
  });

  final List<TransactionReviewItem> items;
  final String searchQuery;
  final ValueChanged<String> onSearchChanged;
  final Set<String> selectedIds;
  final void Function(String id, bool selected) onToggle;
  final VoidCallback onSelectAll;
  final VoidCallback onConfirmSelected;
  final void Function(Set<String> ids) onConfirmGroup;
  final int remainingCount;
  final VoidCallback onLoadMore;

  @override
  State<_ReviewList> createState() => _ReviewListState();
}

class _ReviewListState extends State<_ReviewList> {
  final _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _searchController.text = widget.searchQuery;
  }

  @override
  void didUpdateWidget(covariant _ReviewList oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.searchQuery != _searchController.text) {
      _searchController.text = widget.searchQuery;
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final filteredItems = widget.items.where((item) {
      if (widget.searchQuery.isEmpty) return true;
      final q = widget.searchQuery.toLowerCase();
      final nameMatches = item.displayName.toLowerCase().contains(q);
      final categoryMatches =
          item.categoryName?.toLowerCase().contains(q) == true;
      final keyMatches =
          item.counterpartyKey?.toLowerCase().contains(q) == true;
      return nameMatches || categoryMatches || keyMatches;
    }).toList(growable: false);

    final groups = <String, List<TransactionReviewItem>>{};
    for (final item in filteredItems) {
      final key = item.counterpartyKey ??
          'display:${item.displayName.trim().toLowerCase()}';
      groups.putIfAbsent(key, () => []).add(item);
    }
    final allSelected = filteredItems.isNotEmpty &&
        filteredItems.every((item) => widget.selectedIds.contains(item.id));
    final someSelected = widget.selectedIds.isNotEmpty;

    return ListView(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      children: [
        Padding(
          padding: const EdgeInsets.all(AppSpacing.sm),
          child: TextField(
            key: const ValueKey('review_search_field'),
            controller: _searchController,
            decoration: InputDecoration(
              hintText: 'Search merchants or categories...',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: widget.searchQuery.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear),
                      onPressed: () {
                        _searchController.clear();
                        widget.onSearchChanged('');
                        FocusScope.of(context).unfocus();
                      },
                    )
                  : null,
              isDense: true,
              border: const OutlineInputBorder(),
            ),
            onChanged: (value) => widget.onSearchChanged(value),
          ),
        ),
        if (widget.remainingCount > 0 && widget.searchQuery.isNotEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: AppSpacing.xs),
            child: Text(
              'Searching ${widget.items.length} loaded of ${widget.items.length + widget.remainingCount} items — load more to widen.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
          child: Row(
            children: [
              Checkbox(
                key: const ValueKey('select_all_review'),
                value: allSelected
                    ? true
                    : someSelected
                        ? null
                        : false,
                tristate: true,
                onChanged: (_) => widget.onSelectAll(),
              ),
              const Expanded(child: Text('Select all')),
              FilledButton.icon(
                onPressed: someSelected ? widget.onConfirmSelected : null,
                icon: const Icon(Icons.done_all),
                label: Text('Confirm (${widget.selectedIds.length})'),
              ),
            ],
          ),
        ),
        for (final entry in groups.entries) ...[
          _ReviewGroupHeader(
            groupKey: entry.key,
            label: entry.value.first.displayName,
            count: entry.value.length,
            total: entry.value.fold(0, (sum, item) => sum + item.amount),
            onConfirm: () =>
                widget.onConfirmGroup(entry.value.map((item) => item.id).toSet()),
          ),
          for (final item in entry.value) ...[
            _ReviewTile(
              item: item,
              matchingGroupIds: entry.value.map((item) => item.id).toSet(),
              selected: widget.selectedIds.contains(item.id),
              onSelected: (selected) => widget.onToggle(item.id, selected),
            ),
            const Divider(height: 1),
          ],
        ],
        if (widget.remainingCount > 0)
          Padding(
            padding: AppSpacing.screen,
            child: OutlinedButton.icon(
              onPressed: widget.onLoadMore,
              icon: const Icon(Icons.expand_more),
              label: Text(
                'Load ${widget.remainingCount.clamp(0, reviewPageSize)} more',
              ),
            ),
          ),
      ],
    );
  }
}

class _ReviewGroupHeader extends StatelessWidget {
  const _ReviewGroupHeader({
    required this.groupKey,
    required this.label,
    required this.count,
    required this.total,
    required this.onConfirm,
  });

  final String groupKey;
  final String label;
  final int count;
  final double total;
  final VoidCallback onConfirm;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Theme.of(context).colorScheme.surfaceContainer,
      child: Padding(
        padding: const EdgeInsets.only(
          left: AppSpacing.md,
          right: AppSpacing.sm,
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                '$count similar transaction${count == 1 ? '' : 's'} from $label\n${formatInr(total)} combined',
                style: Theme.of(context).textTheme.labelLarge,
              ),
            ),
            TextButton(
              key: ValueKey('confirm_group_$groupKey'),
              onPressed: onConfirm,
              child:
                  Text(count == 1 ? 'Confirm category' : 'Confirm all $count'),
            ),
          ],
        ),
      ),
    );
  }
}

class _ReviewTile extends ConsumerWidget {
  const _ReviewTile({
    required this.item,
    required this.matchingGroupIds,
    required this.selected,
    required this.onSelected,
  });

  final TransactionReviewItem item;
  final Set<String> matchingGroupIds;
  final bool selected;
  final ValueChanged<bool> onSelected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Row(
      children: [
        Padding(
          padding: const EdgeInsets.only(left: AppSpacing.sm),
          child: Checkbox(
            key: ValueKey('select_${item.id}'),
            value: selected,
            onChanged: (value) => onSelected(value ?? false),
          ),
        ),
        Expanded(
          child: Column(
            children: [
              TransactionTile(
                merchantName: item.displayName,
                amount: item.amount,
                direction: item.direction,
                categoryLabel: item.categoryName ?? 'Uncategorized',
                timeLabel: formatTxnTime(item.ts),
                categoryId: item.categoryId,
                categoryIcon: item.categoryIcon,
                statusLabel: 'Category needs review',
                selected: selected,
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => TransactionDetailScreen(txnId: item.id),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(
                  left: AppSpacing.md,
                  right: AppSpacing.sm,
                  bottom: AppSpacing.xs,
                ),
                child: Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    onPressed: () => _showCorrectionSheet(
                      context,
                      ref,
                      item,
                      matchingGroupIds: matchingGroupIds,
                    ),
                    icon: const Icon(Icons.category_outlined, size: 18),
                    label: const Text('Change category'),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _EmptyReviewState extends StatelessWidget {
  const _EmptyReviewState();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: AppSpacing.screen,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.task_alt,
              size: 48,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(height: AppSpacing.md),
            Text('All caught up', style: theme.textTheme.titleLarge),
            const SizedBox(height: AppSpacing.xs),
            Text(
              'New uncertain transactions will appear here.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

Future<void> _showCorrectionSheet(
  BuildContext context,
  WidgetRef ref,
  TransactionReviewItem item, {
  Set<String> matchingGroupIds = const {},
}) async {
  final screenContext = context;
  final categories = await ref.read(categoryListProvider.future);
  if (!context.mounted || categories.isEmpty) return;

  final category = await showModalBottomSheet<Category>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) => CategoryPickerSheet(
      categories: categories,
      currentCategoryId: item.categoryId,
      suggestedCategoryIds: [
        if (item.categoryId != null) item.categoryId!,
        'transfers',
        'other',
      ],
      explanations: {
        if (item.categoryId != null)
          item.categoryId!: 'Previously used for similar transactions',
        'transfers': 'Use for self-transfers or excluded movement',
      },
    ),
  );

  if (category == null || !context.mounted) return;
  final reusableMatch =
      item.counterpartyKey != null && !item.counterpartyKey!.startsWith('txn:');
  final groupScopeAvailable = matchingGroupIds.length > 1;
  final scope = await showCorrectionScopeSheet(
    context: context,
    categoryName: category.name,
    availableScopes: {
      CorrectionScope.thisTransaction,
      if (groupScopeAvailable) CorrectionScope.matchingGroup,
      if (reusableMatch) ...{
        CorrectionScope.futureMatching,
        CorrectionScope.existingAndFuture,
      },
    },
    initialScope: defaultCorrectionScope(
      groupScopeAvailable
          ? CorrectionContext.groupReview
          : reusableMatch
              ? CorrectionContext.newMerchant
              : CorrectionContext.oneOffEdit,
    ),
    matchingCount: matchingGroupIds.length,
  );
  if (scope == null) return;
  final result = await _repository(ref).correctCategory(
    txnId: item.id,
    categoryId: category.id,
    scope: scope,
    context: 'batch_review',
    matchingTxnIds: matchingGroupIds,
  );
  if (screenContext.mounted) {
    ScaffoldMessenger.of(screenContext).showSnackBar(
      SnackBar(
        content: Text(
          result.ruleCreated
              ? 'Category updated. PaisaTrack will remember this.'
              : result.affectedTransactionCount > 1
                  ? '${result.affectedTransactionCount} transactions updated.'
                  : 'Category updated.',
        ),
      ),
    );
  }
}

TransactionRepository _repository(WidgetRef ref) {
  final database = ref.read(appDatabaseProvider).valueOrNull;
  if (database == null) {
    throw StateError('Database is not ready');
  }
  return ref.read(transactionRepositoryProvider(database));
}
