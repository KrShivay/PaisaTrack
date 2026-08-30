import 'dart:async';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_tokens.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/bloom/bloom.dart';
import '../../core/widgets/category_picker_sheet.dart';
import '../../core/undo/undo_controller.dart';
import '../../data/db/database.dart' show Category;
import '../../data/db/database_provider.dart';
import '../../data/models/normalized_transaction_record.dart';
import '../../data/repositories/transaction_repository.dart';
import '../sms/sms_lookup_sheet.dart';
import '../sms/sms_permission_status_card.dart';
import 'manual_entry_screen.dart';
import 'transaction_detail_screen.dart';
import 'transactions_providers.dart';

enum ActivityFilterChoice { all, expenses, income, transfers, unsorted }

/// Redesigned Bloom Activity screen listing parsed & typed transactions grouped by day.
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

  @override
  ConsumerState<TransactionsScreen> createState() => _TransactionsScreenState();
}

class _TransactionsScreenState extends ConsumerState<TransactionsScreen> {
  final _searchController = TextEditingController();
  String _query = '';
  ActivityFilterChoice _activeFilter = ActivityFilterChoice.all;
  Timer? _debounce;

  void _loadMoreTransactions() {
    ref.read(activityTransactionPageProvider.notifier).loadMore();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  List<TransactionListItem> _filterItems(List<TransactionListItem> items) {
    return items.where((item) {
      if (widget.initialCategoryId != null &&
          item.categoryId != widget.initialCategoryId) {
        return false;
      }
      if (widget.initialMerchant != null &&
          item.displayName != widget.initialMerchant) {
        return false;
      }
      switch (_activeFilter) {
        case ActivityFilterChoice.expenses:
          if (item.direction != TransactionDirection.debit ||
              !item.categoryIsSpending) {
            return false;
          }
        case ActivityFilterChoice.income:
          if (item.direction != TransactionDirection.credit) return false;
        case ActivityFilterChoice.transfers:
          if (item.categoryIsSpending &&
              item.direction == TransactionDirection.debit) {
            return false;
          }
        case ActivityFilterChoice.unsorted:
          if (item.categoryId != null && item.status == 'confirmed') {
            return false;
          }
        case ActivityFilterChoice.all:
          break;
      }
      if (_query.isNotEmpty) {
        final q = _query.toLowerCase();
        final name = item.displayName.toLowerCase();
        final note = (item.note ?? '').toLowerCase();
        final amt = item.amount.toString();
        final channel = item.channel.toLowerCase();
        final ref = (item.reference ?? '').toLowerCase();
        final status = item.status.toLowerCase();
        final account = (item.accountHint ?? '').toLowerCase();
        final category = (item.categoryName ?? '').toLowerCase();
        final source = (item.paymentSourceName ?? '').toLowerCase();
        final merchant = (item.merchantRaw ?? '').toLowerCase();
        if (!name.contains(q) &&
            !note.contains(q) &&
            !amt.contains(q) &&
            !channel.contains(q) &&
            !ref.contains(q) &&
            !status.contains(q) &&
            !account.contains(q) &&
            !category.contains(q) &&
            !source.contains(q) &&
            !merchant.contains(q)) {
          return false;
        }
      }
      return true;
    }).toList();
  }

  void _openManualEntry() {
    showBloomModalSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => const FractionallySizedBox(
        heightFactor: 0.88,
        child: ManualEntryScreen(),
      ),
    );
  }

