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
    final extracted =
        await runtime.extractJson(_prompt(question), assistantIntentSchema);
    if (extracted is LlmUnavailable<Map<String, Object?>>) {
      return _record(
        'The on-device assistant is unavailable. Download the model in Settings and try again.',
      );
    }
    final categories = {
      for (final row in await database.select(database.categories).get())
        row.id: row.name,
    };
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

  static String _prompt(String question) =>
      'Classify this money question into exactly one supported intent. Never answer it, never emit SQL, and emit unsupported when it does not fit. Question: $question';
}
