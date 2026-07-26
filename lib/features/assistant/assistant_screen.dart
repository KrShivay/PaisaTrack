import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_tokens.dart';
import '../../data/db/database_provider.dart';
import '../../intelligence/assistant/assistant_controller.dart';
import '../../intelligence/llm/llm_runtime.dart';
import '../transactions/transactions_screen.dart';

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
  String _selectedCategoryId = 'all';

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

  void _askSuggestion(String question) {
    _input.text = question;
    _send();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Ask PaisaTrack')),
      body: Column(
        children: [
          Expanded(
            child: _messages.isEmpty
                ? _AssistantWelcome(
                    selectedCategory: _selectedCategoryId,
                    onCategorySelected: (id) =>
                        setState(() => _selectedCategoryId = id),
                    onQuestion: _askSuggestion,
                  )
                : ListView.builder(
                    padding: AppSpacing.screen,
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
                            padding: const EdgeInsets.all(AppSpacing.md),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(message.text),
                                if (!message.fromUser) ...[
                                  const SizedBox(height: AppSpacing.sm),
                                  TextButton.icon(
                                    onPressed: () => Navigator.of(context).push(
                                      MaterialPageRoute<void>(
                                        builder: (_) =>
                                            const TransactionsScreen(),
                                      ),
                                    ),
                                    icon:
                                        const Icon(Icons.receipt_long_outlined),
                                    label: const Text(
                                      'View supporting transactions',
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
          ),
          if (_messages.isNotEmpty)
            _SuggestedQuestionsTray(
              selectedCategory: _selectedCategoryId,
              onCategorySelected: (id) =>
                  setState(() => _selectedCategoryId = id),
              onQuestion: _sending ? null : _askSuggestion,
            ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.md,
                AppSpacing.sm,
                AppSpacing.md,
                AppSpacing.md,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _input,
                      enabled: !_sending,
                      onSubmitted: (_) => _send(),
                      decoration: const InputDecoration(
                        hintText: 'Ask about your money…',
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
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

class _AssistantCategory {
  const _AssistantCategory({
    required this.id,
    required this.label,
    required this.icon,
    required this.questions,
  });

  final String id;
  final String label;
  final IconData icon;
  final List<String> questions;
}

const _allCategories = <_AssistantCategory>[
  _AssistantCategory(
    id: 'spending',
    label: 'Spending',
    icon: Icons.account_balance_wallet_outlined,
    questions: [
      'How much did I spend on food this month?',
      'What is my total spending this month?',
      'How much did I spend yesterday?',
      'How much did I spend last month?',
      'What are my total expenses this year?',
      'How much did I spend on shopping this month?',
      'How much did I spend on travel last week?',
      'What is my average daily spend this month?',
    ],
  ),
  _AssistantCategory(
    id: 'breakdown',
    label: 'Breakdowns',
    icon: Icons.pie_chart_outline,
    questions: [
      'Where did my money go this month?',
      'Break down spending by category',
      'Which categories did I spend most on?',
      'Show me category breakdown for last month',
      'Top spending categories this month',
      'What is my spending split this week?',
    ],
  ),
  _AssistantCategory(
    id: 'subscriptions',
    label: 'Subscriptions & Bills',
    icon: Icons.event_repeat_outlined,
    questions: [
      'What subscriptions renew this week?',
      'Which bills are coming up next week?',
      'Show upcoming recurring payments',
      'What payments are due this month?',
      'How much do I pay for recurring bills?',
      'Any autopay payments scheduled soon?',
    ],
  ),
  _AssistantCategory(
    id: 'income',
    label: 'Income & Savings',
    icon: Icons.trending_up_outlined,
    questions: [
      'How much income did I earn this month?',
      'What was my total inflow last month?',
      'How much money did I save this month?',
      'What is my net balance change this month?',
      'How much salary was credited this month?',
      'Show all credit transactions this month',
    ],
  ),
  _AssistantCategory(
    id: 'comparisons',
    label: 'Trends & Compare',
    icon: Icons.compare_arrows_outlined,
    questions: [
      'Why is spending higher than last month?',
      'Compare spending this month vs last month',
      'How does this week compare to last week?',
      'Compare Q1 vs Q2 spending',
      'Is my spending up or down from last month?',
      'Compare spending this year vs last year',
    ],
  ),
  _AssistantCategory(
    id: 'insights',
    label: 'Insights & Alerts',
    icon: Icons.auto_awesome_outlined,
    questions: [
      'Show active spending insights',
      'Is there any unusual spending lately?',
      'Do I have any budget alerts?',
      'Show spending anomalies this month',
      'What unusual transactions happened this month?',
    ],
  ),
  _AssistantCategory(
    id: 'merchants',
    label: 'Merchants & Fees',
    icon: Icons.storefront_outlined,
    questions: [
      'How many payments did I make this month?',
      'How much did I pay in bank fees?',
      'How much did I pay at Swiggy?',
      'Show me transactions at Amazon',
      'How many debit transactions were made this week?',
      'Average payment amount this month',
    ],
  ),
];

class _SuggestedQuestionsTray extends StatelessWidget {
  const _SuggestedQuestionsTray({
    required this.selectedCategory,
    required this.onCategorySelected,
    required this.onQuestion,
  });

  final String selectedCategory;
  final ValueChanged<String> onCategorySelected;
  final ValueChanged<String>? onQuestion;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final questions = selectedCategory == 'all'
        ? _allCategories.expand((c) => c.questions).toList()
        : _allCategories
            .firstWhere(
              (c) => c.id == selectedCategory,
              orElse: () => _allCategories.first,
            )
            .questions;

    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        border: Border(
          top: BorderSide(
            color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
          ),
        ),
      ),
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
            child: Row(
              children: [
                Padding(
                  padding: const EdgeInsets.only(right: AppSpacing.xs),
                  child: FilterChip(
                    label: const Text('All Questions'),
                    selected: selectedCategory == 'all',
                    onSelected: (_) => onCategorySelected('all'),
                    visualDensity: VisualDensity.compact,
                  ),
                ),
                for (final cat in _allCategories)
                  Padding(
                    padding: const EdgeInsets.only(right: AppSpacing.xs),
                    child: FilterChip(
                      avatar: Icon(cat.icon, size: 16),
                      label: Text(cat.label),
                      selected: selectedCategory == cat.id,
                      onSelected: (_) => onCategorySelected(cat.id),
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
            child: Row(
              children: [
                for (final q in questions)
                  Padding(
                    padding: const EdgeInsets.only(right: AppSpacing.xs),
                    child: ActionChip(
                      label: Text(q),
                      onPressed:
                          onQuestion != null ? () => onQuestion!(q) : null,
                      visualDensity: VisualDensity.compact,
                      elevation: 0,
                      backgroundColor: theme.colorScheme.surfaceContainer,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AssistantWelcome extends StatelessWidget {
  const _AssistantWelcome({
    required this.selectedCategory,
    required this.onCategorySelected,
    required this.onQuestion,
  });

  final String selectedCategory;
  final ValueChanged<String> onCategorySelected;
  final ValueChanged<String> onQuestion;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final displayedCategories = selectedCategory == 'all'
        ? _allCategories
        : _allCategories.where((c) => c.id == selectedCategory).toList();

    return ListView(
      padding: AppSpacing.screen,
      children: [
        Container(
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            color: theme.colorScheme.primaryContainer,
            borderRadius: BorderRadius.circular(AppRadius.lg),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.lock_outline,
                color: theme.colorScheme.onPrimaryContainer,
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Text(
                  'Your questions and financial data stay on this device.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onPrimaryContainer,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        Text('Try asking', style: theme.textTheme.titleLarge),
        const SizedBox(height: AppSpacing.sm),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              Padding(
                padding: const EdgeInsets.only(right: AppSpacing.xs),
                child: FilterChip(
                  label: const Text('All'),
                  selected: selectedCategory == 'all',
                  onSelected: (_) => onCategorySelected('all'),
                ),
              ),
              for (final cat in _allCategories)
                Padding(
                  padding: const EdgeInsets.only(right: AppSpacing.xs),
                  child: FilterChip(
                    avatar: Icon(cat.icon, size: 18),
                    label: Text(cat.label),
                    selected: selectedCategory == cat.id,
                    onSelected: (_) => onCategorySelected(cat.id),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        for (final category in displayedCategories) ...[
          Padding(
            padding: const EdgeInsets.only(
              top: AppSpacing.sm,
              bottom: AppSpacing.xs,
            ),
            child: Row(
              children: [
                Icon(
                  category.icon,
                  size: 20,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: AppSpacing.xs),
                Text(
                  category.label,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: theme.colorScheme.primary,
                  ),
                ),
              ],
            ),
          ),
          for (final question in category.questions)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.xs),
              child: InkWell(
                borderRadius: BorderRadius.circular(AppRadius.md),
                onTap: () => onQuestion(question),
                child: Container(
                  constraints: const BoxConstraints(minHeight: 48),
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.md,
                    vertical: AppSpacing.sm,
                  ),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainer,
                    borderRadius: BorderRadius.circular(AppRadius.md),
                  ),
                  child: Row(
                    children: [
                      Expanded(child: Text(question)),
                      const SizedBox(width: AppSpacing.sm),
                      const Icon(Icons.arrow_forward, size: 18),
                    ],
                  ),
                ),
              ),
            ),
          const SizedBox(height: AppSpacing.sm),
        ],
      ],
    );
  }
}
