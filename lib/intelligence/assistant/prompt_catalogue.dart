import 'package:flutter/material.dart';

/// Curated questions shown by Ask PaisaTrack.
///
/// Keep these strings aligned with [AssistantIntentClassifier] and
/// [IntentValidator]. The catalogue test exercises that contract so a shipped
/// suggestion cannot silently become an unsupported request.
class AssistantPromptGroup {
  const AssistantPromptGroup({
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

const assistantPromptCatalogue = <AssistantPromptGroup>[
  AssistantPromptGroup(
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
      'How much did I spend on groceries this month?',
      'What is my average daily spend this month?',
    ],
  ),
  AssistantPromptGroup(
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
  AssistantPromptGroup(
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
  AssistantPromptGroup(
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
  AssistantPromptGroup(
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
  AssistantPromptGroup(
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
  AssistantPromptGroup(
    id: 'merchants',
    label: 'Merchants & Fees',
    icon: Icons.storefront_outlined,
    questions: [
      'How many payments did I make this month?',
      'How much did I pay in bank fees?',
      'How much on Swiggy this month?',
      'Show me transactions at Amazon',
      'How many debit transactions were made this week?',
      'Average payment amount this month',
    ],
  ),
];

final assistantPromptQuestions = [
  for (final group in assistantPromptCatalogue) ...group.questions,
];
