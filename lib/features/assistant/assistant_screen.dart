import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_tokens.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/bloom/bloom.dart';
import '../../data/db/database_provider.dart';
import '../../intelligence/assistant/assistant_controller.dart';
import '../../intelligence/assistant/prompt_catalogue.dart';
import '../../intelligence/llm/llm_runtime.dart';

final assistantControllerProvider = FutureProvider<AssistantController>((
  ref,
) async {
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
  const AssistantScreen({super.key, this.showSheetHeader = true});

  final bool showSheetHeader;

  static Widget sheetHeader(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    final availableHeight =
        mediaQuery.size.height - mediaQuery.viewInsets.bottom;
    return _AssistantSheetHeader(compact: availableHeight < 400);
  }

  @override
  ConsumerState<AssistantScreen> createState() => _AssistantScreenState();
}

class _AssistantScreenState extends ConsumerState<AssistantScreen> {
  final _inputController = TextEditingController();
  final _messages = <AssistantMessage>[];
  bool _sending = false;
  int _chipOffset = 0;

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
      _chipOffset = (_chipOffset + 3) % assistantPromptQuestions.length;
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
          _messages.add(AssistantMessage(userMessage, fromUser: false));
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

    return Material(
      key: const ValueKey('assistant_sheet_surface'),
      color: AppColorTokens.bloomDarkBase,
      child: SafeArea(
        child: LayoutBuilder(
          builder: (context, _) {
            return Column(
              children: [
                if (widget.showSheetHeader) const _AssistantSheetHeader(),

                // Message Thread / Presets
                Expanded(
                  child: _messages.isEmpty
                      ? _PromptCatalogueEmptyState(
                          isDark: isDark,
                          onSelect: _askSuggestion,
                        )
                      : LayoutBuilder(
                          builder: (context, bodyConstraints) {
                            // The sheet gives this body less height when the
                            // keyboard opens. Reserve a bounded, scrollable
                            // prompt panel while leaving the conversation able
                            // to shrink without overflowing.
                            final promptListHeight = bodyConstraints.maxHeight <
                                    96
                                ? 0.0
                                : bodyConstraints.maxHeight < 240
                                    ? (bodyConstraints.maxHeight * 0.55).clamp(
                                        72.0,
                                        bodyConstraints.maxHeight - 24.0,
                                      )
                                    : (bodyConstraints.maxHeight * 0.55)
                                        .clamp(96.0, 236.0);
                            return Column(
                              children: [
                                Expanded(
                                  child: ListView.builder(
                                    padding: const EdgeInsets.all(20),
                                    itemCount: _messages.length,
                                    itemBuilder: (context, index) {
                                      final msg = _messages[index];
                                      return _MessageBubble(
                                        msg: msg,
                                        isDark: isDark,
                                      );
                                    },
                                  ),
                                ),
                                if (promptListHeight > 0)
                                  SizedBox(
                                    height: promptListHeight.toDouble(),
                                    child: _ComposerPromptList(
                                      questions: [
                                        for (var index = 0; index < 3; index++)
                                          assistantPromptQuestions[
                                              (_chipOffset + index) %
                                                  assistantPromptQuestions
                                                      .length],
                                      ],
                                      onSelect: _askSuggestion,
                                      onRotate: () => setState(() {
                                        _chipOffset = (_chipOffset + 3) %
                                            assistantPromptQuestions.length;
                                      }),
                                    ),
                                  ),
                              ],
                            );
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
                    key: const ValueKey('assistant_composer'),
                    height: 52,
                    decoration: BoxDecoration(
                      color: AppColorTokens.bloomDarkCard,
                      border: Border.all(
                        color: AppColorTokens.bloomDarkOutline,
                      ),
                      borderRadius: BorderRadius.circular(26),
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
                              color: AppColorTokens.bloomDarkTextPrimary,
                            ),
                            decoration: InputDecoration(
                              hintText: 'Ask anything about your money…',
                              hintStyle: AppTheme.bloomDisplay(
                                14,
                                FontWeight.w400,
                                color: const Color(0xFF6F6A92),
                              ),
                              border: InputBorder.none,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        GestureDetector(
                          key: const ValueKey('assistant_send_button'),
                          onTap: _send,
                          child: Container(
                            width: 40,
                            height: 40,
                            decoration: const BoxDecoration(
                              gradient: LinearGradient(
                                colors: [
                                  AppColorTokens.bloomEmerald,
                                  AppColorTokens.bloomEmeraldDeep,
                                ],
                              ),
                              shape: BoxShape.circle,
                            ),
                            child: const Center(
                              child: Icon(
                                Icons.arrow_upward_rounded,
                                size: 20,
                                color: AppColorTokens.bloomDarkBase,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                      ],
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _ComposerPromptList extends StatelessWidget {
  const _ComposerPromptList({
    required this.questions,
    required this.onSelect,
    required this.onRotate,
  });

  final List<String> questions;
  final ValueChanged<String> onSelect;
  final VoidCallback onRotate;

  @override
  Widget build(BuildContext context) {
    return Column(
      key: const ValueKey('assistant_prompt_list'),
      children: [
        SizedBox(
          height: 48,
          child: Row(
            children: [
              const Expanded(
                child: Text(
                  'Try asking',
                  style: TextStyle(
                    color: AppColorTokens.bloomDarkTextSecondary,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              IconButton(
                key: const ValueKey('assistant_prompt_chip_rotate'),
                tooltip: 'Rotate suggestions',
                icon: const Icon(Icons.refresh_rounded),
                color: AppColorTokens.bloomDarkTextSecondary,
                iconSize: 18,
                onPressed: onRotate,
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.separated(
            key: const ValueKey('assistant_prompt_list_scroll'),
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            itemCount: questions.length,
            separatorBuilder: (_, __) => const SizedBox(height: 6),
            itemBuilder: (context, index) {
              final question = questions[index];
              return SizedBox(
                width: double.infinity,
                child: TextButton(
                  key: ValueKey('assistant_prompt_list_item_$question'),
                  onPressed: () => onSelect(question),
                  style: TextButton.styleFrom(
                    alignment: Alignment.centerLeft,
                    backgroundColor: AppColorTokens.bloomDarkCard,
                    foregroundColor: AppColorTokens.bloomDarkTextSecondary,
                    minimumSize: const Size.fromHeight(48),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                      side: const BorderSide(
                        color: AppColorTokens.bloomDarkOutline,
                      ),
                    ),
                    tapTargetSize: MaterialTapTargetSize.padded,
                    visualDensity: VisualDensity.standard,
                  ),
                  child: Text(
                    question,
                    softWrap: true,
                    textAlign: TextAlign.start,
                    style: const TextStyle(
                      color: AppColorTokens.bloomDarkTextSecondary,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _AssistantSheetHeader extends StatelessWidget {
  const _AssistantSheetHeader({this.compact = false});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    if (compact) {
      return Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                const BloomMascot(size: 28, bob: false, pulseRing: false),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'Ask PaisaTrack',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: AppColorTokens.bloomDarkTextPrimary,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Close',
                  constraints: const BoxConstraints.tightFor(
                    width: 48,
                    height: 48,
                  ),
                  icon: const Icon(
                    Icons.close,
                    color: AppColorTokens.bloomDarkTextSecondary,
                  ),
                  onPressed: () => Navigator.of(context).maybePop(),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: Color(0xFF1E1B33)),
        ],
      );
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 12, 8),
          child: Row(
            children: [
              const BloomMascot(size: 34, bob: true, pulseRing: false),
              const SizedBox(width: 10),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Ask PaisaTrack',
                      style: TextStyle(
                        color: AppColorTokens.bloomDarkTextPrimary,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      'On-device · no internet used',
                      style: TextStyle(
                        color: AppColorTokens.bloomEmerald,
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Close',
                icon: const Icon(
                  Icons.close,
                  color: AppColorTokens.bloomDarkTextSecondary,
                ),
                onPressed: () => Navigator.of(context).maybePop(),
              ),
            ],
          ),
        ),
        const Divider(height: 1, color: Color(0xFF1E1B33)),
      ],
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
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
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
        const Center(child: BloomMascot(size: 54, bob: true, pulseRing: true)),
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
          onChanged: (value) => setState(() => _query = value),
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
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(minHeight: 48),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 11,
                      ),
                      child: Align(
                        alignment: Alignment.centerLeft,
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
                ),
              ),
          ],
      ],
    );
  }
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({required this.msg, required this.isDark});

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
            const BloomMascot(size: 24, bob: false, pulseRing: false),
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
