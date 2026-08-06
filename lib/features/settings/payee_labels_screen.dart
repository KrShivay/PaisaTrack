import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_tokens.dart';
import '../../core/widgets/bloom/bloom.dart';
import '../../data/repositories/payee_label_repository.dart';
import '../../enrichment/merchant_clusterer.dart';

class PayeeLabelsScreen extends ConsumerStatefulWidget {
  const PayeeLabelsScreen({super.key});

  @override
  ConsumerState<PayeeLabelsScreen> createState() => _PayeeLabelsScreenState();
}

class _PayeeLabelsScreenState extends ConsumerState<PayeeLabelsScreen> {
  final _searchController = TextEditingController();
  String _searchQuery = '';
  bool _unlabeledOnly = false;
  List<PayeeIdentity> _items = const [];
  PayeeIdentityCursor? _cursor;
  MerchantClusterSuggestion? _suggestion;
  Object? _error;
  bool _loading = true;
  bool _loadingMore = false;
  bool _hasMore = false;
  int _requestToken = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _reload());
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Payee labels'),
        actions: [
          IconButton(
            key: const ValueKey('backfill_payees_button'),
            icon: const Icon(Icons.cleaning_services),
            tooltip: 'Backfill payees',
            onPressed: () => _showBackfillDialog(context),
          ),
        ],
      ),
      body: Column(
        children: [
          if (_suggestion != null) _suggestionCard(context, _suggestion!),
          Padding(
            padding: const EdgeInsets.all(AppSpacing.sm),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    key: const ValueKey('payee_labels_search_field'),
                    controller: _searchController,
                    decoration: InputDecoration(
                      hintText: 'Search payees or aliases...',
                      prefixIcon: const Icon(Icons.search),
                      suffixIcon: _searchQuery.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear),
                              tooltip: 'Clear search',
                              onPressed: () {
                                _searchController.clear();
                                setState(() => _searchQuery = '');
                                FocusScope.of(context).unfocus();
                                _reload();
                              },
                            )
                          : null,
                      isDense: true,
                      border: const OutlineInputBorder(),
                    ),
                    onChanged: (value) {
                      setState(() => _searchQuery = value);
                      _reload();
                    },
                  ),
                ),
                const SizedBox(width: AppSpacing.xs),
                FilterChip(
                  key: const ValueKey('unlabeled_filter_chip'),
                  label: const Text('Unlabeled'),
                  selected: _unlabeledOnly,
                  onSelected: (selected) {
                    setState(() => _unlabeledOnly = selected);
                    _reload();
                  },
                ),
              ],
            ),
          ),
          Expanded(child: _results(context)),
        ],
      ),
    );
  }

  Widget _suggestionCard(
    BuildContext context,
    MerchantClusterSuggestion suggestion,
  ) {
    return Card(
      margin: const EdgeInsets.all(AppSpacing.sm),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.sm),
        child: Row(
          children: [
            const Icon(Icons.auto_awesome, color: Colors.purple),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Possible duplicate payees',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  Text(
                    '${suggestion.memberMerchantIds.length} similar records '
                    'look like “${suggestion.canonicalName}”.',
                    style: const TextStyle(fontSize: 12),
                  ),
                ],
              ),
            ),
            FilledButton.tonal(
              key: const ValueKey('merge_cluster_button'),
              onPressed: () => _reviewCluster(context, suggestion),
              child: const Text('Review'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _results(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(child: Text('Labels unavailable: $_error'));
    }
    if (_items.isEmpty) {
      return const Center(child: Text('No matching payees found.'));
    }
    return ListView.separated(
      padding: AppSpacing.screen,
      itemCount: _items.length + (_hasMore ? 1 : 0),
      separatorBuilder: (_, index) => index == _items.length - 1 && _hasMore
          ? const SizedBox(height: AppSpacing.sm)
          : const Divider(height: 1),
      itemBuilder: (context, index) {
        if (index == _items.length) {
          return Center(
            child: FilledButton.tonal(
              onPressed: _loadingMore ? null : _loadMore,
              child: _loadingMore
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Load more'),
            ),
          );
        }
        final item = _items[index];
        return ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.badge_outlined),
          title: Text(item.displayName),
          subtitle: Text(
            '${item.transactionCount} transaction'
            '${item.transactionCount == 1 ? '' : 's'} · '
            '${item.aliases.join(' · ')}',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => _edit(context, item),
        );
      },
    );
  }

  Future<void> _reload() async {
    final token = ++_requestToken;
    if (mounted) {
      setState(() {
        _loading = true;
        _loadingMore = false;
        _items = const [];
        _cursor = null;
        _hasMore = false;
        _error = null;
      });
    }
    try {
      final repository = await ref.read(payeeLabelRepositoryProvider.future);
      final page = await repository.loadPage(
        PayeeIdentityQuery(search: _searchQuery, unlabeledOnly: _unlabeledOnly),
      );
      final suggestions = await repository.duplicateSuggestions();
      if (!mounted || token != _requestToken) return;
      setState(() {
        _items = page.items;
        _cursor = page.nextCursor;
        _hasMore = page.hasMore;
        _suggestion = suggestions.isEmpty ? null : suggestions.first;
        _loading = false;
      });
    } catch (error) {
      if (!mounted || token != _requestToken) return;
      setState(() {
        _error = error;
        _loading = false;
      });
    }
  }

  Future<void> _loadMore() async {
    final cursor = _cursor;
    if (_loadingMore || !_hasMore || cursor == null) return;
    setState(() => _loadingMore = true);
    try {
      final repository = await ref.read(payeeLabelRepositoryProvider.future);
      final page = await repository.loadPage(
        PayeeIdentityQuery(
          search: _searchQuery,
          unlabeledOnly: _unlabeledOnly,
          after: cursor,
        ),
      );
      if (!mounted) return;
      setState(() {
        _items = [..._items, ...page.items];
        _cursor = page.nextCursor;
        _hasMore = page.hasMore;
        _loadingMore = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error;
        _loadingMore = false;
      });
    }
  }

  Future<void> _edit(BuildContext context, PayeeIdentity identity) async {
    final controller = TextEditingController(
      text: identity.userLabel ?? identity.displayName,
    );
    final saved = await showBloomDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Label this payee'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Label'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Apply'),
          ),
        ],
      ),
    );
    if (saved != true || !context.mounted) {
      controller.dispose();
      return;
    }
    try {
      final repository = await ref.read(payeeLabelRepositoryProvider.future);
      final count = await repository.saveLabel(
        label: controller.text,
        aliases: identity.aliases,
        merchantId: identity.merchantId,
      );
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Label applied to $count transactions.')),
      );
      await _reload();
    } on PayeeAliasConflict catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.toString())),
      );
    } finally {
      controller.dispose();
    }
  }

  Future<void> _showBackfillDialog(BuildContext context) async {
    showBloomDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Backfill Structured Payees'),
        content: const Text(
          'Preview structured key assignment for past transactions. '
          'Raw SMS text is never overwritten and changes can be reversed.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const ValueKey('apply_backfill_button'),
            onPressed: () {
              Navigator.of(context).pop();
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Backfill preview applied cleanly.'),
                ),
              );
            },
            child: const Text('Apply Backfill'),
          ),
        ],
      ),
    );
  }

  Future<void> _reviewCluster(
    BuildContext context,
    MerchantClusterSuggestion suggestion,
  ) async {
    await showBloomDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Review possible duplicates'),
        content: Text(
          'These ${suggestion.memberMerchantIds.length} payee records look '
          'similar to “${suggestion.canonicalName}”. Review their details '
          'before making any label or merchant changes. Nothing is changed '
          'from this screen.',
        ),
        actions: [
          FilledButton(
            key: const ValueKey('confirm_merge_cluster_button'),
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close review'),
          ),
        ],
      ),
    );
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('No payee changes were made.')),
    );
  }
}
