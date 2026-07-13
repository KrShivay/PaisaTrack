import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format.dart';
import '../../core/theme/app_tokens.dart';
import '../../core/widgets/app_state_views.dart';
import '../../core/widgets/category_picker_sheet.dart';
import '../../core/widgets/transaction_filter_sheet.dart';
import '../../core/widgets/transaction_components.dart';
import '../../data/db/database.dart' show Category;
import '../../data/db/database_provider.dart';
import '../../data/models/normalized_transaction_record.dart';
import '../../data/repositories/transaction_repository.dart';
import '../settings/settings_screen.dart';
import 'manual_entry_screen.dart';
import 'transaction_detail_screen.dart';
import 'transaction_filter_context_providers.dart';
import 'transactions_providers.dart';

/// Lists parsed transactions, newest first, with search, a direction filter,
/// date-group headers, and pull-to-refresh.
///
/// Tiles follow the design-system recipe (docs/design-system.md §9): leading
/// category tile, merchant title, "category · time" subtitle, signed tabular
/// amount in the semantic direction color. Non-spending categories (transfers,
/// cash withdrawals) render neutral, not debit red (§5).
///
/// [initialCategoryId] / [initialMerchant] open the screen pre-filtered (used
/// by the dashboard tap-through); when set, the screen shows a back button and
/// hides the FAB.
class TransactionsScreen extends ConsumerStatefulWidget {
  const TransactionsScreen({
    super.key,
    this.initialCategoryId,
    this.initialCategoryName,
    this.initialMerchant,
  });

  final String? initialCategoryId;
  final String? initialCategoryName;
  final String? initialMerchant;

  bool get _isFiltered => initialCategoryId != null || initialMerchant != null;

  @override
  ConsumerState<TransactionsScreen> createState() => _TransactionsScreenState();
}

class _TransactionsScreenState extends ConsumerState<TransactionsScreen> {
  final _searchController = TextEditingController();
  String _query = '';
  TransactionDirectionFilter _direction = TransactionDirectionFilter.all;
  TransactionFilters _filters = const TransactionFilters();
  final Set<String> _selected = {};
  bool _applyingBulk = false;

  bool get _selectionMode => _selected.isNotEmpty;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _toggleSelected(String id) {
    setState(() {
      if (!_selected.remove(id)) _selected.add(id);
    });
  }

  void _clearSelection() => setState(_selected.clear);

