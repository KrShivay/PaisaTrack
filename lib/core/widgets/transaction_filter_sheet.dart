import 'package:flutter/material.dart';

import '../../data/repositories/transaction_repository.dart';
import '../theme/app_tokens.dart';

enum TransactionDirectionFilter { all, spent, received }

enum TransactionReviewFilter { all, needsReview, reviewed }

enum TransactionSourceFilter { all, sms, manual }

enum TransactionRecurringFilter { all, recurring, notRecurring }

enum TransactionAnomalyFilter { all, flagged, notFlagged }

enum TransactionFilterField {
  dateRange,
  category,
  merchant,
  account,
  channel,
  amount,
  review,
  recurring,
  source,
  anomaly,
}

class TransactionFilters {
  const TransactionFilters({
    this.dateRange,
    this.categoryId,
    this.categoryName,
    this.merchant,
    this.account,
    this.channel,
    this.minimumAmount,
    this.maximumAmount,
    this.review = TransactionReviewFilter.all,
    this.recurring = TransactionRecurringFilter.all,
    this.source = TransactionSourceFilter.all,
    this.anomaly = TransactionAnomalyFilter.all,
  });

  final DateTimeRange? dateRange;
  final String? categoryId;
  final String? categoryName;
  final String? merchant;
  final String? account;
  final String? channel;
  final double? minimumAmount;
  final double? maximumAmount;
  final TransactionReviewFilter review;
  final TransactionRecurringFilter recurring;
  final TransactionSourceFilter source;
  final TransactionAnomalyFilter anomaly;

  bool get isEmpty => activeCount == 0;

  TransactionFilters clear(TransactionFilterField field) {
    return TransactionFilters(
      dateRange: field == TransactionFilterField.dateRange ? null : dateRange,
      categoryId: field == TransactionFilterField.category ? null : categoryId,
      categoryName:
          field == TransactionFilterField.category ? null : categoryName,
      merchant: field == TransactionFilterField.merchant ? null : merchant,
      account: field == TransactionFilterField.account ? null : account,
      channel: field == TransactionFilterField.channel ? null : channel,
      minimumAmount:
          field == TransactionFilterField.amount ? null : minimumAmount,
      maximumAmount:
          field == TransactionFilterField.amount ? null : maximumAmount,
      review: field == TransactionFilterField.review
          ? TransactionReviewFilter.all
          : review,
      recurring: field == TransactionFilterField.recurring
          ? TransactionRecurringFilter.all
          : recurring,
      source: field == TransactionFilterField.source
          ? TransactionSourceFilter.all
          : source,
      anomaly: field == TransactionFilterField.anomaly
          ? TransactionAnomalyFilter.all
          : anomaly,
    );
  }

  int get activeCount {
    var count = 0;
    if (dateRange != null) count++;
    if (categoryId != null) count++;
    if (merchant != null) count++;
    if (account != null) count++;
    if (channel != null) count++;
    if (minimumAmount != null || maximumAmount != null) count++;
    if (review != TransactionReviewFilter.all) count++;
    if (recurring != TransactionRecurringFilter.all) count++;
    if (source != TransactionSourceFilter.all) count++;
    if (anomaly != TransactionAnomalyFilter.all) count++;
    return count;
  }

  bool matches(
    TransactionListItem item, {
    required Set<String> recurringMerchantIds,
    required Set<String> anomalyTransactionIds,
  }) {
    final range = dateRange;
    if (range != null) {
      final local = item.ts.toLocal();
      final day = DateTime(local.year, local.month, local.day);
      final start = DateTime(
        range.start.year,
        range.start.month,
        range.start.day,
      );
      final end = DateTime(range.end.year, range.end.month, range.end.day);
      if (day.isBefore(start) || day.isAfter(end)) return false;
    }
    if (categoryId != null && item.categoryId != categoryId) return false;
    if (merchant != null && item.displayName != merchant) return false;
    if (account != null && item.accountHint != account) return false;
    if (channel != null && item.channel != channel) return false;
    if (minimumAmount != null && item.amount < minimumAmount!) return false;
    if (maximumAmount != null && item.amount > maximumAmount!) return false;

    final needsReview = item.status == 'needs_review' || item.status == 'asked';
    if (review == TransactionReviewFilter.needsReview && !needsReview) {
      return false;
    }
    if (review == TransactionReviewFilter.reviewed && needsReview) return false;

    final isRecurring = item.merchantId != null &&
        recurringMerchantIds.contains(item.merchantId);
    if (recurring == TransactionRecurringFilter.recurring && !isRecurring) {
      return false;
    }
    if (recurring == TransactionRecurringFilter.notRecurring && isRecurring) {
      return false;
    }

    final isManual = item.parseSource == 'manual';
    if (source == TransactionSourceFilter.manual && !isManual) return false;
    if (source == TransactionSourceFilter.sms && isManual) return false;

    final isAnomaly = anomalyTransactionIds.contains(item.id);
    if (anomaly == TransactionAnomalyFilter.flagged && !isAnomaly) return false;
    if (anomaly == TransactionAnomalyFilter.notFlagged && isAnomaly) {
      return false;
    }
    return true;
  }

