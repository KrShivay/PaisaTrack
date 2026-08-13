## 2024-12-10 - Reusable interactive component pattern

**Learning:** When building custom interactive components like cards or rows, wrapping a `Container` with a `GestureDetector` lacks built-in material visual feedback (ripples) and standard a11y focus states for keyboard navigation.

**Action:** Prefer using a `Material` widget coupled with an `InkWell` instead of a `GestureDetector` with a decorated `Container`. This ensures built-in material ripples for visual tap feedback and standard a11y focus states for keyboard navigation.
