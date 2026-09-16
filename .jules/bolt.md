## 2024-05-24 - Optimize list filtering by replacing upfront string list allocations with short-circuit evaluation
**Learning:** In Dart/Flutter list filters (e.g., searching transactions), creating an upfront list of strings for search fields causes unnecessary memory allocations and CPU overhead, especially for large lists.
**Action:** Use short-circuit evaluation with `&&` or multiple `if` statements and inline `.toLowerCase().contains()` checks to allow early exits without evaluating all fields.
