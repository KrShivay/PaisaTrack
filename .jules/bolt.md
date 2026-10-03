## 2024-10-03 - Lazy evaluation in list filters
**Learning:** In Dart/Flutter, aggressively allocating strings in list filters (e.g. searching via `.toLowerCase()`) across multiple fields upfront before evaluating conditions causes unnecessary CPU overhead and garbage collection.
**Action:** Use short-circuit evaluation directly inside `if` statements to skip expensive string allocations as soon as a match is found.
