import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/app_tokens.dart';
import '../../core/widgets/bloom/bloom.dart';
import '../../data/db/database_provider.dart';
import '../../data/repositories/trends_inbox_repository.dart';
import '../../intelligence/claim.dart';
import 'insights_screen.dart'
    show
        claimDisplayNamesProvider,
        openTrendsInboxEvidence,
        trendsInboxHistoryProvider,
        trendsInboxItemsProvider;

/// State filter choices on the insight history screen.
enum TrendsHistoryStateFilter {
  all('All'),
  newItem('New'),
  later('Later'),
  cleared('Cleared');

  const TrendsHistoryStateFilter(this.label);

  final String label;

  bool matches(TrendsInboxState state) => switch (this) {
        TrendsHistoryStateFilter.all => true,
        TrendsHistoryStateFilter.newItem => state == TrendsInboxState.newItem,
        TrendsHistoryStateFilter.later => state == TrendsInboxState.moved,
        TrendsHistoryStateFilter.cleared => state == TrendsInboxState.cleared,
      };
}

/// Applies the history filters; null [period] / [kind] mean "all".
List<TrendsInboxItem> filterTrendsHistory(
  Iterable<TrendsInboxItem> items, {
  TrendsHistoryStateFilter state = TrendsHistoryStateFilter.all,
  String? period,
  String? kind,
}) =>
    [
      for (final item in items)
        if (state.matches(item.state) &&
            (period == null || item.insight.period == period) &&
            (kind == null || item.insight.kind == kind))
          item,
    ];

/// Groups items by period (`yyyy-MM`), newest period first.
List<MapEntry<String, List<TrendsInboxItem>>> groupTrendsHistoryByPeriod(
  Iterable<TrendsInboxItem> items,
) {
  final groups = <String, List<TrendsInboxItem>>{};
  for (final item in items) {
    groups.putIfAbsent(item.insight.period, () => []).add(item);
  }
  return groups.entries.toList()..sort((a, b) => b.key.compareTo(a.key));
}

String trendsHistoryPeriodLabel(String period) {
  final match = RegExp(r'^(\d{4})-(\d{2})$').firstMatch(period);
  if (match == null) return period;
  return formatMonthYear(
    DateTime(int.parse(match.group(1)!), int.parse(match.group(2)!)),
  );
}

String _kindLabel(String kind) {
  final words = kind.split('_').where((word) => word.isNotEmpty).toList();
  if (words.isEmpty) return kind;
  final text = words.join(' ');
  return '${text[0].toUpperCase()}${text.substring(1)}';
}

String _stateLabel(TrendsInboxState state) => switch (state) {
      TrendsInboxState.newItem => 'New',
      TrendsInboxState.seen => 'Seen',
      TrendsInboxState.moved => 'Later',
      TrendsInboxState.cleared => 'Cleared',
    };

/// All retained Trends inbox items (current and past periods, including
/// cleared and Later) with state, month and insight-type filters.
class TrendsHistoryScreen extends ConsumerStatefulWidget {
  const TrendsHistoryScreen({super.key});

  @override
  ConsumerState<TrendsHistoryScreen> createState() =>
      _TrendsHistoryScreenState();
}

class _TrendsHistoryScreenState extends ConsumerState<TrendsHistoryScreen> {
  var _state = TrendsHistoryStateFilter.all;
  String? _period;
  String? _kind;

