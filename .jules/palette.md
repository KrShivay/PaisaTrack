## 2024-05-24 - Accessible Interactive Pills
**Learning:** When building interactive chips or pills in Flutter, wrapping an `InkWell` inside a `Semantics(excludeSemantics: true)` drops descendant semantics, requiring explicit redefinition of interactions (like `onTap` and `onTapHint`) directly on the `Semantics` node for screen readers to properly announce the button and action.
**Action:** Always wrap `Material`+`InkWell` pill combinations in explicitly redefined `Semantics` widgets to ensure a clean, single-element announcement with proper interaction hints.
