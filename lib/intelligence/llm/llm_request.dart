enum LlmTask {
  jsonExtraction,
  assistantIntent,
  narrative;

  String get wireValue => name;
}

class LlmRequest {
  const LlmRequest({
    required this.systemInstruction,
    required this.userMessage,
    required this.task,
  });

  final String systemInstruction;
  final String userMessage;
  final LlmTask task;

  bool get isValid =>
      systemInstruction.trim().isNotEmpty && userMessage.trim().isNotEmpty;
}
