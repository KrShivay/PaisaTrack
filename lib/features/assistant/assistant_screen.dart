import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/db/database_provider.dart';
import '../../intelligence/assistant/assistant_controller.dart';
import '../../intelligence/llm/llm_runtime.dart';

final assistantControllerProvider =
    FutureProvider<AssistantController>((ref) async {
  final database = await ref.watch(appDatabaseProvider.future);
  return AssistantController(
    runtime: ref.watch(llmRuntimeProvider),
    database: database,
  );
});

class AssistantScreen extends ConsumerStatefulWidget {
  const AssistantScreen({super.key});

  @override
  ConsumerState<AssistantScreen> createState() => _AssistantScreenState();
}

class _AssistantScreenState extends ConsumerState<AssistantScreen> {
  final _input = TextEditingController();
  final _messages = <AssistantMessage>[];
  bool _sending = false;

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _input.text.trim();
    if (text.isEmpty || _sending) return;
    setState(() {
      _sending = true;
      _messages.add(AssistantMessage(text, fromUser: true));
      _input.clear();
    });
    try {
      final controller = await ref.read(assistantControllerProvider.future);
      final answer = await controller.ask(text);
      if (mounted) {
        setState(
          () => _messages.add(AssistantMessage(answer, fromUser: false)),
        );
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _messages.add(
            const AssistantMessage(
              'I could not answer that from your local data.',
              fromUser: false,
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Ask PaisaTrack')),
      body: Column(
        children: [
          Expanded(
            child: _messages.isEmpty
                ? const Center(
                    child: Padding(
                      padding: EdgeInsets.all(32),
                      child: Text(
                        'Ask about spending totals, categories, merchants, recurring payments, comparisons, or active insights.',
                        textAlign: TextAlign.center,
                      ),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: _messages.length,
                    itemBuilder: (context, index) {
                      final message = _messages[index];
                      return Align(
                        alignment: message.fromUser
                            ? Alignment.centerRight
                            : Alignment.centerLeft,
                        child: Card(
                          color: message.fromUser
                              ? Theme.of(context).colorScheme.primaryContainer
                              : null,
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Text(message.text),
                          ),
                        ),
                      );
                    },
                  ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _input,
                      enabled: !_sending,
                      onSubmitted: (_) => _send(),
                      decoration: const InputDecoration(
                        hintText: 'Ask about your money',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    onPressed: _sending ? null : _send,
                    icon: _sending
                        ? const SizedBox.square(
                            dimension: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.send),
                    tooltip: 'Send',
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
