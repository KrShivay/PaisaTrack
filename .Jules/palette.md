## 2025-02-12 - Interactive Component Tap Feedback and Accessibility
**Learning:** Using `GestureDetector` coupled with a decorated `Container` for custom interactive components (like pills or chips) drops the material design ripple effect (tap feedback) and lacks standard accessibility focus states for keyboard navigation.
**Action:** Always prefer using a `Material` widget coupled with an `InkWell` for interactive UI elements. Apply `borderRadius` on both the `Material` (for clipping background color) and the `InkWell` (for conforming the ripple effect).
