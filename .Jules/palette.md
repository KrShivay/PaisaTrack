## 2026-08-25 - Tap affordances
**Learning:** Custom interactive components like buttons in toasts or notices built with `GestureDetector` miss out on standard visual tap feedback (ripples) and keyboard accessibility focus states.
**Action:** Use a `Material` widget coupled with an `InkWell` (and appropriate border radius) instead of `GestureDetector` for these micro-interactions to ensure built-in material ripples and standard a11y focus states.
