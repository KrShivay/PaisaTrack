## 2024-03-24 - Hoist loop invariants and short-circuit early in UI filtering
**Learning:** `items.where` loops in Dart can easily hide O(n * M) property access/mutation if conditions are eagerly evaluated and local variables are allocated inside the loop. In `TransactionsScreen`, searching lowercased 10 fields per transaction eagerly instead of short-circuiting as soon as a match was found.
**Action:** Always check filter methods to extract variables invariant across the loop, and convert boolean cascades into early-return `if` conditions to minimize allocations.
