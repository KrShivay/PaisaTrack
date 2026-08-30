## 2024-05-18 - Replacing GestureDetector with Material+InkWell

**Learning:** When building custom interactive elements like custom cards or filter chips, using `GestureDetector` coupled with a decorated `Container` prevents the element from automatically gaining proper standard visual feedback and accessible focus states for keyboard navigation.

**Action:** Prefer wrapping `InkWell` inside a `Material` widget for all custom interactive surfaces. Ensure styling (like background color and border radius) is applied to the `Material` to match the ripple effect, and adjust the inner `Padding` to preserve visual layout while providing native tap feedback and accessibility.
