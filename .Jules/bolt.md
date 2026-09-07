## 2026-09-07 - Optimize string allocations in list filters
**Learning:** In large list filters (like _filterItems in transactions_screen.dart), computing lowercase strings for every property upfront causes massive unnecessary memory allocations and CPU usage, especially when a search query only matches the first or second field.
**Action:** Always use short-circuit evaluation (e.g., `!field1.toLowerCase().contains(q) && !(field2?.toLowerCase().contains(q) ?? false)`) in filter methods. This avoids converting downstream fields if an upstream field already produces a match.
