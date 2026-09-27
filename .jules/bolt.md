## 2024-05-18 - Lazy Evaluation for Text Searches
**Learning:** Eagerly generating lowercased text for many fields at once wastes memory and CPU overhead in list filtering functions.
**Action:** Always prefer lazy/short-circuit evaluation (using `||` and inline `.toLowerCase().contains()`) for string filtering to reduce CPU overhead and unnecessary allocations.
