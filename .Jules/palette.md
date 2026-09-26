## 2024-05-24 - Interactive Chip Accessibility
**Learning:** Custom interactive elements like filter chips using `GestureDetector` and `Container` lack built-in tap feedback and screen reader context.
**Action:** Wrap custom interactive elements in `Semantics(button: true, excludeSemantics: true, ...)` and use `Material` + `InkWell` to ensure visual ripple feedback and proper accessibility announcements.
