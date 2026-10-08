## 2024-10-08 - Lazy Evaluation for Filters
**Learning:** In Dart/Flutter list filters (e.g., searching transactions), prioritize lazy/short-circuit evaluation (using `&&` and inline strings like `.toLowerCase().contains()`) over upfront string allocations across multiple fields to reduce CPU overhead and unnecessary memory allocations.
**Action:** Always refactor upfront eager evaluations into short-circuited lazy evaluations.