  void _openDetail(TransactionListItem item) {
    showBloomModalSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => FractionallySizedBox(
        heightFactor: 0.9,
        child: TransactionDetailScreen(txnId: item.id),
      ),
    );
  }

  Future<void> _recategorizeItem(TransactionListItem item) async {
    final categories = await ref.read(categoryListProvider.future);
    if (!mounted) return;
    final chosen = await showBloomFullScreenSheet<Category>(
      context: context,
      showBack: true,
      builder: (context) => CategoryPickerSheet(
        categories: categories,
        title: 'Change Category',
      ),
    );
    if (chosen == null || !mounted) return;

    final database = await ref.read(appDatabaseProvider.future);
    final repo = ref.read(transactionRepositoryProvider(database));
    final prevCategory = item.categoryId;

    await repo.updateWithFeedback(
      txnId: item.id,
      categoryId: Value(chosen.id),
      context: 'activity_swipe',
    );

    ref.read(undoControllerProvider.notifier).pushUndo(
          UndoToken(
            id: 'categorize_${item.id}',
            message: 'Filed under ${chosen.name}',
            undoAction: () async {
              await repo.updateWithFeedback(
                txnId: item.id,
                categoryId: Value(prevCategory),
                context: 'undo_swipe',
              );
            },
          ),
        );
  }

  Future<void> _confirmItem(TransactionListItem item) async {
    final database = await ref.read(appDatabaseProvider.future);
    final repo = ref.read(transactionRepositoryProvider(database));
    final prevStatus = item.status;

    await repo.updateWithFeedback(
      txnId: item.id,
      status: const Value('confirmed'),
      context: 'activity_confirm',
    );

    ref.read(undoControllerProvider.notifier).pushUndo(
          UndoToken(
            id: 'confirm_${item.id}',
            message: 'Marked confirmed',
            undoAction: () async {
              await repo.updateWithFeedback(
                txnId: item.id,
                status: Value(prevStatus),
                context: 'undo_confirm',
              );
            },
          ),
        );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final pageAsync = ref.watch(activityTransactionPageProvider);
    final page = pageAsync.valueOrNull;
    final items = page?.rows ?? const <TransactionListItem>[];
    final hasMore = page?.hasMore ?? false;
    final filtered = _filterItems(items);
    final grouped = _groupByDay(filtered);

    return Scaffold(
      backgroundColor:
          isDark ? AppColorTokens.bloomDarkBase : AppColorTokens.bloomBase,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            // Top Header: title, SMS import, and manual entry actions.
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Activity',
                    style: AppTheme.bloomDisplay(
                      22,
                      FontWeight.w700,
                      letterSpacing: -0.03,
                      color: isDark
                          ? AppColorTokens.bloomDarkTextPrimary
                          : AppColorTokens.ink,
                    ),
                  ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        tooltip: 'Scan SMS inbox',
                        onPressed: () => showBloomModalSheet(
                          context: context,
                          isScrollControlled: true,
                          builder: (_) => const SmsLookupSheet(),
                        ),
                        icon: const Icon(Icons.sms_outlined),
                      ),
                      GestureDetector(
                        onTap: _openManualEntry,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: isDark
                                ? AppColorTokens.violetPrimary
                                : AppColorTokens.ink,
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.add,
                                size: 16,
                                color: Colors.white,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                'Add',
                                style: AppTheme.bloomDisplay(
                                  13,
                                  FontWeight.w600,
                                  color: Colors.white,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 20),
              child: SmsPermissionStatusCard(),
            ),
            const SizedBox(height: 12),

            // Search Bar
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Container(
                height: 44,
                decoration: BoxDecoration(
                  color: isDark
                      ? AppColorTokens.bloomDarkCard
                      : const Color(0xFFF1EFFB),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: TextField(
                  controller: _searchController,
                  onChanged: (val) {
                    if (_debounce?.isActive ?? false) _debounce?.cancel();
                    _debounce = Timer(const Duration(milliseconds: 300), () {
                      setState(() => _query = val);
                    });
                  },
                  style: AppTheme.bloomDisplay(
                    14,
                    FontWeight.w400,
                    color: isDark
                        ? AppColorTokens.bloomDarkTextPrimary
                        : AppColorTokens.ink,
                  ),
                  decoration: InputDecoration(
                    hintText: 'Search merchant, note, amount...',
                    hintStyle: AppTheme.bloomDisplay(
                      14,
                      FontWeight.w400,
                      color: isDark
                          ? AppColorTokens.bloomDarkTextTertiary
                          : AppColorTokens.inkTertiary,
                    ),
                    prefixIcon: Icon(
                      Icons.search,
                      size: 20,
                      color: isDark
                          ? AppColorTokens.bloomDarkTextTertiary
                          : AppColorTokens.inkTertiary,
                    ),
                    suffixIcon: _query.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.close, size: 18),
                            tooltip: 'Clear search',
                            onPressed: () {
                              _searchController.clear();
                              setState(() => _query = '');
                            },
                          )
                        : null,
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),

            // Filter Chips Row
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  for (final choice in ActivityFilterChoice.values) ...[
                    _FilterChip(
                      label: _filterLabel(choice),
                      isSelected: _activeFilter == choice,
                      onTap: () => setState(() => _activeFilter = choice),
                      isDark: isDark,
                    ),
                    if (choice != ActivityFilterChoice.values.last)
                      const SizedBox(width: 8),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Transaction List grouped by day
            Expanded(
              child: pageAsync.isLoading && filtered.isEmpty
                  ? const Center(child: BloomSkeleton(width: 280, height: 160))
                  : filtered.isEmpty
                      ? Column(
                          children: [
                            Expanded(
                              child: _EmptyState(
                                isDark: isDark,
                                query: _query,
                                onClearFilters: () {
                                  setState(() {
                                    _query = '';
                                    _searchController.clear();
                                    _activeFilter = ActivityFilterChoice.all;
                                  });
                                },
                              ),
                            ),
                            if (hasMore) _loadMoreButton(),
                          ],
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.fromLTRB(20, 0, 20, 110),
                          itemCount: grouped.length + (hasMore ? 1 : 0),
                          itemBuilder: (context, index) {
                            if (index == grouped.length) {
                              return _loadMoreButton();
                            }
                            final group = grouped[index];
                            return _DayGroupSection(
                              header: group.header,
                              dayTotal: group.total,
                              items: group.items,
                              isDark: isDark,
                              onTap: _openDetail,
                              onSwipeRight: _confirmItem,
                              onSwipeLeft: _recategorizeItem,
                            );
                          },
                        ),
            ),
          ],
        ),
      ),
    );
  }

  String _filterLabel(ActivityFilterChoice choice) => switch (choice) {
        ActivityFilterChoice.all => 'All',
        ActivityFilterChoice.expenses => 'Expenses',
        ActivityFilterChoice.income => 'Income',
        ActivityFilterChoice.transfers => 'Transfers',
        ActivityFilterChoice.unsorted => 'Unsorted',
      };

  Widget _loadMoreButton() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
      child: OutlinedButton(
        onPressed: _loadMoreTransactions,
        child: const Text('Load more transactions'),
      ),
    );
  }

  List<_DayGroup> _groupByDay(List<TransactionListItem> items) {
    final Map<String, List<TransactionListItem>> map = {};
    final Map<String, double> totals = {};

    final now = DateTime.now();
    final todayStr = '${now.year}-${now.month}-${now.day}';
    final yesterday = now.subtract(const Duration(days: 1));
    final yesterdayStr =
        '${yesterday.year}-${yesterday.month}-${yesterday.day}';

    for (final item in items) {
      final date = item.ts.toLocal();
      final dateKey = '${date.year}-${date.month}-${date.day}';
      String header;
      if (dateKey == todayStr) {
        header = 'TODAY';
      } else if (dateKey == yesterdayStr) {
        header = 'YESTERDAY';
      } else {
        header = '${_shortMonth(date.month).toUpperCase()} ${date.day}';
      }

      map.putIfAbsent(header, () => []).add(item);
      totals[header] = (totals[header] ?? 0) +
          (item.direction == TransactionDirection.debit
              ? -item.amount
              : item.amount);
    }

    return [
      for (final entry in map.entries)
        _DayGroup(
          header: entry.key,
          total: totals[entry.key] ?? 0,
          items: entry.value,
        ),
    ];
  }

  String _shortMonth(int month) => const [
        'Jan',
        'Feb',
        'Mar',
        'Apr',
        'May',
        'Jun',
        'Jul',
        'Aug',
        'Sep',
        'Oct',
        'Nov',
        'Dec',
      ][month - 1];
}

