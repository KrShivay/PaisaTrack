## 2024-11-20 - Debouncing text fields
**Learning:** Reacting to `onChange` events in text fields such as `TextField` in Flutter by triggering a state change (`setState` in a `StatefulWidget` or using Riverpod) without debouncing can result in performance issues, especially when the state change triggers expensive computations like list filtering.
**Action:** Always wrap text field changes that trigger filtering or other expensive logic in a debounce mechanism. A simple approach uses `dart:async`'s `Timer`.