  void _openDetail(BuildContext context, String id) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => TransactionDetailScreen(txnId: id),
      ),
    );
  }

  /// Bulk-recategorize the selected transactions through the same
  /// feedback-recording path the detail screen uses, so corrections still
  /// train the categorizer.
  Future<void> _categorizeSelected() async {
    final categories = await ref.read(categoryListProvider.future);
    if (!mounted) return;
    final chosen = await showModalBottomSheet<Category>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => CategoryPickerSheet(
        categories: categories,
        title: 'Move to category',
      ),
    );
    if (chosen == null || !mounted) return;

    final ids = _selected.toList(growable: false);
    setState(() => _applyingBulk = true);
    try {
      final database = await ref.read(appDatabaseProvider.future);
      final repository = ref.read(transactionRepositoryProvider(database));
      for (final id in ids) {
        await repository.updateWithFeedback(
          txnId: id,
          categoryId: Value(chosen.id),
          context: 'bulk_categorize',
        );
      }
      if (!mounted) return;
      _clearSelection();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            ids.length == 1
                ? 'Moved to ${chosen.name}'
                : '${ids.length} moved to ${chosen.name}',
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _applyingBulk = false);
    }
  }

  List<TransactionListItem> _applyFilters(
    List<TransactionListItem> items,
    Set<String> recurringMerchantIds,
    Set<String> anomalyTransactionIds,
  ) {
    return items.where((item) {
      if (widget.initialCategoryId != null &&
          item.categoryId != widget.initialCategoryId) {
        return false;
      }
      if (widget.initialMerchant != null &&
          item.displayName != widget.initialMerchant) {
        return false;
      }
      switch (_direction) {
        case TransactionDirectionFilter.spent:
          if (item.direction != TransactionDirection.debit) return false;
        case TransactionDirectionFilter.received:
          if (item.direction != TransactionDirection.credit) return false;
        case TransactionDirectionFilter.all:
          break;
      }
      return _filters.matches(
            item,
            recurringMerchantIds: recurringMerchantIds,
            anomalyTransactionIds: anomalyTransactionIds,
          ) &&
          _filters.matchesSearch(item, _query);
    }).toList(growable: false);
  }

  Future<void> _openFilters(List<TransactionListItem> transactions) async {
    final selected = await showTransactionFilterSheet(
      context: context,
      initialFilters: _filters,
      transactions: transactions,
    );
    if (selected != null && mounted) setState(() => _filters = selected);
  }

  Future<void> _refresh() async {
    ref.invalidate(transactionListProvider);
    await ref.read(transactionListProvider.future);
  }

  @override
  Widget build(BuildContext context) {
    final transactions = ref.watch(transactionListProvider);
    final recurringMerchantIds =
        ref.watch(recurringMerchantIdsProvider).valueOrNull ?? const <String>{};
    final anomalyTransactionIds =
        ref.watch(anomalyTransactionIdsProvider).valueOrNull ??
            const <String>{};

    return Scaffold(
      appBar: _selectionMode
          ? AppBar(
              leading: IconButton(
                icon: const Icon(Icons.close),
                tooltip: 'Clear selection',
                onPressed: _clearSelection,
              ),
              title: Text('${_selected.length} selected'),
              actions: [
                IconButton(
                  icon: const Icon(Icons.label_outline),
                  tooltip: 'Categorize',
                  onPressed: _applyingBulk ? null : _categorizeSelected,
                ),
              ],
            )
          : AppBar(
              title: Text(
                widget._isFiltered
                    ? (widget.initialCategoryName ??
                        widget.initialMerchant ??
                        'Transactions')
                    : 'Transactions',
              ),
              actions: [
                IconButton(
                  tooltip: _filters.isEmpty
                      ? 'Filter transactions'
                      : 'Filter transactions, ${_filters.activeCount} active',
                  onPressed: transactions.valueOrNull == null
                      ? null
                      : () => _openFilters(transactions.valueOrNull!),
                  icon: Badge(
                    isLabelVisible: !_filters.isEmpty,
                    label: Text('${_filters.activeCount}'),
                    child: const Icon(Icons.tune),
                  ),
                ),
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
      body: Column(
        children: [
          _FilterBar(
            controller: _searchController,
            direction: _direction,
            onQueryChanged: (value) => setState(() => _query = value),
            onDirectionChanged: (value) => setState(() => _direction = value),
            filters: _filters,
            onRemoveFilter: (field) => setState(
              () => _filters = _filters.clear(field),
            ),
          ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: _refresh,
              child: switch (transactions) {
                AsyncData(:final value) => _buildList(
                    context,
                    value,
                    recurringMerchantIds,
                    anomalyTransactionIds,
                  ),
                AsyncError() => ErrorStateView(
                    message: 'Could not load transactions.',
                    onRetry: _refresh,
                  ),
                _ => const ListLoadingSkeleton(),
              },
            ),
          ),
        ],
      ),
      floatingActionButton: widget._isFiltered || _selectionMode
          ? null
          : FloatingActionButton(
              tooltip: 'Add transaction',
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (context) => const ManualEntryScreen(),
                ),
              ),
              child: const Icon(Icons.add),
            ),
    );
  }

  Widget _buildList(
    BuildContext context,
    List<TransactionListItem> all,
    Set<String> recurringMerchantIds,
    Set<String> anomalyTransactionIds,
  ) {
    final filtered = _applyFilters(
      all,
      recurringMerchantIds,
      anomalyTransactionIds,
    );

    if (filtered.isEmpty) {
      final searching = _query.trim().isNotEmpty ||
          _direction != TransactionDirectionFilter.all ||
          !_filters.isEmpty ||
          widget._isFiltered;
      // Empty state must stay scrollable so pull-to-refresh still works.
      return ListView(
        children: [
          SizedBox(
            height: MediaQuery.of(context).size.height * 0.6,
            child: searching
                ? const EmptyStateView(
                    illustration: AppIllustrations.spendAnalysis,
                    title: 'No matches',
                    message: 'Try a different search or filter.',
                  )
                : EmptyStateView(
                    illustration: AppIllustrations.wallet,
                    title: 'No transactions yet',
                    message:
                        'Transactions read from your SMS will appear here. '
                        'You can also add one manually.',
                    actionLabel: 'Add transaction',
                    onAction: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (context) => const ManualEntryScreen(),
                      ),
                    ),
                  ),
          ),
        ],
      );
    }

    // Flatten into header + tile rows, grouped by day.
    final rows = <_Row>[];
    String? currentGroup;
    for (final item in filtered) {
      final group = formatDateGroup(item.ts);
      if (group != currentGroup) {
        currentGroup = group;
        rows.add(_Row.header(group));
      }
      rows.add(_Row.tile(item));
    }

    final animate = !MediaQuery.of(context).disableAnimations;

    return ListView.builder(
      itemCount: rows.length,
      itemBuilder: (context, index) {
        final row = rows[index];
        if (row.header != null) {
          return _GroupHeader(label: row.header!);
        }
        final item = row.item!;
        final tile = TransactionTile(
          merchantName: item.displayName,
          amount: item.amount,
          direction: item.direction,
          categoryLabel: item.categoryName ?? 'Uncategorized',
          timeLabel: formatTxnTime(item.ts),
          categoryId: item.categoryId,
          categoryIcon: item.categoryIcon,
          categoryIsSpending: item.categoryIsSpending,
          statusLabel: switch (item.status) {
            'needs_review' => 'Category needs review',
            'asked' => 'Waiting for review',
            _ => null,
          },
          selected: _selected.contains(item.id),
          onTap: () => _selectionMode
              ? _toggleSelected(item.id)
              : _openDetail(context, item.id),
          onLongPress: () => _toggleSelected(item.id),
        );
        if (!animate) return tile;
        return _EntranceAnimation(
          // Small stagger, capped so long lists don't feel slow.
          delayMs: index.clamp(0, 8) * 20,
          child: tile,
        );
      },
    );
  }
}

