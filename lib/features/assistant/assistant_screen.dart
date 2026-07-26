import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_tokens.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/bloom/bloom.dart';
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

class AssistantMessage {
  const AssistantMessage(this.text, {required this.fromUser});

  final String text;
  final bool fromUser;
}

/// Redesigned Bloom Ask PaisaTrack assistant sheet.
class AssistantScreen extends ConsumerStatefulWidget {
  const AssistantScreen({super.key});

  @override
  ConsumerState<AssistantScreen> createState() => _AssistantScreenState();
}

class _AssistantScreenState extends ConsumerState<AssistantScreen> {
  final _inputController = TextEditingController();
  final _messages = <AssistantMessage>[];
  bool _sending = false;

  @override
  void dispose() {
    _inputController.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _inputController.text.trim();
    if (text.isEmpty || _sending) return;
    setState(() {
      _sending = true;
      _messages.add(AssistantMessage(text, fromUser: true));
      _inputController.clear();
    });

    try {
      final controller = await ref.read(assistantControllerProvider.future);
      final answer = await controller.ask(text);
      if (mounted) {
        setState(() {
          _messages.add(AssistantMessage(answer, fromUser: false));
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _messages.add(
            const AssistantMessage(
              'I could not calculate that from your data. Try asking about recent spend, budget, or categories.',
              fromUser: false,
            ),
          );
        });
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  void _askSuggestion(String question) {
    _inputController.text = question;
    _send();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor:
          isDark ? AppColorTokens.bloomDarkBase : AppColorTokens.bloomBase,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        title: Row(
          children: [
            const BloomMascot(
              size: 28,
              bob: true,
              pulseRing: false,
            ),
            const SizedBox(width: 8),
            Text(
              'Ask PaisaTrack',
              style: AppTheme.bloomDisplay(
                18,
                FontWeight.w700,
                color: isDark
                    ? AppColorTokens.bloomDarkTextPrimary
                    : AppColorTokens.ink,
              ),
            ),
          ],
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Header Row with Mascot
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              child: Row(
                children: [
                  const BloomMascot(
                    size: 32,
                    bob: true,
                    pulseRing: false,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Ask PaisaTrack',
                          style: AppTheme.bloomDisplay(
                            16,
                            FontWeight.w700,
                            color: isDark
                                ? AppColorTokens.bloomDarkTextPrimary
                                : AppColorTokens.ink,
                          ),
                        ),
                        Text(
                          'Natural language financial search',
                          style: AppTheme.bloomDisplay(
                            11,
                            FontWeight.w400,
                            color: isDark
                                ? AppColorTokens.bloomDarkTextTertiary
                                : AppColorTokens.inkTertiary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),

            // Message Thread / Presets
            Expanded(
              child: _messages.isEmpty
                  ? _PresetQuestions(
                      isDark: isDark,
                      onSelect: _askSuggestion,
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.all(20),
                      itemCount: _messages.length,
                      itemBuilder: (context, index) {
                        final msg = _messages[index];
                        return _MessageBubble(msg: msg, isDark: isDark);
                      },
                    ),
            ),

            if (_sending)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: BloomSkeleton(width: 160, height: 24),
              ),

            // Bottom Input Bar
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
              child: Container(
                height: 48,
                decoration: BoxDecoration(
                  color: isDark
                      ? AppColorTokens.bloomDarkCard
                      : const Color(0xFFF1EFFB),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  children: [
                    const SizedBox(width: 16),
                    Expanded(
                      child: TextField(
                        controller: _inputController,
                        onSubmitted: (_) => _send(),
                        style: AppTheme.bloomDisplay(
                          14,
                          FontWeight.w400,
                          color: isDark
                              ? AppColorTokens.bloomDarkTextPrimary
                              : AppColorTokens.ink,
                        ),
                        decoration: InputDecoration(
                          hintText: 'Ask anything about your money...',
                          hintStyle: AppTheme.bloomDisplay(
                            14,
                            FontWeight.w400,
                            color: isDark
                                ? AppColorTokens.bloomDarkTextTertiary
                                : AppColorTokens.inkTertiary,
                          ),
                          border: InputBorder.none,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    GestureDetector(
                      onTap: _send,
                      child: Container(
                        width: 36,
                        height: 36,
                        margin: const EdgeInsets.only(right: 6),
                        decoration: const BoxDecoration(
                          color: AppColorTokens.violetPrimary,
                          shape: BoxShape.circle,
                        ),
                        child: const Center(
                          child: Icon(
                            Icons.arrow_upward_rounded,
                            size: 20,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PresetQuestions extends StatelessWidget {
  const _PresetQuestions({
    required this.isDark,
    required this.onSelect,
  });

  final bool isDark;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    final presets = [
      'How much on Swiggy this month?',
      'Can I afford a ₹5,000 dinner?',
      'Show food vs shopping',
      "What's my burn rate?",
    ];

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      child: Center(
        child: SingleChildScrollView(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Center(
                child: BloomMascot(
                  size: 54,
                  bob: true,
                  pulseRing: true,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'What would you like to know?',
                style: AppTheme.bloomDisplay(
                  16,
                  FontWeight.w600,
                  color: isDark
                      ? AppColorTokens.bloomDarkTextPrimary
                      : AppColorTokens.ink,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              for (final q in presets) ...[
                GestureDetector(
                  onTap: () => onSelect(q),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    decoration: BoxDecoration(
                      color: isDark
                          ? AppColorTokens.bloomDarkCard
                          : AppColorTokens.bloomCard,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: isDark
                            ? AppColorTokens.bloomDarkOutline
                            : AppColorTokens.bloomChip,
                      ),
                    ),
                    child: Text(
                      q,
                      style: AppTheme.bloomDisplay(
                        13,
                        FontWeight.w500,
                        color: isDark
                            ? AppColorTokens.bloomDarkTextSecondary
                            : AppColorTokens.inkSecondary,
                      ),
                    ),
                  ),
                ),
                if (q != presets.last) const SizedBox(height: 10),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({
    required this.msg,
    required this.isDark,
  });

  final AssistantMessage msg;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    if (msg.fromUser) {
      return Align(
        alignment: Alignment.centerRight,
        child: Container(
          margin: const EdgeInsets.only(bottom: 12, left: 40),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: const BoxDecoration(
            color: AppColorTokens.violetPrimary,
            borderRadius: BorderRadius.only(
              topLeft: Radius.circular(18),
              topRight: Radius.circular(18),
              bottomLeft: Radius.circular(18),
              bottomRight: Radius.circular(4),
            ),
          ),
          child: Text(
            msg.text,
            style: AppTheme.bloomDisplay(
              14,
              FontWeight.w500,
              color: Colors.white,
            ),
          ),
        ),
      );
    }

    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12, right: 40),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color:
              isDark ? AppColorTokens.bloomDarkCard : const Color(0xFFF6F4FE),
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(4),
            topRight: Radius.circular(18),
            bottomLeft: Radius.circular(18),
            bottomRight: Radius.circular(18),
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const BloomMascot(
              size: 24,
              bob: false,
              pulseRing: false,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                msg.text,
                style: AppTheme.bloomDisplay(
                  14,
                  FontWeight.w400,
                  color: isDark
                      ? AppColorTokens.bloomDarkTextPrimary
                      : AppColorTokens.ink,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
