
## 2024-09-24 - Dart String Allocation Overhead in List Filtering
**Learning:** In Dart/Flutter list filters (e.g., searching transactions), evaluating all fields across multiple items upfront creates significant unnecessary memory overhead due to string allocations, slowing down performance.
**Action:** Prioritize lazy/short-circuit evaluation (using `&&` or `||` and inline strings like `.toLowerCase().contains()`) over upfront string allocations across multiple fields to reduce CPU overhead and unnecessary memory allocations.
