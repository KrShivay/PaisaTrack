import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/app_tokens.dart';
import '../../core/theme/category_visuals.dart';
import '../../core/theme/paisa_colors.dart';
import '../../core/widgets/app_state_views.dart';
import '../../data/db/database.dart' show Category;
import '../../data/db/database_provider.dart';
import '../../data/models/normalized_transaction_record.dart';
import '../../data/repositories/transaction_repository.dart';
import 'manual_entry_screen.dart';
import 'transaction_detail_screen.dart';
import 'transactions_providers.dart';

/// Direction filter for the transactions list.
enum _DirectionFilter { all, spent, received }

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
  _DirectionFilter _direction = _DirectionFilter.all;
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
      showDragHandle: true,
      builder: (context) => _CategoryPickerSheet(categories: categories),
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

  List<TransactionListItem> _applyFilters(List<TransactionListItem> items) {
    final q = _query.trim().toLowerCase();
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
        case _DirectionFilter.spent:
          if (item.direction != TransactionDirection.debit) return false;
        case _DirectionFilter.received:
          if (item.direction != TransactionDirection.credit) return false;
        case _DirectionFilter.all:
          break;
      }
      if (q.isEmpty) return true;
      final name = item.displayName.toLowerCase();
      final category = (item.categoryName ?? '').toLowerCase();
      return name.contains(q) || category.contains(q);
    }).toList(growable: false);
  }

  Future<void> _refresh() async {
    ref.invalidate(transactionListProvider);
    await ref.read(transactionListProvider.future);
  }

  @override
  Widget build(BuildContext context) {
    final transactions = ref.watch(transactionListProvider);

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
            ),
      body: Column(
        children: [
          _FilterBar(
            controller: _searchController,
            direction: _direction,
            onQueryChanged: (value) => setState(() => _query = value),
            onDirectionChanged: (value) => setState(() => _direction = value),
          ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: _refresh,
              child: switch (transactions) {
                AsyncData(:final value) => _buildList(context, value),
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

  Widget _buildList(BuildContext context, List<TransactionListItem> all) {
    final filtered = _applyFilters(all);

    if (filtered.isEmpty) {
      final searching = _query.trim().isNotEmpty ||
          _direction != _DirectionFilter.all ||
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
        final tile = _TransactionTile(
          item: item,
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
  });

  final TextEditingController controller;
  final _DirectionFilter direction;
  final ValueChanged<String> onQueryChanged;
  final ValueChanged<_DirectionFilter> onDirectionChanged;

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
              hintText: 'Search merchant or category',
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
            child: SegmentedButton<_DirectionFilter>(
              segments: const [
                ButtonSegment(value: _DirectionFilter.all, label: Text('All')),
                ButtonSegment(
                  value: _DirectionFilter.spent,
                  label: Text('Spent'),
                ),
                ButtonSegment(
                  value: _DirectionFilter.received,
                  label: Text('Received'),
                ),
              ],
              selected: {direction},
              onSelectionChanged: (selection) =>
                  onDirectionChanged(selection.single),
              showSelectedIcon: false,
            ),
          ),
        ],
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
        child: Transform.translate(offset: Offset(0, 8 * (1 - t)), child: child),
      ),
      child: child,
    );
  }
}

/// Bottom sheet listing categories to apply to the selected transactions.
class _CategoryPickerSheet extends StatelessWidget {
  const _CategoryPickerSheet({required this.categories});

  final List<Category> categories;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              0,
              AppSpacing.lg,
              AppSpacing.sm,
            ),
            child: Text(
              'Move to category',
              style: theme.textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.w600),
            ),
          ),
          Flexible(
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: categories.length,
              itemBuilder: (context, index) {
                final category = categories[index];
                final color = CategoryVisuals.color(category.id);
                return ListTile(
                  leading: Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.15),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      CategoryVisuals.icon(category.icon),
                      size: 20,
                      color: color,
                    ),
                  ),
                  title: Text(category.name),
                  onTap: () => Navigator.of(context).pop(category),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _TransactionTile extends StatelessWidget {
  const _TransactionTile({
    required this.item,
    required this.selected,
    required this.onTap,
    required this.onLongPress,
  });

  final TransactionListItem item;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final paisa = PaisaColors.of(context);
    final isCredit = item.direction == TransactionDirection.credit;
    final sign = isCredit ? '+' : '-';
    final categoryColor = CategoryVisuals.color(item.categoryId);
    final categoryLabel = item.categoryName ?? 'Uncategorized';

    // Credit -> credit hue; spending debit -> debit hue; non-spending debit
    // (transfers, cash withdrawals) -> neutral onSurface (design-system §5).
    final Color amountColor;
    if (isCredit) {
      amountColor = paisa.credit;
    } else if (!item.categoryIsSpending) {
      amountColor = theme.colorScheme.onSurface;
    } else {
      amountColor = paisa.debit;
    }

    final leading = selected
        ? Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: theme.colorScheme.primary,
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.check,
              size: 20,
              color: theme.colorScheme.onPrimary,
            ),
          )
        : Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: categoryColor.withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child: Icon(
              CategoryVisuals.icon(item.categoryIcon),
              size: 20,
              color: categoryColor,
            ),
          );

    return ListTile(
      selected: selected,
      selectedTileColor: theme.colorScheme.primary.withValues(alpha: 0.08),
      onTap: onTap,
      onLongPress: onLongPress,
      leading: Semantics(
        label: selected ? 'Selected, $categoryLabel' : categoryLabel,
        child: leading,
      ),
      title: Text(
        item.displayName,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        '$categoryLabel · ${formatTxnTime(item.ts)}',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.bodyMedium?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
      trailing: Text(
        '$sign${formatInr(item.amount)}',
        style: theme.textTheme.titleMedium?.copyWith(
          color: amountColor,
          fontWeight: FontWeight.w600,
          fontFeatures: AppTheme.tabularFigures,
        ),
      ),
    );
  }
}
