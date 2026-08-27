## 2024-08-27 - [Optimize .toLowerCase() in loops and iterators]
**Learning:** Found multiple instances where `.toLowerCase()` is repeatedly called inside iterators/loops for string searching algorithms resulting in unnecessary object allocations and time spent.
**Action:** Lift `.toLowerCase()` calls on variables that don't change out of the loops, and only evaluate properties that might match. This reduces GC overhead and makes O(n) filter loops faster on large lists (like transactions and categories).
