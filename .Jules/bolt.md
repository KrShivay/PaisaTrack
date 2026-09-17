## 2024-05-24 - Eager String Allocations in List Filters
**Learning:** The codebase has an anti-pattern of eagerly allocating multiple strings using `.toLowerCase()` before evaluating list search conditions, which causes unnecessary CPU overhead and memory allocation during list filtering.
**Action:** In Dart/Flutter list filters, prioritize lazy/short-circuit evaluation using `&&` and inline string checks (e.g., `item.property?.toLowerCase().contains(q) ?? false`) over upfront allocations.
