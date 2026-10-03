## 2025-02-23 - Optimizing filtering with short-circuit string allocations
**Learning:** Found an O(n) anti-pattern in list filtering logic where multiple fields unconditionally allocated new strings using `.toLowerCase()` inside a filter's `.where()` closure. Since all fields were checked at once, long lists caused noticeable lag during search.
**Action:** When filtering across multiple text fields, always hoist the search query's string allocations out of the loop and implement short-circuit field evaluations to avoid unconditional allocations.