class _DayGroup {
  const _DayGroup({
    required this.header,
    required this.total,
    required this.items,
  });

  final String header;
  final double total;
  final List<TransactionListItem> items;
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.isSelected,
    required this.onTap,
    required this.isDark,
  });

  final String label;
  final bool isSelected;
  final VoidCallback onTap;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final activeBg = isDark ? AppColorTokens.violetPrimary : AppColorTokens.ink;
    final inactiveBg =
        isDark ? AppColorTokens.bloomDarkCard : AppColorTokens.bloomChip;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: isSelected ? activeBg : inactiveBg,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Text(
          label,
          style: AppTheme.bloomDisplay(
            12,
            isSelected ? FontWeight.w600 : FontWeight.w500,
            color: isSelected
                ? Colors.white
                : (isDark
                    ? AppColorTokens.bloomDarkTextSecondary
                    : AppColorTokens.inkSecondary),
          ),
        ),
      ),
    );
  }
}

class _DayGroupSection extends StatelessWidget {
  const _DayGroupSection({
    required this.header,
    required this.dayTotal,
    required this.items,
    required this.isDark,
    required this.onTap,
    required this.onSwipeRight,
    required this.onSwipeLeft,
  });

  final String header;
  final double dayTotal;
  final List<TransactionListItem> items;
  final bool isDark;
  final ValueChanged<TransactionListItem> onTap;
  final ValueChanged<TransactionListItem> onSwipeRight;
  final ValueChanged<TransactionListItem> onSwipeLeft;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Day Header
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                header,
                style: AppTheme.bloomDisplay(
                  11,
                  FontWeight.w600,
                  letterSpacing: 0.1,
                  color: isDark
                      ? AppColorTokens.bloomDarkTextTertiary
                      : AppColorTokens.inkTertiary,
                ),
              ),
              BloomAmount(
                amount: dayTotal,
                size: 12,
                weight: FontWeight.w500,
              ),
            ],
          ),
        ),
        for (final item in items) ...[
          _DismissibleTransactionRow(
            item: item,
            isDark: isDark,
            onTap: () => onTap(item),
            onSwipeRight: () => onSwipeRight(item),
            onSwipeLeft: () => onSwipeLeft(item),
          ),
          if (item != items.last) const SizedBox(height: 8),
        ],
      ],
    );
  }
}

