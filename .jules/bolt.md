## 2024-10-07 - Lazy String Evaluation in List Filters
**Learning:** Unconditional upfront string allocations and `.toLowerCase()` operations in list filter predicates cause unnecessary CPU overhead and memory allocation for all fields, even if a match is found early.
**Action:** Prioritize lazy/short-circuit evaluation (using `&&` and inline strings like `.toLowerCase().contains()`) in list filters to avoid processing all fields when an early match is present.
