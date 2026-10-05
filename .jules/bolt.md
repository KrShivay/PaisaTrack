## 2024-10-05 - Lazy Evaluation in List Filters
**Learning:** In Dart, filtering large lists by pre-allocating multiple normalized strings per item (e.g., `item.field.toLowerCase()`) creates significant memory churn and CPU overhead if only a few fields are typically queried.
**Action:** Always prioritize lazy/short-circuit evaluation (e.g., `item.field.toLowerCase().contains(q) || ...`) in search filters. This prevents unnecessary string allocations and reduces GC pressure since evaluation stops at the first match.
