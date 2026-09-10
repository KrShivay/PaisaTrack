## 2024-09-10 - Short-circuit Evaluation in List Filters
**Learning:** In Dart/Flutter, eagerly allocating strings (like calling `.toLowerCase()` on multiple fields of an object) before checking if a filter matches can cause unnecessary memory allocations and CPU overhead, especially when iterating over long lists.
**Action:** Use short-circuit evaluation (e.g., inline `field.toLowerCase().contains(query) || ...`) to stop allocations as soon as a match is found.
