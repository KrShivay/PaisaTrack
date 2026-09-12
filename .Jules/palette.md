## 2026-08-15 - Use Material and InkWell for interactive rows
**Learning:** For interactive rows and cards, using `GestureDetector` with a decorated `Container` lacks visual tap feedback (ripple) and proper accessibility focus states.
**Action:** Prefer wrapping components in a `Material` widget coupled with an `InkWell` to ensure built-in material ripples for visual tap feedback and standard a11y focus states for keyboard navigation.
