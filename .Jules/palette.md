## 2024-05-24 - Tap feedback and Focus states

**Learning:** Interactive cards built as wrapped Containers using `GestureDetector` lack native visual tap feedback and standard a11y focus states for keyboard navigation.
**Action:** When building custom interactive components like cards or rows, use a `Material` widget coupled with an `InkWell` (and `Padding`) instead of `GestureDetector` with a decorated `Container`. This ensures built-in material ripples and correct keyboard focus states.
