## 2024-10-04 - Optimize List Filtering with Short-Circuiting
**Learning:** In Flutter/Dart list filters, such as searching transactions, prioritizing lazy/short-circuit evaluation with inline `.toLowerCase().contains()` over upfront string allocations across multiple fields significantly reduces CPU overhead and unnecessary memory allocations.
**Action:** When filtering lists by multiple fields, avoid allocating variables for all fields upfront; instead, chain conditions logically to allow early exit.
