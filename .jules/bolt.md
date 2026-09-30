## 2024-05-24 - Upfront String Allocation in List Filtering
**Learning:** In Dart/Flutter list filters (e.g., searching transactions), upfront string allocations across multiple fields (`final name = item.displayName.toLowerCase(); ...`) causes heavy GC churn and CPU overhead on long lists.
**Action:** Prioritize lazy/short-circuit evaluation (using `||` and inline strings like `.toLowerCase().contains()`) to reduce unnecessary memory allocations.
