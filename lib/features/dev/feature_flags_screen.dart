import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/repositories/feature_flag_repository.dart';

/// Developer-only editor for persisted feature flags and thresholds.
class FeatureFlagsScreen extends ConsumerWidget {
  const FeatureFlagsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final flagsAsync = ref.watch(featureFlagsStreamProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Feature flags')),
      body: flagsAsync.when(
        data: (flags) => ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          children: [
            const Text(
              'Changes are stored locally and apply to the next operation. '
              'Reset a row to restore its built-in default.',
            ),
            const SizedBox(height: 12),
            for (final definition in featureFlagDefinitions)
              _FeatureFlagTile(
                definition: definition,
                flags: flags,
                onChanged: (value) => _setValue(ref, definition, value),
                onEdit: () => _editValue(context, ref, definition, flags),
                onReset: flags.isOverridden(definition)
                    ? () => _resetValue(ref, definition)
                    : null,
              ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: flags.overrides.isEmpty
                  ? null
                  : () => _resetAllWithConfirmation(context, ref),
              icon: const Icon(Icons.restart_alt),
              label: const Text('Reset all overrides'),
            ),
          ],
        ),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) =>
            Center(child: Text('Unable to load flags: $error')),
      ),
    );
  }

  static Future<void> _setValue(
    WidgetRef ref,
    FeatureFlagDefinition definition,
    String value,
  ) async {
    final repository = await ref.read(featureFlagRepositoryProvider.future);
    await repository.setValue(definition, value);
  }

  static Future<void> _resetValue(
    WidgetRef ref,
    FeatureFlagDefinition definition,
  ) async {
    final repository = await ref.read(featureFlagRepositoryProvider.future);
    await repository.resetFlag(definition.key);
  }

  static Future<void> _resetAll(WidgetRef ref) async {
    final repository = await ref.read(featureFlagRepositoryProvider.future);
    await repository.resetAllFlags();
  }

  static Future<void> _editValue(
    BuildContext context,
    WidgetRef ref,
    FeatureFlagDefinition definition,
    FeatureFlagsState flags,
  ) async {
    final value = await showDialog<String>(
      context: context,
      builder: (_) => _FlagValueDialog(
        definition: definition,
        initialValue: flags.valueFor(definition).toString(),
      ),
    );
    if (value == null || value.isEmpty) return;
    try {
      await _setValue(ref, definition, value);
    } on FormatException catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(error.message)),
        );
      }
    }
  }

  static Future<void> _resetAllWithConfirmation(
    BuildContext context,
    WidgetRef ref,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Reset feature flags?'),
        content: const Text('Restore every flag to its built-in default.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Reset'),
          ),
        ],
      ),
    );
    if (confirmed == true) await _resetAll(ref);
  }
}

class _FlagValueDialog extends StatefulWidget {
  const _FlagValueDialog({
    required this.definition,
    required this.initialValue,
  });

  final FeatureFlagDefinition definition;
  final String initialValue;

  @override
  State<_FlagValueDialog> createState() => _FlagValueDialogState();
}

class _FlagValueDialogState extends State<_FlagValueDialog> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.initialValue);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.definition.label),
      content: TextField(
        controller: _controller,
        autofocus: true,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: InputDecoration(helperText: widget.definition.description),
        onSubmitted: (value) => Navigator.of(context).pop(value.trim()),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_controller.text.trim()),
          child: const Text('Save'),
        ),
      ],
    );
  }
}

class _FeatureFlagTile extends StatelessWidget {
  const _FeatureFlagTile({
    required this.definition,
    required this.flags,
    required this.onChanged,
    required this.onEdit,
    required this.onReset,
  });

  final FeatureFlagDefinition definition;
  final FeatureFlagsState flags;
  final ValueChanged<String> onChanged;
  final VoidCallback onEdit;
  final VoidCallback? onReset;

  @override
  Widget build(BuildContext context) {
    final value = flags.valueFor(definition);
    final overridden = flags.isOverridden(definition);
    final subtitle = '${definition.description}\n'
        '${overridden ? 'Override' : 'Default'}: $value';

    if (definition.type == FeatureFlagValueType.boolean) {
      return SwitchListTile.adaptive(
        contentPadding: EdgeInsets.zero,
        title: Text(definition.label),
        subtitle: Text(subtitle),
        value: value as bool,
        onChanged: (next) => onChanged(next.toString()),
        secondary: onReset == null
            ? null
            : IconButton(
                tooltip: 'Reset ${definition.label}',
                onPressed: onReset,
                icon: const Icon(Icons.restart_alt),
              ),
      );
    }

    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(definition.label),
      subtitle: Text(subtitle),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(value.toString()),
          IconButton(
            tooltip: 'Edit ${definition.label}',
            onPressed: onEdit,
            icon: const Icon(Icons.edit_outlined),
          ),
          if (onReset != null)
            IconButton(
              tooltip: 'Reset ${definition.label}',
              onPressed: onReset,
              icon: const Icon(Icons.restart_alt),
            ),
        ],
      ),
      onTap: onEdit,
    );
  }
}
