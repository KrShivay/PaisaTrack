## 2026-08-14 - Use Material+InkWell for Interactive Rows
**Learning:** Custom interactive components like transaction rows in this app's design system need built-in material ripples for visual tap feedback and standard a11y focus states for keyboard navigation. A simple `GestureDetector` inside a decorated `Container` does not provide this.
**Action:** Replace `GestureDetector` + `Container` with `Material` + `InkWell` on interactive lists and cards across the codebase to improve accessibility and interaction feedback.
