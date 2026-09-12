## 2024-08-23 - Interactive component ripples
**Learning:** For custom interactive components like cards or rows, prefer using a `Material` widget coupled with an `InkWell` instead of a `GestureDetector` with a decorated `Container`. This ensures built-in material ripples for visual tap feedback and standard a11y focus states for keyboard navigation.
**Action:** Replace `GestureDetector` + `Container` patterns with `Material` + `InkWell` for tappable rows/cards where possible.
