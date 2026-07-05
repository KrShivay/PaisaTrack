# Seed Assets

Phase 0 ships seed data and the Drift loader for bundled categories.

- `assets/seed/categories.json` mirrors the default category taxonomy in
  PLAN.md section 5.
- `assets/seed/category_seed.json` is a starter merchant-to-category map used by
  the future categorizer ladder. It is intentionally small and should grow over
  time from sanitized fixtures, user feedback, and reviewed aliases.

`AppDatabase.seedDefaultCategories()` loads `categories.json` into the
`categories` table with insert-or-ignore semantics. It is safe to run at startup:
reruns do not create duplicate rows and do not overwrite user-edited category
names or icons.
