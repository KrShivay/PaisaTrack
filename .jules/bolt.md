## 2024-05-24 - Lazy evaluation in list filters
**Learning:** Pre-computing lowercase strings for all fields during a search filter operation creates unnecessary memory allocations and CPU overhead, especially on large lists.
**Action:** Prioritize lazy/short-circuit evaluation (using `&&` and inline strings like `.toLowerCase().contains()`) over upfront string allocations across multiple fields in list filters.
