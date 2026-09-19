## 2024-05-24 - Dart string allocations in list filtering
**Learning:** Upfront `.toLowerCase()` and string allocations on multiple properties within list filters lead to unnecessary overhead, as the filter might return early if it's evaluated sequentially.
**Action:** Prioritize lazy/short-circuit evaluation in Dart/Flutter list filters by chaining `.toLowerCase().contains()` sequentially with `||` or `&&` instead of upfront string allocations.
