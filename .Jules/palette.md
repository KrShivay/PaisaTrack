## 2024-11-20 - Visual Tap Feedback on Interactive Elements
**Learning:** Custom 'Add' buttons and 'Filter' chips built with `GestureDetector` and `Container` lack visual tap feedback and semantic labeling for screen readers.
**Action:** Always wrap interactive pills/buttons in `Semantics` (with `button: true`, `label`, and `excludeSemantics: true`) + `Material` (with `clipBehavior: Clip.antiAlias`) + `InkWell` to provide standard Material ripple effects and proper screen reader context.
