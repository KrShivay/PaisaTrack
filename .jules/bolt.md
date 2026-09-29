## 2024-05-19 - Lazy Short-Circuit Evaluation for List Filters
**Learning:** In Dart/Flutter list filters (e.g., searching transactions), upfront string allocations across multiple fields (using `.toLowerCase()`) create unnecessary CPU overhead and memory allocations, especially when filtering long lists repeatedly (e.g., on every keystroke).
**Action:** Prioritize lazy/short-circuit evaluation (using `||` and inline string checks like `.toLowerCase().contains()`) so that processing stops on the first match and subsequent fields are not unnecessarily evaluated and allocated.
