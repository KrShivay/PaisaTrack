## 2024-05-13 - Add Semantics and Material InkWell to filter chips
**Learning:** Using `Semantics` with `excludeSemantics: true` allows for clean, single-element screen reader announcements for interactive pills, while `Material` and `InkWell` provide native ripple feedback.
**Action:** Always wrap interactive custom elements (like chips or pills) with `Semantics` for accessibility and `Material`/`InkWell` for native visual feedback.
