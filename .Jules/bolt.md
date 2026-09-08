## 2026-09-08 - Optimize list filtering with short-circuit evaluation
**Learning:** Upfront string transformations (like `toLowerCase()`) on all object fields during list filtering cause unnecessary memory allocations and CPU overhead.
**Action:** Use short-circuit evaluation (`||` or `&&` with inline `toLowerCase().contains()`) to lazily evaluate fields and prevent unnecessary allocations.
