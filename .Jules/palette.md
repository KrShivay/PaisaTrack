## 2025-02-28 - Material InkWell for Interactive Rows
**Learning:** Using `GestureDetector` with a decorated `Container` for interactive rows (like transactions) prevents standard accessibility focus states and built-in visual feedback (ripple effect) which degrades the experience for keyboard navigators and touch users.
**Action:** Always prefer wrapping interactive rows in a `Material` widget combined with an `InkWell`. Ensure `borderRadius` is applied to both the `Material` widget and the `InkWell` to maintain shape boundaries.
