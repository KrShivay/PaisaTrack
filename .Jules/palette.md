## 2024-05-24 - Accessibility improvements for navigation tabs
**Learning:** Using `GestureDetector` for navigation elements lacks standard tap feedback and isn't announced well by screen readers. Replacing it with `Semantics` (to clean up announcements by hiding internal icons and labels and providing a unified element) and `Material` + `InkWell` brings visual feedback (ripples) and built-in accessibility focus for keyboard navigation.
**Action:** Always prefer `Material` and `InkWell` wrapped in `Semantics` for custom interactive buttons/tabs rather than plain `GestureDetector`.
