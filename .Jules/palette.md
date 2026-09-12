
## 2024-08-16 - InkWell for Material visual tap feedback
**Learning:** For interactive UI elements (like transaction rows), it's important to use `Material` with `InkWell` instead of just a raw `GestureDetector` in a decorated `Container`. This provides a built-in visual ripple effect for user feedback, making the app feel more responsive and native.
**Action:** Replace `GestureDetector` with `InkWell` inside a `Material` widget for tap targets like custom cards, list items, and rows, while ensuring proper `clipBehavior` and `color` on the `Material`.