class _DismissibleTransactionRow extends StatelessWidget {
  const _DismissibleTransactionRow({
    required this.item,
    required this.isDark,
    required this.onTap,
    required this.onSwipeRight,
    required this.onSwipeLeft,
  });

  final TransactionListItem item;
  final bool isDark;
  final VoidCallback onTap;
  final VoidCallback onSwipeRight;
  final VoidCallback onSwipeLeft;

  @override
  Widget build(BuildContext context) {
    final bg = isDark ? AppColorTokens.bloomDarkCard : AppColorTokens.bloomCard;

    return Dismissible(
      key: ValueKey(item.id),
      background: Container(
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.only(left: 20),
        decoration: BoxDecoration(
          color: AppColorTokens.bloomEmerald,
          borderRadius: BorderRadius.circular(AppRadius.bloomRow),
        ),
        child: const Icon(Icons.check, color: Colors.white),
      ),
      secondaryBackground: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        decoration: BoxDecoration(
          color: AppColorTokens.bloomGold,
          borderRadius: BorderRadius.circular(AppRadius.bloomRow),
        ),
        child: const Icon(Icons.sell_outlined, color: Colors.white),
      ),
      confirmDismiss: (direction) async {
        if (direction == DismissDirection.startToEnd) {
          onSwipeRight();
        } else {
          onSwipeLeft();
        }
        return false; // Re-render row so state updates smoothly via Riverpod stream
      },
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(AppRadius.bloomRow),
          ),
          child: Row(
            children: [
              BloomCategoryTile(
                categoryId: item.categoryId,
                iconName: item.categoryIcon,
                size: 36,
                borderRadius: 13,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.displayName,
                      style: AppTheme.bloomDisplay(
                        14,
                        FontWeight.w500,
                        color: isDark
                            ? AppColorTokens.bloomDarkTextPrimary
                            : AppColorTokens.ink,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _formatMeta(item),
                      style: AppTheme.bloomDisplay(
                        11,
                        FontWeight.w400,
                        color: isDark
                            ? AppColorTokens.bloomDarkTextTertiary
                            : AppColorTokens.inkTertiary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              BloomAmount(
                amount: item.direction == TransactionDirection.debit
                    ? -item.amount
                    : item.amount,
                size: 15,
                weight: FontWeight.w500,
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatMeta(TransactionListItem item) {
    final time = _formatTime(item.ts);
    final account = item.accountHint != null && item.accountHint!.isNotEmpty
        ? ' · ${item.accountHint}'
        : '';
    return '$time$account';
  }

  String _formatTime(DateTime date) {
    final h =
        date.hour > 12 ? date.hour - 12 : (date.hour == 0 ? 12 : date.hour);
    final m = date.minute.toString().padLeft(2, '0');
    final ampm = date.hour >= 12 ? 'pm' : 'am';
    return '$h:$m $ampm';
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({
    required this.isDark,
    required this.query,
    this.onClearFilters,
  });

  final bool isDark;
  final String query;
  final VoidCallback? onClearFilters;

  @override
  Widget build(BuildContext context) {
    final isFiltered = query.isNotEmpty;

    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight),
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    isFiltered
                        ? Icons.search_off_rounded
                        : Icons.receipt_long_outlined,
                    size: 48,
                    color: isDark
                        ? AppColorTokens.bloomDarkTextTertiary
                        : AppColorTokens.inkTertiary,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    isFiltered
                        ? 'No transactions matching "$query"'
                        : 'No transactions found',
                    style: AppTheme.bloomDisplay(
                      15,
                      FontWeight.w600,
                      color: isDark
                          ? AppColorTokens.bloomDarkTextPrimary
                          : AppColorTokens.ink,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    isFiltered
                        ? 'Try clearing your search or filter keywords'
                        : 'Scan your SMS inbox for payment alerts or add a transaction manually.',
                    style: AppTheme.bloomDisplay(
                      12,
                      FontWeight.w400,
                      color: isDark
                          ? AppColorTokens.bloomDarkTextSecondary
                          : AppColorTokens.inkSecondary,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 20),
                  if (isFiltered)
                    OutlinedButton(
                      onPressed: onClearFilters,
                      child: const Text('Clear filters'),
                    )
                  else
                    Column(
                      children: [
                        FilledButton.icon(
                          icon: const Icon(Icons.sms_rounded, size: 18),
                          label: const Text('Find transactions from SMS'),
                          style: FilledButton.styleFrom(
                            backgroundColor: AppColorTokens.violetPrimary,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 20,
                              vertical: 12,
                            ),
                          ),
                          onPressed: () {
                            showBloomModalSheet(
                              context: context,
                              isScrollControlled: true,
                              builder: (_) => const SmsLookupSheet(),
                            );
                          },
                        ),
                        const SizedBox(height: 10),
                        TextButton.icon(
                          icon: const Icon(Icons.add_rounded, size: 18),
                          label: const Text('Add one manually'),
                          onPressed: () {
                            showBloomModalSheet(
                              context: context,
                              isScrollControlled: true,
                              builder: (_) => const FractionallySizedBox(
                                heightFactor: 0.88,
                                child: ManualEntryScreen(),
                              ),
                            );
                          },
                        ),
                      ],
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