  Future<void> _mutate(
    Future<void> Function(TrendsInboxRepository repository) action,
  ) async {
    final database = await ref.read(appDatabaseProvider.future);
    await action(TrendsInboxRepository(database));
    ref.invalidate(trendsInboxItemsProvider);
    ref.invalidate(trendsInboxHistoryProvider);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final historyAsync = ref.watch(trendsInboxHistoryProvider);
    final categoryNames =
        ref.watch(claimDisplayNamesProvider).valueOrNull?.categories ??
            const <String, String>{};
    final secondary = isDark
        ? AppColorTokens.bloomDarkTextSecondary
        : AppColorTokens.inkSecondary;

    return Scaffold(
      backgroundColor:
          isDark ? AppColorTokens.bloomDarkBase : AppColorTokens.bloomBase,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        title: Text(
          'Insight history',
          style: AppTheme.bloomDisplay(
            20,
            FontWeight.w700,
            letterSpacing: -0.03,
            color: isDark
                ? AppColorTokens.bloomDarkTextPrimary
                : AppColorTokens.ink,
          ),
        ),
      ),
      body: SafeArea(
        top: false,
        child: historyAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (_, __) => Center(
            child: Text(
              "Couldn't load insight history.",
              style:
                  AppTheme.bloomDisplay(13, FontWeight.w500, color: secondary),
            ),
          ),
          data: (all) => _buildBody(context, all, isDark, categoryNames),
        ),
      ),
    );
  }

  Widget _buildBody(
    BuildContext context,
    List<TrendsInboxItem> all,
    bool isDark,
    Map<String, String> categoryNames,
  ) {
    final secondary = isDark
        ? AppColorTokens.bloomDarkTextSecondary
        : AppColorTokens.inkSecondary;
    final periods = ({for (final i in all) i.insight.period}.toList()
      ..sort((a, b) => b.compareTo(a)));
    final kinds = {for (final i in all) i.insight.kind}.toList()..sort();
    // A filter value that vanished (e.g. after Restore/Clear) falls back to all.
    final period = periods.contains(_period) ? _period : null;
    final kind = kinds.contains(_kind) ? _kind : null;
    final filtered = filterTrendsHistory(
      all,
      state: _state,
      period: period,
      kind: kind,
    );
    final groups = groupTrendsHistoryByPeriod(filtered);

    return ListView(
      padding: EdgeInsets.fromLTRB(
        20,
        8,
        20,
        24 + BloomBottomInset.contentPadding(context),
      ),
      children: [
        _ChipRow(
          label: 'Status',
          isDark: isDark,
          chips: [
            for (final filter in TrendsHistoryStateFilter.values)
              _FilterOption(
                label: filter.label,
                selected: _state == filter,
                onSelected: () => setState(() => _state = filter),
              ),
          ],
        ),
        if (periods.isNotEmpty)
          _ChipRow(
            label: 'Month',
            isDark: isDark,
            chips: [
              _FilterOption(
                label: 'All months',
                selected: period == null,
                onSelected: () => setState(() => _period = null),
              ),
              for (final p in periods)
                _FilterOption(
                  label: trendsHistoryPeriodLabel(p),
                  selected: period == p,
                  onSelected: () => setState(() => _period = p),
                ),
            ],
          ),
        if (kinds.isNotEmpty)
          _ChipRow(
            label: 'Type',
            isDark: isDark,
            chips: [
              _FilterOption(
                label: 'All types',
                selected: kind == null,
                onSelected: () => setState(() => _kind = null),
              ),
              for (final k in kinds)
                _FilterOption(
                  label: _kindLabel(k),
                  selected: kind == k,
                  onSelected: () => setState(() => _kind = k),
                ),
            ],
          ),
        const SizedBox(height: 8),
        if (groups.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 48),
            child: Text(
              all.isEmpty
                  ? 'No insights yet. Insights you receive are kept here.'
                  : 'No insights match these filters.',
              textAlign: TextAlign.center,
              style:
                  AppTheme.bloomDisplay(13, FontWeight.w500, color: secondary),
            ),
          ),
        for (final group in groups) ...[
          Padding(
            padding: const EdgeInsets.only(top: 12, bottom: 8),
            child: Text(
              trendsHistoryPeriodLabel(group.key).toUpperCase(),
              style: AppTheme.bloomDisplay(
                11,
                FontWeight.w600,
                letterSpacing: 0.12,
                color: secondary,
              ),
            ),
          ),
          for (final item in group.value)
            _HistoryRow(
              item: item,
              isDark: isDark,
              categoryNames: categoryNames,
              onOpen: () => openTrendsInboxEvidence(context, item),
              onClear: () => _mutate((repo) => repo.clear(item.key)),
              onRestore: () => _mutate((repo) => repo.restore(item.key)),
            ),
        ],
      ],
    );
  }
}