  bool matchesSearch(TransactionListItem item, String query) {
    final normalized = query.trim().toLowerCase();
    if (normalized.isEmpty) return true;
    final searchable = [
      item.displayName,
      item.merchantRaw,
      item.categoryName,
      item.amount.toStringAsFixed(2),
      item.amount.toStringAsFixed(0),
      item.accountHint,
      item.channel,
      item.note,
      item.reference,
      item.status == 'needs_review' ? 'needs review' : item.status,
      item.parseSource == 'manual' ? 'manual' : 'sms',
    ].whereType<String>();
    return searchable.any((value) => value.toLowerCase().contains(normalized));
  }
}

Future<TransactionFilters?> showTransactionFilterSheet({
  required BuildContext context,
  required TransactionFilters initialFilters,
  required List<TransactionListItem> transactions,
}) {
  return showModalBottomSheet<TransactionFilters>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) => TransactionFilterSheet(
      initialFilters: initialFilters,
      transactions: transactions,
    ),
  );
}

class TransactionFilterSheet extends StatefulWidget {
  const TransactionFilterSheet({
    super.key,
    required this.initialFilters,
    required this.transactions,
  });

  final TransactionFilters initialFilters;
  final List<TransactionListItem> transactions;

  @override
  State<TransactionFilterSheet> createState() => _TransactionFilterSheetState();
}

class _TransactionFilterSheetState extends State<TransactionFilterSheet> {
  late DateTimeRange? _dateRange = widget.initialFilters.dateRange;
  late String? _categoryId = widget.initialFilters.categoryId;
  late String? _merchant = widget.initialFilters.merchant;
  late String? _account = widget.initialFilters.account;
  late String? _channel = widget.initialFilters.channel;
  late TransactionReviewFilter _review = widget.initialFilters.review;
  late TransactionRecurringFilter _recurring = widget.initialFilters.recurring;
  late TransactionSourceFilter _source = widget.initialFilters.source;
  late TransactionAnomalyFilter _anomaly = widget.initialFilters.anomaly;
  late final TextEditingController _minimumController = TextEditingController(
    text: widget.initialFilters.minimumAmount?.toStringAsFixed(0) ?? '',
  );
  late final TextEditingController _maximumController = TextEditingController(
    text: widget.initialFilters.maximumAmount?.toStringAsFixed(0) ?? '',
  );

