import 'package:flutter/material.dart';

import '../../data/db/database.dart' show Category;
import '../theme/app_tokens.dart';
import '../theme/category_visuals.dart';

class CategoryPickerSheet extends StatefulWidget {
  const CategoryPickerSheet({
    super.key,
    required this.categories,
    this.currentCategoryId,
    this.title = 'Choose category',
    this.suggestedCategoryIds = const [],
    this.recentCategoryIds = const [],
    this.explanations = const {},
  });

  final List<Category> categories;
  final String? currentCategoryId;
  final String title;
  final List<String> suggestedCategoryIds;
  final List<String> recentCategoryIds;
  final Map<String, String> explanations;

  @override
  State<CategoryPickerSheet> createState() => _CategoryPickerSheetState();
}

class _CategoryPickerSheetState extends State<CategoryPickerSheet> {
  final _searchController = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final insets = MediaQuery.viewInsetsOf(context);
    final byId = {
      for (final category in widget.categories) category.id: category,
    };
    final q = _query.trim().toLowerCase();
    final filtered = _hierarchicalCategories(widget.categories).where((
      category,
    ) {
      final parentName = byId[category.parentId]?.name.toLowerCase();
      return q.isEmpty ||
          category.name.toLowerCase().contains(q) ||
          (parentName?.contains(q) ?? false);
    }).toList(growable: false);
    final suggested = _idsToCategories(widget.suggestedCategoryIds, byId);
    final recent = _idsToCategories(widget.recentCategoryIds, byId);

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          AppSpacing.lg,
          0,
          AppSpacing.lg,
          insets.bottom + AppSpacing.lg,
        ),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 640),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                widget.title,
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: AppSpacing.md),
              TextField(
                controller: _searchController,
                autofocus: true,
                textInputAction: TextInputAction.search,
                decoration: InputDecoration(
                  hintText: 'Search categories',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: _query.isEmpty
                      ? null
                      : IconButton(
                          tooltip: 'Clear category search',
                          icon: const Icon(Icons.close),
                          onPressed: () {
                            _searchController.clear();
                            setState(() => _query = '');
                          },
                        ),
                ),
                onChanged: (value) => setState(() => _query = value),
              ),
              const SizedBox(height: AppSpacing.md),
              Expanded(
                child: ListView(
                  children: [
                    if (_query.trim().isEmpty && suggested.isNotEmpty) ...[
                      const _SectionLabel('Suggested'),
                      Wrap(
                        spacing: AppSpacing.sm,
                        runSpacing: AppSpacing.sm,
                        children: [
                          for (final category in suggested)
                            _CategoryChip(
                              category: category,
                              parentName: byId[category.parentId]?.name,
                              selected: category.id == widget.currentCategoryId,
                              onTap: () => Navigator.of(context).pop(category),
                            ),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.lg),
                    ],
                    if (_query.trim().isEmpty && recent.isNotEmpty) ...[
                      const _SectionLabel('Recent'),
                      for (final category in recent)
                        _CategoryRow(
                          category: category,
                          parentName: byId[category.parentId]?.name,
                          selected: category.id == widget.currentCategoryId,
                          explanation: widget.explanations[category.id],
                        ),
                      const SizedBox(height: AppSpacing.md),
                    ],
                    _SectionLabel(
                      _query.trim().isEmpty ? 'All categories' : 'Matches',
                    ),
                    if (filtered.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          vertical: AppSpacing.lg,
                        ),
                        child: Text(
                          'No categories match your search.',
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                      )
                    else
                      for (final category in filtered)
                        _CategoryRow(
                          category: category,
                          parentName: byId[category.parentId]?.name,
                          selected: category.id == widget.currentCategoryId,
                          explanation: widget.explanations[category.id],
                        ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<Category> _idsToCategories(
    List<String> ids,
    Map<String, Category> byId,
  ) {
    final seen = <String>{};
    return [
      for (final id in ids)
        if (seen.add(id) && byId[id] != null) byId[id]!,
    ];
  }

  List<Category> _hierarchicalCategories(List<Category> categories) {
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
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Text(
        label.toUpperCase(),
        style: Theme.of(context).textTheme.labelMedium,
      ),
    );
  }
}

class _CategoryChip extends StatelessWidget {
  const _CategoryChip({
    required this.category,
    this.parentName,
    required this.selected,
    required this.onTap,
  });

  final Category category;
  final String? parentName;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return FilterChip(
      selected: selected,
      avatar: Icon(CategoryVisuals.icon(category.icon), size: 18),
      label: Text(
        parentName == null ? category.name : '$parentName › ${category.name}',
      ),
      onSelected: (_) => onTap(),
    );
  }
}

class _CategoryRow extends StatelessWidget {
  const _CategoryRow({
    required this.category,
    this.parentName,
    required this.selected,
    this.explanation,
  });

  final Category category;
  final String? parentName;
  final bool selected;
  final String? explanation;

  @override
  Widget build(BuildContext context) {
    final color = CategoryVisuals.color(category.id);
    final subtitle = [
      if (parentName case final parent?) 'Subcategory of $parent',
      if (explanation case final detail?) detail,
    ].join(' · ');
    return ListTile(
      minVerticalPadding: AppSpacing.sm,
      contentPadding: EdgeInsets.only(left: parentName == null ? 0 : 20),
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.15),
          shape: BoxShape.circle,
        ),
        child: Icon(
          CategoryVisuals.icon(category.icon),
          size: 20,
          color: color,
        ),
      ),
      title: Text(category.name),
      subtitle: subtitle.isEmpty ? null : Text(subtitle),
      trailing: selected ? const Icon(Icons.check_circle) : null,
      onTap: () => Navigator.of(context).pop(category),
    );
  }
}