class _FilterOption {
  const _FilterOption({
    required this.label,
    required this.selected,
    required this.onSelected,
  });

  final String label;
  final bool selected;
  final VoidCallback onSelected;
}

class _ChipRow extends StatelessWidget {
  const _ChipRow({
    required this.label,
    required this.isDark,
    required this.chips,
  });

  final String label;
  final bool isDark;
  final List<_FilterOption> chips;

  @override
  Widget build(BuildContext context) {
    final textColor =
        isDark ? AppColorTokens.bloomDarkTextPrimary : AppColorTokens.ink;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final chip in chips)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Semantics(
                label: '$label filter: ${chip.label}',
                child: ChoiceChip(
                  label: Text(chip.label),
                  selected: chip.selected,
                  showCheckmark: false,
                  selectedColor: AppColorTokens.violetPrimary,
                  backgroundColor: isDark
                      ? AppColorTokens.bloomDarkCard
                      : AppColorTokens.bloomChip,
                  side: BorderSide(
                    color: isDark
                        ? AppColorTokens.bloomDarkOutline
                        : AppColorTokens.bloomHairline,
                  ),
                  labelStyle: AppTheme.bloomDisplay(
                    12,
                    FontWeight.w600,
                    color: chip.selected ? Colors.white : textColor,
                  ),
                  onSelected: (_) => chip.onSelected(),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _HistoryRow extends StatelessWidget {
  const _HistoryRow({
    required this.item,
    required this.isDark,
    required this.categoryNames,
    required this.onOpen,
    required this.onClear,
    required this.onRestore,
  });

  final TrendsInboxItem item;
  final bool isDark;
  final Map<String, String> categoryNames;
  final VoidCallback onOpen;
  final VoidCallback onClear;
  final VoidCallback onRestore;

  @override
  Widget build(BuildContext context) {
    final display = const ClaimRenderer().render(
      item.claim,
      categoryNames: categoryNames,
    );
    if (display == null) return const SizedBox.shrink();
    final textColor =
        isDark ? AppColorTokens.bloomDarkTextPrimary : AppColorTokens.ink;
    final secondary = isDark
        ? AppColorTokens.bloomDarkTextSecondary
        : AppColorTokens.inkSecondary;
    final cleared = item.state == TrendsInboxState.cleared;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.fromLTRB(14, 8, 8, 4),
      decoration: BoxDecoration(
        color: isDark ? AppColorTokens.bloomDarkCard : AppColorTokens.bloomChip,
        borderRadius: BorderRadius.circular(AppRadius.bloomChip),
        border: Border.all(
          color: isDark
              ? AppColorTokens.bloomDarkOutline
              : AppColorTokens.bloomHairline,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: TextButton(
                  onPressed: onOpen,
                  style: TextButton.styleFrom(
                    alignment: Alignment.centerLeft,
                    foregroundColor: textColor,
                    minimumSize: const Size(48, 48),
                    padding: EdgeInsets.zero,
                  ),
                  child: Text(
                    display.title,
                    style: AppTheme.bloomDisplay(13, FontWeight.w600),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                _stateLabel(item.state),
                style: AppTheme.bloomDisplay(
                  11,
                  FontWeight.w600,
                  color: cleared ? secondary : AppColorTokens.violetPrimary,
                ),
              ),
              const SizedBox(width: 6),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(right: 6),
            child: Text(
              display.body,
              style: AppTheme.bloomDisplay(
                12,
                FontWeight.w400,
                color: secondary,
              ),
            ),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: Wrap(
              children: [
                TextButton(
                  onPressed: onOpen,
                  style: TextButton.styleFrom(
                    minimumSize: const Size(48, 48),
                  ),
                  child: const Text('Evidence'),
                ),
                if (cleared)
                  TextButton(
                    onPressed: onRestore,
                    style: TextButton.styleFrom(
                      minimumSize: const Size(48, 48),
                    ),
                    child: const Text('Restore'),
                  )
                else
                  TextButton(
                    onPressed: onClear,
                    style: TextButton.styleFrom(
                      minimumSize: const Size(48, 48),
                    ),
                    child: const Text('Clear'),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
