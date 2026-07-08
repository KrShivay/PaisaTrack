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
                    tooltip: 'Rename',
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
    final name = await _askName(context, title: 'Add category');
    if (name == null) return;
    await (await _repository(ref)).addUserCategory(name: name);
  }

  Future<void> _renameCategory(
    BuildContext context,
    WidgetRef ref,
    Category category,
  ) async {
    final name = await _askName(
      context,
      title: 'Rename category',
      initialValue: category.name,
    );
    if (name == null) return;
    await (await _repository(ref)).renameCategory(
      categoryId: category.id,
      name: name,
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

  Future<String?> _askName(
    BuildContext context, {
    required String title,
    String initialValue = '',
  }) {
    final controller = TextEditingController(text: initialValue);
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Name'),
          textCapitalization: TextCapitalization.words,
          onSubmitted: (_) => Navigator.of(context).pop(controller.text),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(controller.text),
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }
}
