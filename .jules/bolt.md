## 2024-05-15 - Short-circuit evaluation in Dart List Filters
**Learning:** In Dart/Flutter list filters (e.g., searching transactions), evaluating all fields upfront by allocating a list, filtering nulls with `.whereType()`, and using `.any()` causes significant CPU overhead and memory allocations. A benchmark showed a 5x improvement in speed by avoiding these allocations.
**Action:** Prioritize lazy/short-circuit evaluation (using sequential `if` statements and null-aware operators) over upfront string allocations and array building to reduce overhead.
