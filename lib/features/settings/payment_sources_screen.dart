import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_tokens.dart';
import '../../data/repositories/payment_source_repository.dart';

class PaymentSourcesScreen extends ConsumerWidget {
  const PaymentSourcesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sources = ref.watch(paymentSourcesProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Accounts and payment sources')),
      body: sources.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) =>
            Center(child: Text('Accounts unavailable: $error')),
        data: (items) => items.isEmpty
            ? const Center(
                child: Text('No masked account or payment source found yet.'),
              )
            : ListView.separated(
                padding: AppSpacing.screen,
                itemCount: items.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final source = items[index];
                  return _PaymentSourceTile(source: source);
                },
              ),
      ),
    );
  }
}

class _PaymentSourceTile extends ConsumerWidget {
  const _PaymentSourceTile({required this.source});

  final PaymentSourceSummary source;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final details = <String>[
      source.kind.toUpperCase(),
      if (source.institution?.trim().isNotEmpty == true) source.institution!,
      source.maskedIdentifier,
      '${source.transactionCount} transactions',
      if (source.transferCount > 0) '${source.transferCount} owned transfers',
    ];
    return ExpansionTile(
      tilePadding: EdgeInsets.zero,
      title: Text(source.displayName),
      subtitle: Text(details.join(' · ')),
      leading: const Icon(Icons.account_balance_wallet_outlined),
      children: [
        ListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Nickname'),
          subtitle: Text(source.nickname ?? 'Not set'),
          trailing: const Icon(Icons.edit_outlined),
          onTap: () => _editNickname(context, ref),
        ),
        ListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Institution'),
          subtitle: Text(source.institution ?? 'Not set'),
          trailing: const Icon(Icons.edit_outlined),
          onTap: () => _editInstitution(context, ref),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Active source'),
          value: source.isActive,
          onChanged: (value) => _update(ref, isActive: Value(value)),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Owned by me'),
          subtitle: const Text('Enables transfer recognition between sources'),
          value: source.isOwned,
          onChanged: (value) => _update(
            ref,
            isOwned: Value(value),
          ),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Include in analytics'),
          subtitle: const Text('Transactions remain visible when excluded'),
          value: source.includeInAnalytics,
          onChanged: (value) => _update(
            ref,
            includeInAnalytics: Value(value),
          ),
        ),
      ],
    );
  }

  Future<void> _editNickname(BuildContext context, WidgetRef ref) async {
    final controller = TextEditingController(text: source.nickname);
    final nickname = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Source nickname'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'e.g. Salary account'),
          onSubmitted: (value) => Navigator.of(context).pop(value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(controller.text),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (nickname == null) return;
    await _update(
      ref,
      nickname: Value(nickname.trim().isEmpty ? null : nickname.trim()),
    );
  }

  Future<void> _editInstitution(BuildContext context, WidgetRef ref) async {
    final controller = TextEditingController(text: source.institution);
    final institution = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Financial institution'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'e.g. HDFC Bank'),
          onSubmitted: (value) => Navigator.of(context).pop(value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(controller.text),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (institution == null) return;
    await _update(
      ref,
      institution: Value(
        institution.trim().isEmpty ? null : institution.trim(),
      ),
    );
  }

  Future<void> _update(
    WidgetRef ref, {
    Value<String?> nickname = const Value.absent(),
    Value<String?> institution = const Value.absent(),
    Value<bool> includeInAnalytics = const Value.absent(),
    Value<bool> isOwned = const Value.absent(),
    Value<bool> isActive = const Value.absent(),
  }) async {
    final repository = await ref.read(paymentSourceRepositoryProvider.future);
    await repository.updateSource(
      sourceId: source.id,
      nickname: nickname,
      institution: institution,
      includeInAnalytics: includeInAnalytics,
      isOwned: isOwned,
      isActive: isActive,
    );
  }
}
