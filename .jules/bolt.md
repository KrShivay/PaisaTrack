## 2026-09-20 - Lazy Evaluation in List Filters
**Learning:** Upfront string allocation for multiple fields in list filters (e.g., `item.field.toLowerCase()`) causes unnecessary CPU overhead and memory allocation, especially when early fields might already match the search query.
**Action:** Prioritize lazy/short-circuit evaluation directly within the conditional check (`if (item.field.toLowerCase().contains(q))`) to prevent allocating strings for fields that are never checked if a previous field matches.
