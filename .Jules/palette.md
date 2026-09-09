## 2024-06-12 - Accessible Nav Pill Icons

**Learning:** When creating custom navigation buttons or pills containing text and icons using `Material` and `InkWell`, standard semantics might announce multiple elements or miss state (selected). Wrapping the interactive elements in `Semantics` with `excludeSemantics: true` provides a clean, single-element announcement.
**Action:** Always wrap custom tab/nav components in `Semantics` with `excludeSemantics: true`, explicitly redefining `onTap`, `onTapHint`, `selected`, and `label` properties.
