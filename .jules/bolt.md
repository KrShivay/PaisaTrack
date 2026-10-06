## 2024-10-25 - Avoid Upfront Allocations in List Filtering
**Learning:** In Dart/Flutter list filters (e.g., searching transactions), evaluating all fields upfront and placing them in an array before filtering (e.g., using `[field1, field2].any()`) creates a significant performance bottleneck due to unnecessary list allocations and string conversions (`toStringAsFixed`).
**Action:** Prioritize lazy/short-circuit evaluation using early returns (`if (condition) return true;`) to reduce CPU overhead and memory allocations when scanning large lists.
