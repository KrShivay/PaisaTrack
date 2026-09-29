## 2024-05-15 - Add Material Ripple and Focus to Transaction Rows
**Learning:** Using `GestureDetector` with a `Container` for interactive rows lacks visual feedback and standard a11y focus states for keyboard navigation.
**Action:** Always prefer wrapping interactive elements in `Material` and `InkWell`, moving the background color to `Material` and inner padding to `Padding` inside the `InkWell`. Ensure `borderRadius` is set on both `Material` and `InkWell` to clip ripples correctly.
