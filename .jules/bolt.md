## 2026-09-21 - List Filtering Short-Circuiting Optimization
**Learning:** Dart list filtering using variables up front creates unneeded string allocations. By using short-circuit logical operators, we can skip processing fields if a prior condition is already met.
**Action:** Always favor inline `.toLowerCase().contains(q)` evaluations combined with `||` directly inside the filter expression instead of storing multiple strings beforehand.
