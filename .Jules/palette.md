
## 2026-08-26 - Navigation Button Semantics
**Learning:** When building custom bottom navigation tabs or floating action buttons using `GestureDetector` that contain both icons and text, they announce poorly to screen readers by default (reading out parts separately).
**Action:** Always wrap such `GestureDetector` composite buttons in a `Semantics` widget with `button: true`, the correct `label`, and crucially, `excludeSemantics: true` to suppress the noisy internal elements and provide a single clean announcement.
