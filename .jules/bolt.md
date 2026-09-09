## 2024-09-09 - Lazy evaluation in list filtering
**Learning:** Upfront string allocations across multiple fields during list filtering cause significant CPU overhead and memory allocations.
**Action:** Prioritize lazy/short-circuit evaluation in Dart/Flutter list filters by chaining `.toLowerCase().contains()` with `&&` or `||` to prevent unnecessary allocations.