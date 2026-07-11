import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_tokens.dart';
import '../../core/theme/category_visuals.dart';
import '../../data/db/database.dart';
import '../../data/db/database_provider.dart';
import '../../data/repositories/category_repository.dart';

final categoryManagerListProvider =
    StreamProvider<List<Category>>((ref) async* {
  final database = await ref.watch(appDatabaseProvider.future);
  yield* ref.watch(categoryRepositoryProvider(database)).watchAll();
});

class CategoryManagerScreen extends ConsumerWidget {
  const CategoryManagerScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final categories = ref.watch(categoryManagerListProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Categories')),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _addCategory(context, ref),
        child: const Icon(Icons.add),
      ),
      body: categories.when(
        data: (rows) => ListView.separated(
          padding: AppSpacing.screen,
          itemBuilder: (context, index) {
            final category = rows[index];
            return ListTile(
              leading: CircleAvatar(
                backgroundColor:
                    CategoryVisuals.color(category.id).withValues(alpha: 0.15),
                child: Icon(
                  CategoryVisuals.icon(category.icon),
                  color: CategoryVisuals.color(category.id),
                ),
              ),
              title: Text(category.name),
              subtitle: Text(category.isUserCreated ? 'User category' : 'Seed'),
              trailing: Wrap(
                spacing: AppSpacing.xs,
                children: [
                  IconButton(
                    tooltip: category.isUserCreated ? 'Edit' : 'Rename',
                    onPressed: () => _renameCategory(context, ref, category),
                    icon: const Icon(Icons.edit),
                  ),
                  IconButton(
                    tooltip: 'Merge',
                    onPressed: () =>
                        _mergeCategory(context, ref, category, rows),
                    icon: const Icon(Icons.call_merge),
                  ),
                ],
              ),
            );
          },
          separatorBuilder: (context, index) => const Divider(height: 1),
          itemCount: rows.length,
        ),
        error: (error, stackTrace) => Center(
          child: Text('Could not load categories: $error'),
        ),
        loading: () => const Center(child: CircularProgressIndicator()),
      ),
    );
  }

  Future<CategoryRepository> _repository(WidgetRef ref) async {
    final database = await ref.read(appDatabaseProvider.future);
    return ref.read(categoryRepositoryProvider(database));
  }

  Future<void> _addCategory(BuildContext context, WidgetRef ref) async {
    final input = await _askCategory(context, title: 'Add category');
    if (input == null) return;
    await (await _repository(ref)).addUserCategory(
      name: input.name,
      icon: input.icon,
    );
  }

  Future<void> _renameCategory(
    BuildContext context,
    WidgetRef ref,
    Category category,
  ) async {
    final input = await _askCategory(
      context,
      title: category.isUserCreated ? 'Edit category' : 'Rename category',
      initialValue: category.name,
      initialIcon: category.icon,
      allowIconSelection: category.isUserCreated,
    );
    if (input == null) return;
    await (await _repository(ref)).renameCategory(
      categoryId: category.id,
      name: input.name,
      icon: category.isUserCreated ? input.icon : null,
    );
  }

  Future<void> _mergeCategory(
    BuildContext context,
    WidgetRef ref,
    Category source,
    List<Category> categories,
  ) async {
    final targets =
        categories.where((category) => category.id != source.id).toList();
    if (targets.isEmpty) return;

    final target = await showDialog<Category>(
      context: context,
      builder: (context) => SimpleDialog(
        title: Text('Merge ${source.name} into'),
        children: [
          for (final category in targets)
            SimpleDialogOption(
              onPressed: () => Navigator.of(context).pop(category),
              child: Text(category.name),
            ),
        ],
      ),
    );
    if (target == null) return;

    await (await _repository(ref)).mergeCategory(
      sourceCategoryId: source.id,
      targetCategoryId: target.id,
    );
  }

  Future<CategoryEditorResult?> _askCategory(
    BuildContext context, {
    required String title,
    String initialValue = '',
    String initialIcon = 'category',
    bool allowIconSelection = true,
  }) {
    return showDialog<CategoryEditorResult>(
      context: context,
      builder: (context) => CategoryEditorDialog(
        title: title,
        initialValue: initialValue,
        initialIcon: initialIcon,
        allowIconSelection: allowIconSelection,
      ),
    );
  }
}

class CategoryEditorResult {
  const CategoryEditorResult(this.name, this.icon);

  final String name;
  final String icon;
}

class CategoryEditorDialog extends StatefulWidget {
  const CategoryEditorDialog({
    super.key,
    required this.title,
    this.initialValue = '',
    this.initialIcon = 'category',
    this.allowIconSelection = true,
    this.onSave,
  });

  final String title;
  final String initialValue;
  final String initialIcon;
  final bool allowIconSelection;
  final ValueChanged<CategoryEditorResult>? onSave;

  @override
  State<CategoryEditorDialog> createState() => _CategoryEditorDialogState();
}

class _CategoryEditorDialogState extends State<CategoryEditorDialog> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initialValue,
  );
  late String _selectedIcon = widget.initialIcon;
  late bool _manuallySelected = widget.initialValue.isNotEmpty;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _save() {
    final result = CategoryEditorResult(_controller.text, _selectedIcon);
    if (widget.onSave case final onSave?) {
      onSave(result);
    } else {
      Navigator.of(context).pop(result);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _controller,
              autofocus: true,
              decoration: const InputDecoration(labelText: 'Name'),
              textCapitalization: TextCapitalization.words,
              onChanged: (value) {
                if (!widget.allowIconSelection || _manuallySelected) return;
                setState(
                  () => _selectedIcon = CategoryVisuals.suggestIcon(value),
                );
              },
              onSubmitted: (_) => _save(),
            ),
            if (widget.allowIconSelection) ...[
              const SizedBox(height: AppSpacing.lg),
              Text('Icon', style: Theme.of(context).textTheme.labelLarge),
              const SizedBox(height: AppSpacing.sm),
              SizedBox(
                height: 220,
                child: GridView.builder(
                  itemCount: CategoryVisuals.iconOptions.length,
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 5,
                    mainAxisSpacing: AppSpacing.sm,
                    crossAxisSpacing: AppSpacing.sm,
                  ),
                  itemBuilder: (context, index) {
                    final option = CategoryVisuals.iconOptions[index];
                    final selected = option.id == _selectedIcon;
                    return Tooltip(
                      message: option.label,
                      child: InkWell(
                        key: ValueKey('category_icon_${option.id}'),
                        borderRadius: BorderRadius.circular(AppRadius.md),
                        onTap: () => setState(() {
                          _selectedIcon = option.id;
                          _manuallySelected = true;
                        }),
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: selected
                                ? Theme.of(context).colorScheme.primaryContainer
                                : Theme.of(context)
                                    .colorScheme
                                    .surfaceContainer,
                            borderRadius: BorderRadius.circular(AppRadius.md),
                            border: Border.all(
                              color: selected
                                  ? Theme.of(context).colorScheme.primary
                                  : Theme.of(context)
                                      .colorScheme
                                      .outlineVariant,
                            ),
                          ),
                          child: Icon(option.icon),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _save, child: const Text('Save')),
      ],
    );
  }
}
