## 2024-03-24 - Interactive Row Accessibility
**Learning:** In Flutter, wrapping rows using `GestureDetector` and `Container` for interactivity lacks visual feedback and standard keyboard navigation support, leading to a poorer accessibility experience.
**Action:** Always prefer wrapping interactive rows in a `Material` widget coupled with an `InkWell` to provide built-in material ripples for visual tap feedback and standard a11y focus states for keyboard navigation.
