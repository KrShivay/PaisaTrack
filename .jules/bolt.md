## 2024-09-26 - Short-circuit string allocations in list filters
**Learning:** In list filters (e.g. searching transactions), allocating lowercase strings for all searchable fields per row causes unnecessary memory churn. Upfront `.toLowerCase()` allocation across 10 fields when a match could occur on the very first field leads to frame drops during rapid typing on large lists.
**Action:** Use inline strings like `?.toLowerCase().contains()` joined with `&&` for short-circuit evaluation to skip processing remaining fields once a match is found or discarded.
