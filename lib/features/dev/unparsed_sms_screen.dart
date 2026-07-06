import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/repositories/raw_sms_repository.dart';
import 'unparsed_sms_providers.dart';

/// Developer diagnostics screen listing raw SMS that never produced a
/// transaction (unknown template or not yet processed), so parser coverage
/// gaps are visible without a debugger.
class UnparsedSmsScreen extends ConsumerWidget {
  const UnparsedSmsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final unparsed = ref.watch(unparsedSmsListProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Unparsed SMS (dev)')),
      body: switch (unparsed) {
        AsyncData(:final value) when value.isEmpty =>
          const Center(child: Text('No unparsed messages')),
        AsyncData(:final value) => _UnparsedListView(items: value),
        AsyncError() => const Center(child: Text('Could not load raw SMS')),
        _ => const Center(child: CircularProgressIndicator()),
      },
    );
  }
}

class _UnparsedListView extends StatelessWidget {
  const _UnparsedListView({required this.items});

  final List<UnparsedSms> items;

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      itemCount: items.length,
      separatorBuilder: (context, index) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final sms = items[index];
        return ListTile(
          title: Text(sms.sender),
          subtitle: Text(sms.body, maxLines: 3, overflow: TextOverflow.ellipsis),
        );
      },
    );
  }
}
