## 2025-01-24 - Interactive Tab Button Accessibility
**Learning:** Using `GestureDetector` for tab buttons lacks built-in material ripple and proper semantic feedback, resulting in a poor screen reader experience where inner nodes might be announced separately.
**Action:** Replace `GestureDetector` with `Semantics` > `Material` > `InkWell`. Define `excludeSemantics: true` on the `Semantics` widget to drop descendant semantics, and explicitly set properties like `button`, `selected`, `label`, `onTap`, and `onTapHint` to create a clean, single-element announcement.
