## 2024-05-15 - Home Navigation Pill Semantics
**Learning:** Custom navigation tabs with both icons and text produce redundant, cluttered screen reader announcements if not grouped. The standard `GestureDetector` also lacks visual tap feedback and keyboard focus styles that `InkWell` provides out-of-the-box.
**Action:** Wrap custom nav pills in a `Semantics` node with `excludeSemantics: true` to unify the label and state, and use `Material` + `InkWell` for built-in visual feedback and a11y focus states. Rebind `onTap` at the `Semantics` level to ensure actions remain accessible.
