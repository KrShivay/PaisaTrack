import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_tokens.dart';
import '../../core/theme/app_theme.dart';
import '../../core/util/debouncer.dart';
import '../../core/widgets/bloom/bloom.dart';
import '../../data/db/database_provider.dart';
import '../../intelligence/assistant/assistant_controller.dart';
import '../../intelligence/assistant/prompt_catalogue.dart';
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
    } catch (e) {
      if (mounted) {
        // Sanitize error — never expose stack traces or internal details.
        final userMessage = e is LlmUnavailable
            ? 'The on-device AI model is not available. You can still search your transactions by keyword.'
            : 'I could not calculate that from your data. Try asking about recent spend, budget, or categories.';
        setState(() {
          _messages.add(
            AssistantMessage(userMessage, fromUser: false),
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
            Expanded(
              child: Text(
                'Ask PaisaTrack',
                style: AppTheme.bloomDisplay(
                  18,
                  FontWeight.w700,
                  color: isDark
                      ? AppColorTokens.bloomDarkTextPrimary
                      : AppColorTokens.ink,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
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
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
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
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            // On-device privacy badge
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: isDark
                      ? AppColorTokens.bloomEmerald.withValues(alpha: 0.15)
                      : const Color(0xFFE8F5E9),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.shield_outlined,
                      size: 14,
                      color: AppColorTokens.bloomEmerald,
                    ),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        'On-device · no internet used',
                        style: AppTheme.bloomDisplay(
                          11,
                          FontWeight.w500,
                          color: AppColorTokens.bloomEmerald,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 4),
            const Divider(height: 1),

            // Message Thread / Presets
            Expanded(
              child: _messages.isEmpty
                  ? _PromptCatalogueEmptyState(
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

class _PromptCatalogueEmptyState extends StatefulWidget {
  const _PromptCatalogueEmptyState({
    required this.isDark,
    required this.onSelect,
  });

  final bool isDark;
  final ValueChanged<String> onSelect;

  @override
  State<_PromptCatalogueEmptyState> createState() =>
      _PromptCatalogueEmptyStateState();
}

class _PromptCatalogueEmptyStateState
    extends State<_PromptCatalogueEmptyState> {
  final _searchController = TextEditingController();
  final _debouncer = Debouncer(delay: const Duration(milliseconds: 300));
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    _debouncer.dispose();
    super.dispose();
  }

  List<AssistantPromptGroup> get _visibleGroups {
    final query = _query.trim().toLowerCase();
    if (query.isEmpty) return assistantPromptCatalogue;
    return [
      for (final group in assistantPromptCatalogue)
        if (group.label.toLowerCase().contains(query))
          group
        else
          AssistantPromptGroup(
            id: group.id,
            label: group.label,
            icon: group.icon,
            questions: [
              for (final question in group.questions)
                if (question.toLowerCase().contains(query)) question,
            ],
          ),
    ].where((group) => group.questions.isNotEmpty).toList(growable: false);
  }

  @override
  Widget build(BuildContext context) {
    final groups = _visibleGroups;
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
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
            color: widget.isDark
                ? AppColorTokens.bloomDarkTextPrimary
                : AppColorTokens.ink,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 16),
        TextField(
          key: const ValueKey('assistant_prompt_search_field'),
          controller: _searchController,
          onChanged: (value) => _debouncer.run(() {
            if (mounted) setState(() => _query = value);
          }),
          decoration: const InputDecoration(
            hintText: 'Search questions...',
            prefixIcon: Icon(Icons.search),
            border: OutlineInputBorder(),
            isDense: true,
          ),
        ),
        const SizedBox(height: 12),
        if (groups.isEmpty)
          const Padding(
            padding: EdgeInsets.all(24),
            child: Center(child: Text('No matching questions.')),
          )
        else
          for (final group in groups) ...[
            Padding(
              padding: const EdgeInsets.only(top: 8, bottom: 4),
              child: Row(
                children: [
                  Icon(
                    group.icon,
                    size: 18,
                    color: widget.isDark
                        ? AppColorTokens.bloomDarkTextSecondary
                        : AppColorTokens.inkSecondary,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    group.label,
                    style: AppTheme.bloomDisplay(
                      13,
                      FontWeight.w700,
                      color: widget.isDark
                          ? AppColorTokens.bloomDarkTextPrimary
                          : AppColorTokens.ink,
                    ),
                  ),
                ],
              ),
            ),
            for (final question in group.questions)
              Card(
                color: widget.isDark
                    ? AppColorTokens.bloomDarkCard
                    : AppColorTokens.bloomCard,
                margin: const EdgeInsets.only(bottom: 6),
                child: InkWell(
                  onTap: () => widget.onSelect(question),
                  borderRadius: BorderRadius.circular(12),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 11,
                    ),
                    child: Text(
                      question,
                      style: AppTheme.bloomDisplay(
                        13,
                        FontWeight.w500,
                        color: widget.isDark
                            ? AppColorTokens.bloomDarkTextSecondary
                            : AppColorTokens.inkSecondary,
                      ),
                    ),
                  ),
                ),
              ),
          ],
      ],
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
