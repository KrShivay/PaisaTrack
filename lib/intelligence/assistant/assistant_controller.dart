import '../../data/db/database.dart';
import '../llm/llm_runtime.dart';
import 'answer_renderer.dart';
import 'assistant_intent.dart';
import 'query_engine.dart';

class AssistantMessage {
  const AssistantMessage(this.text, {required this.fromUser});
  final String text;
  final bool fromUser;
}

class AssistantController {
  AssistantController({
    required this.runtime,
    required this.database,
    this.clock = DateTime.now,
  });
  final LlmRuntime runtime;
  final AppDatabase database;
  final DateTime Function() clock;
  final List<AssistantMessage> _history = [];
  List<AssistantMessage> get history => List.unmodifiable(_history);

  Future<String> ask(String text) async {
    final question = text.trim();
    if (question.isEmpty) return 'Ask a question about your money.';
    _history.add(AssistantMessage(question, fromUser: true));
    final categories = {
      for (final row in await database.select(database.categories).get())
        row.id: row.name,
    };
    final extracted = await runtime.extractJson(
      _prompt(question, clock(), categories.values),
      assistantIntentSchema,
    );
    if (extracted is LlmUnavailable<Map<String, Object?>>) {
      return _record(_unavailableMessage(extracted.reason));
    }
    final validated = IntentValidator(categories: categories, clock: clock)
        .validate((extracted as LlmSuccess<Map<String, Object?>>).value);
    if (validated is InvalidIntent) {
      final suggestions = validated.refusal.suggestions.isEmpty
          ? ''
          : '\nTry: ${validated.refusal.suggestions.join(' · ')}';
      return _record('${validated.refusal.message}$suggestions');
    }
    final intent = (validated as ValidIntent).intent;
    final result = await AssistantQueryEngine(database).run(intent);
    return _record(const AnswerRenderer().render(intent, result));
  }

  String _record(String text) {
    _history.add(AssistantMessage(text, fromUser: false));
    return text;
  }

  static String _unavailableMessage(LlmUnavailableReason reason) =>
      switch (reason) {
        LlmUnavailableReason.featureDisabled =>
          'The on-device assistant is turned off for this build.',
        LlmUnavailableReason.modelAbsent =>
          'The on-device assistant is unavailable. Download the model in Settings and try again.',
        LlmUnavailableReason.unsupportedDevice =>
          "This device doesn't have enough memory to run the on-device assistant.",
        LlmUnavailableReason.failure =>
          'I could not understand a clear answer from the on-device model. Try rephrasing your question.',
      };

  static String _prompt(
    String question,
    DateTime today,
    Iterable<String> categoryNames,
  ) {
    final iso = today.toUtc().toIso8601String().substring(0, 10);
    final month = iso.substring(0, 7);
    final categoryList = categoryNames.join(', ');
    return '''
Today's date is $iso. Classify this money question into exactly one supported
intent. Never answer it yourself, never emit SQL or numbers, and emit
"unsupported" when it does not fit one of these:
- period_total: a total/count/average over a period.
- category_breakdown: spend broken down by category over a period.
- merchant_lookup: totals for one named merchant (filter.merchant required).
- month_over_month: compare two periods (needs both time_range and compare_to).
- upcoming_recurring: subscriptions/recurring payments due soon.
- active_insights: currently active budget/spending insights.

Choose "metric" from the question's wording:
- "income", "earned", "received", "salary", "credited" -> "income"
- "spend", "spent", "paid", "expense", "cost", "debited" -> "spend"
- "net", "saved", "left over", "balance change" -> "net"

time_range and compare_to always use one of these shapes (compute real dates
from today's date above; never invent a year):
- {"kind":"month","month":"YYYY-MM"}
- {"kind":"last_n_days","n_days":<int 1-3660>}
- {"kind":"range","start":"YYYY-MM-DD","end":"YYYY-MM-DD"}
- {"kind":"all_time"}

The only valid categories are: $categoryList. Omit "filter" entirely unless
the question names one of these exact categories or a specific merchant.
Never invent a category or use a placeholder like "all" or "total".

Every field except "intent" is optional: omit any field that does not apply
to this question. Never set a field to null, "none", or any other placeholder
— either include a real value or leave the key out entirely.

Your answer is a JSON *values* object, not the schema. Never include the
words "type", "properties", "required", or "additionalProperties" in your
answer — those describe the schema, they are not part of it.

Examples (question -> exact answer), all relative to today $iso:
"How much did I spend this month?" -> {"intent":"period_total","metric":"spend","aggregation":"sum","time_range":{"kind":"month","month":"$month"}}
"What's my income this month?" -> {"intent":"period_total","metric":"income","aggregation":"sum","time_range":{"kind":"month","month":"$month"}}
"Where did my money go this month?" -> {"intent":"category_breakdown","metric":"spend","aggregation":"breakdown","time_range":{"kind":"month","month":"$month"}}
"How much did I spend at Amazon?" -> {"intent":"merchant_lookup","metric":"spend","aggregation":"sum","filter":{"merchant":"Amazon"},"time_range":{"kind":"all_time"}}
"What subscriptions are due soon?" -> {"intent":"upcoming_recurring"}
"Any budget alerts?" -> {"intent":"active_insights"}

Question: $question
''';
  }
}
