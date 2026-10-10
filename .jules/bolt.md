## 2025-02-14 - List filter optimizations
**Learning:** Prioritizing lazy/short-circuit evaluation (e.g. early return with `.toLowerCase().contains()`) over upfront string allocations across multiple fields reduces CPU overhead and unnecessary memory allocations in transaction search filtering.
**Action:** When implementing list filters across multiple fields, use sequential short-circuited `if` statements instead of building an array of strings or mapping multiple strings upfront.
