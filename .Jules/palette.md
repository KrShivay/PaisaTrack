## 2024-09-14 - Accessible Filter Pills
**Learning:** Custom interactive elements like filter pills using `GestureDetector` lack built-in accessibility semantics and visual tap feedback (ripple).
**Action:** Always wrap interactive pills/buttons in a `Semantics` widget, and use `Material` + `InkWell` instead of `GestureDetector` + `Container` for proper a11y focus states and material ripples. Note that `Semantics` needs `excludeSemantics: true` when overriding descendant behavior, meaning `onTap` and `onTapHint` must be explicitly redefined on the `Semantics` node.
