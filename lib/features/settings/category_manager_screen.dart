import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_tokens.dart';
import '../../core/widgets/bloom/bloom.dart';
import '../../core/theme/category_visuals.dart';
import '../../data/db/database.dart';
import '../../data/db/database_provider.dart';
import '../../data/repositories/category_repository.dart';

final categoryManagerListProvider =
    StreamProvider<List<Category>>((ref) async* {
  final database = await ref.watch(appDatabaseProvider.future);
  yield* ref.watch(categoryRepositoryProvider(database)).watchAll();
});

class CategoryManagerScreen extends ConsumerStatefulWidget {
  const CategoryManagerScreen({super.key});

  @override
  ConsumerState<CategoryManagerScreen> createState() =>
      _CategoryManagerScreenState();
}

enum _CategoryFilter { all, defaults, custom }

class _CategoryManagerScreenState extends ConsumerState<CategoryManagerScreen> {
  final _searchController = TextEditingController();
  _CategoryFilter _filter = _CategoryFilter.all;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final categories = ref.watch(categoryManagerListProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Categories')),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _addCategory(context, ref),
        tooltip: 'Add category',
        child: const Icon(Icons.add),
      ),
      body: categories.when(
        data: (rows) {
          final query = _searchController.text.trim().toLowerCase();
          final byId = {for (final category in rows) category.id: category};
          final visible = _hierarchicalRows(rows).where((category) {
            final parentName =
                byId[category.parentId]?.name.toLowerCase() ?? '';
            if (query.isNotEmpty &&
                !category.name.toLowerCase().contains(query) &&
                !parentName.contains(query)) {
              return false;
            }
            return switch (_filter) {
              _CategoryFilter.all => true,
              _CategoryFilter.defaults => !category.isUserCreated,
              _CategoryFilter.custom => category.isUserCreated,
            };
          }).toList();
          return ListView.separated(
            padding: EdgeInsets.fromLTRB(
              AppSpacing.screen.left,
              AppSpacing.screen.top,
              AppSpacing.screen.right,
              AppSpacing.screen.bottom + 72,
            ),
            itemBuilder: (context, index) {
              if (index == 0) {
                return Column(
                  children: [
                    TextField(
                      controller: _searchController,
                      onChanged: (_) => setState(() {}),
                      decoration: const InputDecoration(
                        hintText: 'Search categories',
                        prefixIcon: Icon(Icons.search),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    SegmentedButton<_CategoryFilter>(
                      segments: const [
                        ButtonSegment(
                          value: _CategoryFilter.all,
                          label: Text('All'),
                        ),
                        ButtonSegment(
                          value: _CategoryFilter.defaults,
                          label: Text('Default'),
                        ),
                        ButtonSegment(
                          value: _CategoryFilter.custom,
                          label: Text('Created'),
                        ),
                      ],
                      selected: {_filter},
                      onSelectionChanged: (value) =>
                          setState(() => _filter = value.single),
                    ),
                  ],
                );
              }
              final category = visible[index - 1];
              final parent = byId[category.parentId];
              return ListTile(
                contentPadding: EdgeInsets.only(
                  left: parent == null ? 0 : AppSpacing.lg,
                ),
                leading: CircleAvatar(
                  backgroundColor: CategoryVisuals.color(category.id)
                      .withValues(alpha: 0.15),
                  child: Icon(
                    CategoryVisuals.icon(category.icon),
                    color: CategoryVisuals.color(category.id),
                  ),
                ),
                title: Text(category.name),
                subtitle: Text(
                  [
                    if (parent != null) 'Subcategory of ${parent.name}',
                    category.isUserCreated
                        ? 'Created by you'
                        : 'Default category',
                    category.isSpending ? 'Spending' : 'Excluded',
                  ].join(' · '),
                ),
                onTap: () => _renameCategory(context, ref, category, rows),
                trailing: PopupMenuButton<_CategoryAction>(
                  tooltip: 'Actions for ${category.name}',
                  onSelected: (action) {
                    switch (action) {
                      case _CategoryAction.edit:
                        _renameCategory(context, ref, category, rows);
                      case _CategoryAction.merge:
                        _mergeCategory(context, ref, category, rows);
                    }
                  },
                  itemBuilder: (context) => const [
                    PopupMenuItem(
                      value: _CategoryAction.edit,
                      child: Text('Edit'),
                    ),
                    PopupMenuItem(
                      value: _CategoryAction.merge,
                      child: Text('Merge'),
                    ),
                  ],
                ),
              );
            },
            separatorBuilder: (context, index) => const Divider(height: 1),
            itemCount: visible.length + 1,
          );
        },
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

  List<Category> _hierarchicalRows(List<Category> categories) {
    final ids = categories.map((category) => category.id).toSet();
    final children = <String, List<Category>>{};
    final roots = <Category>[];
    for (final category in categories) {
      final parentId = category.parentId;
      if (parentId == null || !ids.contains(parentId)) {
        roots.add(category);
      } else {
        children.putIfAbsent(parentId, () => []).add(category);
      }
    }
    return [
      for (final root in roots) ...[
        root,
        ...?children[root.id],
      ],
    ];
  }

  Future<void> _addCategory(BuildContext context, WidgetRef ref) async {
    final categories = await ref.read(categoryManagerListProvider.future);
    if (!context.mounted) return;
    final input = await _askCategory(
      context,
      title: 'Create category',
      parentCategories:
          categories.where((category) => category.parentId == null).toList(),
      existingNames: categories.map((category) => category.name).toSet(),
    );
    if (input == null) return;
    await (await _repository(ref)).addUserCategory(
      name: input.name,
      icon: input.icon,
      isSpending: input.type == CategoryType.spending,
      parentId: input.parentId,
    );
  }

  Future<void> _renameCategory(
    BuildContext context,
    WidgetRef ref,
    Category category,
    List<Category> categories,
  ) async {
    final input = await _askCategory(
      context,
      title: category.isUserCreated ? 'Edit category' : 'Rename category',
      initialValue: category.name,
      initialIcon: category.icon,
      allowIconSelection: category.isUserCreated,
      allowParentSelection: category.isUserCreated,
      initialParentId: category.parentId,
      parentCategories: categories
          .where(
            (candidate) =>
                candidate.parentId == null && candidate.id != category.id,
          )
          .toList(),
      initialType:
          category.isSpending ? CategoryType.spending : CategoryType.transfer,
      existingNames: categories
          .where((candidate) => candidate.id != category.id)
          .map((candidate) => candidate.name)
          .toSet(),
    );
    if (input == null) return;
    await (await _repository(ref)).renameCategory(
      categoryId: category.id,
      name: input.name,
      icon: category.isUserCreated ? input.icon : null,
      isSpending:
          category.isUserCreated ? input.type == CategoryType.spending : null,
      parentId: input.parentId,
      updateParent: category.isUserCreated,
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

    final target = await showBloomDialog<Category>(
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
    if (target == null || !context.mounted) return;

    final confirmed = await showBloomDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Merge ${source.name} into ${target.name}?'),
        content: Text(
          'All historical transactions, subcategories, and rules assigned to "${source.name}" '
          'will be re-parented and moved to "${target.name}".\n\n"${source.name}" will be deleted. '
          'This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Merge'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;

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
    bool allowParentSelection = true,
    String? initialParentId,
    List<Category> parentCategories = const [],
    CategoryType initialType = CategoryType.spending,
    Set<String> existingNames = const {},
  }) {
    return showModalBottomSheet<CategoryEditorResult>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => CategoryEditorDialog(
        title: title,
        initialValue: initialValue,
        initialIcon: initialIcon,
        allowIconSelection: allowIconSelection,
        allowParentSelection: allowParentSelection,
        initialParentId: initialParentId,
        parentCategories: parentCategories,
        initialType: initialType,
        existingNames: existingNames,
      ),
    );
  }
}

enum _CategoryAction { edit, merge }

enum CategoryType { spending, income, transfer }

class CategoryEditorResult {
  const CategoryEditorResult(
    this.name,
    this.icon, {
    this.type = CategoryType.spending,
    this.parentId,
  });

  final String name;
  final String icon;
  final CategoryType type;
  final String? parentId;
}

class CategoryEditorDialog extends StatefulWidget {
  const CategoryEditorDialog({
    super.key,
    required this.title,
    this.initialValue = '',
    this.initialIcon = 'category',
    this.allowIconSelection = true,
    this.allowParentSelection = true,
    this.initialParentId,
    this.parentCategories = const [],
    this.initialType = CategoryType.spending,
    this.existingNames = const {},
    this.onSave,
  });

  final String title;
  final String initialValue;
  final String initialIcon;
  final bool allowIconSelection;
  final bool allowParentSelection;
  final String? initialParentId;
  final List<Category> parentCategories;
  final CategoryType initialType;
  final Set<String> existingNames;
  final ValueChanged<CategoryEditorResult>? onSave;

  @override
  State<CategoryEditorDialog> createState() => _CategoryEditorDialogState();
}

class _CategoryEditorDialogState extends State<CategoryEditorDialog> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initialValue,
  );
  final _iconSearchController = TextEditingController();
  late String _selectedIcon = widget.initialIcon;
  late bool _manuallySelected = widget.initialValue.isNotEmpty;
  late CategoryType _type = widget.initialType;
  late String? _parentId = widget.initialParentId;
  String? _errorText;

  @override
  void dispose() {
    _controller.dispose();
    _iconSearchController.dispose();
    super.dispose();
  }

  void _save() {
    final name = _controller.text.trim();
    if (name.isEmpty) {
      setState(() => _errorText = 'Enter a category name');
      return;
    }
    final duplicate = widget.existingNames.any(
      (existing) => existing.trim().toLowerCase() == name.toLowerCase(),
    );
    if (duplicate) {
      setState(() => _errorText = 'A category with this name already exists');
      return;
    }
    final result = CategoryEditorResult(
      name,
      _selectedIcon,
      type: _type,
      parentId: _parentId,
    );
    if (widget.onSave case final onSave?) {
      onSave(result);
    } else {
      Navigator.of(context).pop(result);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final iconQuery = _iconSearchController.text.trim().toLowerCase();
    final iconOptions = CategoryVisuals.iconOptions
        .where(
          (option) =>
              iconQuery.isEmpty ||
              option.label.toLowerCase().contains(iconQuery) ||
              option.id.toLowerCase().contains(iconQuery),
        )
        .toList();
    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          AppSpacing.screen.left,
          AppSpacing.sm,
          AppSpacing.screen.right,
          MediaQuery.viewInsetsOf(context).bottom + AppSpacing.screen.bottom,
        ),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(widget.title, style: theme.textTheme.headlineSmall),
              const SizedBox(height: AppSpacing.lg),
              Center(
                child: CircleAvatar(
                  radius: 28,
                  backgroundColor: theme.colorScheme.primaryContainer,
                  child: Icon(
                    CategoryVisuals.icon(_selectedIcon),
                    color: theme.colorScheme.onPrimaryContainer,
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              TextField(
                controller: _controller,
                autofocus: true,
                decoration: InputDecoration(
                  labelText: 'Name',
                  errorText: _errorText,
                ),
                textCapitalization: TextCapitalization.words,
                onChanged: (value) {
                  if (!widget.allowIconSelection || _manuallySelected) return;
                  setState(
                    () {
                      _errorText = null;
                      _selectedIcon = CategoryVisuals.suggestIcon(value);
                    },
                  );
                },
                onSubmitted: (_) => _save(),
              ),
              if (widget.allowParentSelection &&
                  widget.parentCategories.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.lg),
                DropdownButtonFormField<String>(
                  initialValue: _parentId ?? '',
                  decoration: const InputDecoration(
                    labelText: 'Subcategory of',
                    helperText: 'Optional — leave as Top-level category',
                  ),
                  items: [
                    const DropdownMenuItem(
                      value: '',
                      child: Text('Top-level category'),
                    ),
                    for (final category in widget.parentCategories)
                      DropdownMenuItem(
                        value: category.id,
                        child: Text(category.name),
                      ),
                  ],
                  onChanged: (value) => setState(
                    () => _parentId =
                        value == null || value.isEmpty ? null : value,
                  ),
                ),
              ],
              if (widget.allowIconSelection) ...[
                const SizedBox(height: AppSpacing.lg),
                Text('Choose icon', style: theme.textTheme.titleMedium),
                const SizedBox(height: AppSpacing.sm),
                TextField(
                  controller: _iconSearchController,
                  decoration: const InputDecoration(
                    hintText: 'Search icons',
                    prefixIcon: Icon(Icons.search),
                  ),
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: AppSpacing.sm),
                SizedBox(
                  height: 240,
                  child: GridView.builder(
                    itemCount: iconOptions.length,
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 5,
                      mainAxisSpacing: AppSpacing.sm,
                      crossAxisSpacing: AppSpacing.sm,
                    ),
                    itemBuilder: (context, index) {
                      final option = iconOptions[index];
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
                                  ? Theme.of(context)
                                      .colorScheme
                                      .primaryContainer
                                  : Theme.of(context)
                                      .colorScheme
                                      .surfaceContainer,
                              borderRadius: BorderRadius.circular(AppRadius.md),
                            ),
                            child: Icon(option.icon),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
              const SizedBox(height: AppSpacing.lg),
              Text('Category type', style: theme.textTheme.titleMedium),
              RadioGroup<CategoryType>(
                groupValue: _type,
                onChanged: (value) => setState(() => _type = value!),
                child: const Column(
                  children: [
                    RadioListTile(
                      contentPadding: EdgeInsets.zero,
                      value: CategoryType.spending,
                      title: Text('Spending'),
                    ),
                    RadioListTile(
                      contentPadding: EdgeInsets.zero,
                      value: CategoryType.income,
                      title: Text('Income'),
                    ),
                    RadioListTile(
                      contentPadding: EdgeInsets.zero,
                      value: CategoryType.transfer,
                      title: Text('Transfer / excluded'),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _save,
                  child: Text(
                    widget.initialValue.isEmpty ? 'Create category' : 'Save',
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