  @override
  void dispose() {
    _minimumController.dispose();
    _maximumController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final categories = <String, String>{
      for (final item in widget.transactions)
        if (item.categoryId != null && item.categoryName != null)
          item.categoryId!: item.categoryName!,
    };
    final merchants = {
      for (final item in widget.transactions) item.displayName,
    }.toList()
      ..sort();
    final accounts = {
      for (final item in widget.transactions)
        if (item.accountHint != null) item.accountHint!,
    }.toList()
      ..sort();
    final channels = {
      for (final item in widget.transactions) item.channel,
    }.toList()
      ..sort();

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          AppSpacing.lg,
          0,
          AppSpacing.lg,
          MediaQuery.viewInsetsOf(context).bottom + AppSpacing.lg,
        ),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Filter transactions',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: AppSpacing.lg),
              _DateRangeField(
                value: _dateRange,
                onChanged: (value) => setState(() => _dateRange = value),
              ),
              const SizedBox(height: AppSpacing.md),
              _OptionalDropdown<String>(
                label: 'Category',
                value: _categoryId,
                entries: [
                  for (final entry in categories.entries)
                    DropdownMenuEntry(value: entry.key, label: entry.value),
                ],
                onChanged: (value) => setState(() => _categoryId = value),
              ),
              const SizedBox(height: AppSpacing.md),
              _OptionalDropdown<String>(
                label: 'Merchant',
                value: _merchant,
                entries: [
                  for (final merchant in merchants)
                    DropdownMenuEntry(value: merchant, label: merchant),
                ],
                onChanged: (value) => setState(() => _merchant = value),
              ),
              const SizedBox(height: AppSpacing.md),
              Row(
                children: [
                  Expanded(
                    child: _OptionalDropdown<String>(
                      label: 'Account',
                      value: _account,
                      entries: [
                        for (final account in accounts)
                          DropdownMenuEntry(value: account, label: account),
                      ],
                      onChanged: (value) => setState(() => _account = value),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: _OptionalDropdown<String>(
                      label: 'Channel',
                      value: _channel,
                      entries: [
                        for (final channel in channels)
                          DropdownMenuEntry(
                            value: channel,
                            label: _sentenceCase(channel),
                          ),
                      ],
                      onChanged: (value) => setState(() => _channel = value),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _minimumController,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: const InputDecoration(
                        labelText: 'Minimum amount',
                        prefixText: '₹',
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: TextField(
                      controller: _maximumController,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: const InputDecoration(
                        labelText: 'Maximum amount',
                        prefixText: '₹',
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              _EnumDropdown<TransactionReviewFilter>(
                label: 'Review status',
                value: _review,
                labels: const {
                  TransactionReviewFilter.all: 'Any status',
                  TransactionReviewFilter.needsReview: 'Needs review',
                  TransactionReviewFilter.reviewed: 'Reviewed',
                },
                onChanged: (value) => setState(() => _review = value),
              ),
              const SizedBox(height: AppSpacing.md),
              _EnumDropdown<TransactionRecurringFilter>(
                label: 'Recurring state',
                value: _recurring,
                labels: const {
                  TransactionRecurringFilter.all: 'Any transaction',
                  TransactionRecurringFilter.recurring: 'Recurring',
                  TransactionRecurringFilter.notRecurring: 'Not recurring',
                },
                onChanged: (value) => setState(() => _recurring = value),
              ),
              const SizedBox(height: AppSpacing.md),
              _EnumDropdown<TransactionSourceFilter>(
                label: 'Source',
                value: _source,
                labels: const {
                  TransactionSourceFilter.all: 'SMS and manual',
                  TransactionSourceFilter.sms: 'SMS',
                  TransactionSourceFilter.manual: 'Manual',
                },
                onChanged: (value) => setState(() => _source = value),
              ),
              const SizedBox(height: AppSpacing.md),
              _EnumDropdown<TransactionAnomalyFilter>(
                label: 'Anomaly status',
                value: _anomaly,
                labels: const {
                  TransactionAnomalyFilter.all: 'Any transaction',
                  TransactionAnomalyFilter.flagged: 'Flagged as unusual',
                  TransactionAnomalyFilter.notFlagged: 'Not flagged',
                },
                onChanged: (value) => setState(() => _anomaly = value),
              ),
              const SizedBox(height: AppSpacing.xl),
              FilledButton(
                onPressed: _apply,
                child: const Text('Apply filters'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(
                  context,
                  const TransactionFilters(),
                ),
                child: const Text('Clear all'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _apply() {
    final categoryName = widget.transactions
        .where((item) => item.categoryId == _categoryId)
        .map((item) => item.categoryName)
        .whereType<String>()
        .firstOrNull;
    Navigator.pop(
      context,
      TransactionFilters(
        dateRange: _dateRange,
        categoryId: _categoryId,
        categoryName: categoryName,
        merchant: _merchant,
        account: _account,
        channel: _channel,
        minimumAmount: double.tryParse(_minimumController.text.trim()),
        maximumAmount: double.tryParse(_maximumController.text.trim()),
        review: _review,
        recurring: _recurring,
        source: _source,
        anomaly: _anomaly,
      ),
    );
  }
}

class _DateRangeField extends StatelessWidget {
  const _DateRangeField({required this.value, required this.onChanged});

  final DateTimeRange? value;
  final ValueChanged<DateTimeRange?> onChanged;

  @override
  Widget build(BuildContext context) {
    final localizations = MaterialLocalizations.of(context);
    final label = value == null
        ? 'Any date'
        : '${localizations.formatMediumDate(value!.start)} – '
            '${localizations.formatMediumDate(value!.end)}';
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: const Text('Date range'),
      subtitle: Text(label),
      trailing: value == null
          ? const Icon(Icons.calendar_today_outlined)
          : IconButton(
              tooltip: 'Clear date range',
              onPressed: () => onChanged(null),
              icon: const Icon(Icons.close),
            ),
      onTap: () async {
        final now = DateTime.now();
        final selected = await showDateRangePicker(
          context: context,
          firstDate: DateTime(now.year - 10),
          lastDate: DateTime(now.year + 1),
          initialDateRange: value,
        );
        if (selected != null) onChanged(selected);
      },
    );
  }
}

class _OptionalDropdown<T extends Object> extends StatelessWidget {
  const _OptionalDropdown({
    required this.label,
    required this.value,
    required this.entries,
    required this.onChanged,
  });

  final String label;
  final T? value;
  final List<DropdownMenuEntry<T>> entries;
  final ValueChanged<T?> onChanged;

  @override
  Widget build(BuildContext context) {
    return DropdownMenu<T>(
      label: Text(label),
      initialSelection: value,
      dropdownMenuEntries: entries,
      expandedInsets: EdgeInsets.zero,
      enableFilter: entries.length > 8,
      trailingIcon: value == null
          ? null
          : IconButton(
              tooltip: 'Clear $label',
              onPressed: () => onChanged(null),
              icon: const Icon(Icons.close),
            ),
      onSelected: onChanged,
    );
  }
}

class _EnumDropdown<T extends Enum> extends StatelessWidget {
  const _EnumDropdown({
    required this.label,
    required this.value,
    required this.labels,
    required this.onChanged,
  });

  final String label;
  final T value;
  final Map<T, String> labels;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<T>(
      initialValue: value,
      decoration: InputDecoration(labelText: label),
      items: [
        for (final entry in labels.entries)
          DropdownMenuItem(value: entry.key, child: Text(entry.value)),
      ],
      onChanged: (value) {
        if (value != null) onChanged(value);
      },
    );
  }
}

String _sentenceCase(String value) {
  if (value.isEmpty) return value;
  return '${value[0].toUpperCase()}${value.substring(1).toLowerCase()}';
}
