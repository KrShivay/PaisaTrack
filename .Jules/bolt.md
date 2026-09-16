## 2024-05-14 - String Allocation in List Filters
**Learning:** In Dart/Flutter list filters (e.g., searching transactions), evaluating strings upfront via `.toLowerCase()` and variables creates a significant number of short-lived string allocations, especially across large sets.
**Action:** Prioritize lazy/short-circuit evaluation (using `&&` and inline strings like `.toLowerCase().contains()`) over upfront string allocations across multiple fields to reduce CPU overhead and unnecessary memory allocations.