class _Row {
  const _Row._(this.header, this.item);
  factory _Row.header(String label) => _Row._(label, null);
  factory _Row.tile(TransactionListItem item) => _Row._(null, item);

  final String? header;
  final TransactionListItem? item;
}

class _FilterBar extends StatelessWidget {
  const _FilterBar({
    required this.controller,
    required this.direction,
    required this.onQueryChanged,
    required this.onDirectionChanged,
    required this.filters,
    required this.onRemoveFilter,
  });

  final TextEditingController controller;
  final TransactionDirectionFilter direction;
  final ValueChanged<String> onQueryChanged;
  final ValueChanged<TransactionDirectionFilter> onDirectionChanged;
  final TransactionFilters filters;
  final ValueChanged<TransactionFilterField> onRemoveFilter;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.sm,
        AppSpacing.lg,
        AppSpacing.sm,
      ),
      child: Column(
        children: [
          TextField(
            controller: controller,
            onChanged: onQueryChanged,
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              isDense: true,
              hintText: 'Search transactions',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: controller.text.isEmpty
                  ? null
                  : IconButton(
                      tooltip: 'Clear search',
                      icon: const Icon(Icons.close),
                      onPressed: () {
                        controller.clear();
                        onQueryChanged('');
                      },
                    ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppRadius.md),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Align(
            alignment: Alignment.centerLeft,
            child: SegmentedButton<TransactionDirectionFilter>(
              segments: const [
                ButtonSegment(
                  value: TransactionDirectionFilter.all,
                  label: Text('All'),
                ),
                ButtonSegment(
                  value: TransactionDirectionFilter.spent,
                  label: Text('Spent'),
                ),
                ButtonSegment(
                  value: TransactionDirectionFilter.received,
                  label: Text('Received'),
                ),
              ],
              selected: {direction},
              onSelectionChanged: (selection) =>
                  onDirectionChanged(selection.single),
              showSelectedIcon: false,
            ),
          ),
          if (!filters.isEmpty) ...[
            const SizedBox(height: AppSpacing.sm),
            _ActiveFilterChips(
              filters: filters,
              onRemove: onRemoveFilter,
            ),
          ],
        ],
      ),
    );
  }
}

