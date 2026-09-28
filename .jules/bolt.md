## 2024-09-28 - Lazy Evaluate Search Filters
**Learning:** Upfront string allocations across multiple fields during list filtering cause unnecessary CPU overhead and memory allocations.
**Action:** Use short-circuit evaluation (using `||`) and inline strings like `.toLowerCase().contains()` in Dart/Flutter list filters.
