import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_tokens.dart';
import '../../data/repositories/payee_label_repository.dart';

class PayeeLabelsScreen extends ConsumerStatefulWidget {
  const PayeeLabelsScreen({super.key});

  @override
  ConsumerState<PayeeLabelsScreen> createState() => _PayeeLabelsScreenState();
}

class _PayeeLabelsScreenState extends ConsumerState<PayeeLabelsScreen> {
  String _searchQuery = '';
  bool _unlabeledOnly = false;

  @override
  Widget build(BuildContext context) {
    final identities = ref.watch(payeeIdentitiesProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Payee labels')),
      body: identities.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(child: Text('Labels unavailable: $error')),
        data: (items) {
          if (items.isEmpty) {
            return const Center(child: Text('No merchants or UPI IDs found yet.'));
          }

          final filtered = items.where((item) {
            if (_unlabeledOnly && item.userLabel != null) return false;
            if (_searchQuery.isEmpty) return true;
            final q = _searchQuery.toLowerCase();
            final nameMatches = item.displayName.toLowerCase().contains(q);
            final labelMatches =
                item.userLabel?.toLowerCase().contains(q) == true;
            final aliasMatches =
                item.aliases.any((a) => a.toLowerCase().contains(q));
            return nameMatches || labelMatches || aliasMatches;
          }).toList(growable: false);

          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(AppSpacing.sm),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        key: const ValueKey('payee_labels_search_field'),
                        decoration: InputDecoration(
                          hintText: 'Search payees or aliases...',
                          prefixIcon: const Icon(Icons.search),
                          suffixIcon: _searchQuery.isNotEmpty
                              ? IconButton(
                                  icon: const Icon(Icons.clear),
                                  onPressed: () =>
                                      setState(() => _searchQuery = ''),
                                )
                              : null,
                          isDense: true,
                          border: const OutlineInputBorder(),
                        ),
                        onChanged: (value) =>
                            setState(() => _searchQuery = value),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.xs),
                    FilterChip(
                      key: const ValueKey('unlabeled_filter_chip'),
                      label: const Text('Unlabeled'),
                      selected: _unlabeledOnly,
                      onSelected: (selected) =>
                          setState(() => _unlabeledOnly = selected),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: filtered.isEmpty
                    ? const Center(child: Text('No matching payees found.'))
                    : ListView.separated(
                        padding: AppSpacing.screen,
                        itemCount: filtered.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (context, index) {
                          final item = filtered[index];
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
                            onTap: () => _edit(context, ref, item),
                          );
                        },
                      ),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _edit(
    BuildContext context,
    WidgetRef ref,
    PayeeIdentity identity,
  ) async {
    final controller = TextEditingController(
      text: identity.userLabel ?? identity.displayName,
    );
    final selectedAliases = identity.aliases.toSet();
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Label this payee'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: controller,
                  autofocus: true,
                  decoration: const InputDecoration(labelText: 'Label'),
                ),
                const SizedBox(height: AppSpacing.md),
                Text(
                  'Aliases to include',
                  style: Theme.of(context).textTheme.labelLarge,
                ),
                for (final alias in identity.aliases)
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    title: Text(alias),
                    value: selectedAliases.contains(alias),
                    onChanged: (selected) => setState(() {
                      if (selected == true) {
                        selectedAliases.add(alias);
                      } else {
                        selectedAliases.remove(alias);
                      }
                    }),
                  ),
                Text(
                  '${identity.transactionCount} historical transaction'
                  '${identity.transactionCount == 1 ? '' : 's'} will be '
                  'previewed again before saving. Original merchant and UPI '
                  'evidence is retained.',
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: selectedAliases.isEmpty && identity.merchantId == null
                  ? null
                  : () => Navigator.of(context).pop(true),
              child: const Text('Preview'),
            ),
          ],
        ),
      ),
    );
    if (saved != true || !context.mounted) return;

    final repository = await ref.read(payeeLabelRepositoryProvider.future);
    final preview = await repository.preview(
      aliases: selectedAliases,
      merchantId: identity.merchantId,
    );
    if (!context.mounted) return;
    if (preview.hasConflicts) {
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Aliases conflict'),
          content: Text(
            '${preview.conflictingAliases.join(', ')} already belong to '
            'another payee. No changes were made.',
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('OK'),
            ),
          ],
        ),
      );
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Apply label?'),
        content: Text(
          '${preview.affectedTransactionCount} historical transaction'
          '${preview.affectedTransactionCount == 1 ? '' : 's'} will display '
          'as “${controller.text.trim()}”.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Back'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Apply'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    try {
      final count = await repository.saveLabel(
        label: controller.text,
        aliases: selectedAliases,
        merchantId: identity.merchantId,
      );
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Label applied to $count transactions.')),
      );
    } on PayeeAliasConflict catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.toString())),
      );
    }
  }
}