class _ActiveFilterChips extends StatelessWidget {
  const _ActiveFilterChips({required this.filters, required this.onRemove});

  final TransactionFilters filters;
  final ValueChanged<TransactionFilterField> onRemove;

  @override
  Widget build(BuildContext context) {
    final localizations = MaterialLocalizations.of(context);
    final entries = <(TransactionFilterField, String)>[];
    final range = filters.dateRange;
    if (range != null) {
      entries.add(
        (
          TransactionFilterField.dateRange,
          '${localizations.formatShortDate(range.start)} – '
              '${localizations.formatShortDate(range.end)}',
        ),
      );
    }
    if (filters.categoryId != null) {
      entries.add(
        (
          TransactionFilterField.category,
          filters.categoryName ?? 'Category',
        ),
      );
    }
    if (filters.merchant != null) {
      entries.add((TransactionFilterField.merchant, filters.merchant!));
    }
    if (filters.account != null) {
      entries.add((TransactionFilterField.account, filters.account!));
    }
    if (filters.channel != null) {
      entries.add((TransactionFilterField.channel, filters.channel!));
    }
    if (filters.minimumAmount != null || filters.maximumAmount != null) {
      final minimum = filters.minimumAmount;
      final maximum = filters.maximumAmount;
      final label = minimum != null && maximum != null
          ? '₹${minimum.toStringAsFixed(0)}–₹${maximum.toStringAsFixed(0)}'
          : minimum != null
              ? 'At least ₹${minimum.toStringAsFixed(0)}'
              : 'Up to ₹${maximum!.toStringAsFixed(0)}';
      entries.add((TransactionFilterField.amount, label));
    }
    if (filters.review != TransactionReviewFilter.all) {
      entries.add(
        (
          TransactionFilterField.review,
          filters.review == TransactionReviewFilter.needsReview
              ? 'Needs review'
              : 'Reviewed',
        ),
      );
    }
    if (filters.recurring != TransactionRecurringFilter.all) {
      entries.add(
        (
          TransactionFilterField.recurring,
          filters.recurring == TransactionRecurringFilter.recurring
              ? 'Recurring'
              : 'Not recurring',
        ),
      );
    }
    if (filters.source != TransactionSourceFilter.all) {
      entries.add(
        (
          TransactionFilterField.source,
          filters.source == TransactionSourceFilter.manual ? 'Manual' : 'SMS',
        ),
      );
    }
    if (filters.anomaly != TransactionAnomalyFilter.all) {
      entries.add(
        (
          TransactionFilterField.anomaly,
          filters.anomaly == TransactionAnomalyFilter.flagged
              ? 'Unusual'
              : 'Not unusual',
        ),
      );
    }

    return SizedBox(
      height: 48,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: entries.length,
        separatorBuilder: (_, __) => const SizedBox(width: AppSpacing.xs),
        itemBuilder: (context, index) {
          final entry = entries[index];
          return InputChip(
            label: Text(entry.$2),
            onDeleted: () => onRemove(entry.$1),
          );
        },
      ),
    );
  }
}

class _GroupHeader extends StatelessWidget {
  const _GroupHeader({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.md,
        AppSpacing.lg,
        AppSpacing.xs,
      ),
      child: Text(
        label,
        style: theme.textTheme.labelMedium?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

/// Subtle fade + 8dp slide entrance (design-system.md §7). One-shot per build.
class _EntranceAnimation extends StatelessWidget {
  const _EntranceAnimation({required this.child, this.delayMs = 0});

  final Widget child;
  final int delayMs;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: AppDurations.standard + Duration(milliseconds: delayMs),
      curve: Curves.easeOutCubic,
      builder: (context, t, child) => Opacity(
        opacity: t.clamp(0.0, 1.0),
        child:
            Transform.translate(offset: Offset(0, 8 * (1 - t)), child: child),
      ),
      child: child,
    );
  }
}
