## 2024-05-18 - Avoid Upfront Array Allocation in List Filters
**Learning:** In Dart/Flutter, building a list of strings and using `.any()` for search filtering creates unnecessary memory allocations and blocks early returns.
**Action:** Prioritize lazy/short-circuit evaluation (sequential `if` checks) over upfront list allocation when filtering large lists to reduce CPU and memory overhead.
