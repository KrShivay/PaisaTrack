import 'package:flutter_test/flutter_test.dart';
import 'package:paisatrack/intelligence/assistant/assistant_intent.dart';
import 'package:paisatrack/intelligence/assistant/assistant_intent_classifier.dart';
import 'package:paisatrack/intelligence/assistant/prompt_catalogue.dart';

void main() {
  test('every catalogue question maps to a valid supported intent', () {
    const classifier = AssistantIntentClassifier();
    final validator = IntentValidator(
      categories: const {
        'food': 'Food',
        'shopping': 'Shopping',
        'travel': 'Travel',
      },
      clock: () => DateTime(2026, 7, 12),
    );

    for (final group in assistantPromptCatalogue) {
      expect(group.questions, isNotEmpty, reason: group.id);
      for (final question in group.questions) {
        final json = classifier.classify(
          question,
          today: DateTime(2026, 7, 12),
          categoryNames: const ['Food', 'Shopping', 'Travel'],
        );
        expect(json, isNotNull, reason: '$group.id: $question');
        final result = validator.validate(json!);
        expect(
          result,
          isA<ValidIntent>(),
          reason: '$group.id: $question → $json',
        );
        expect(
          (result as ValidIntent).intent.kind,
          isNotNull,
          reason: '$group.id: $question',
        );
      }
    }

    expect(
      assistantPromptQuestions.length,
      assistantPromptCatalogue.fold<int>(
        0,
        (count, group) => count + group.questions.length,
      ),
    );
  });
}
