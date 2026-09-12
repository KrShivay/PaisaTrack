## 2024-05-18 - Improve accessibility and visual feedback for list items
**Learning:** `GestureDetector` coupled with `Container` does not offer accessibility keyboard focus states or visual tap feedback, leaving list items feeling disconnected and hindering navigation for keyboard users.
**Action:** When building interactive components like rows or cards, prefer using a `Material` widget coupled with an `InkWell` to ensure built-in Material ripples for visual tap feedback and standard a11y focus states for keyboard navigation.
