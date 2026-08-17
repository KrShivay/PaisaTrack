## 2026-08-17 - Interactive Components Tap Feedback
**Learning:** When building custom interactive components like cards or rows, using a `GestureDetector` coupled with a decorated `Container` lacks standard a11y focus states and visual tap feedback (ripples).
**Action:** Use a `Material` widget with a specified color and `borderRadius` instead, containing an `InkWell` (which handles the tap and ripple), and finally wrapping the inner content with `Padding`.
