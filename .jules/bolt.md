## 2024-05-19 - Debounce Search State

**Learning:** When text inputs trigger state updates (like `setState(() => query = val)`), typing rapidly can cause excessive widget rebuilds. This is particularly noticeable if the rebuild includes complex operations like filtering a large list of transactions.
**Action:** Implement a `Debouncer` class using `Timer` and wrap the `setState` calls in `onChanged` handlers to wait for a short delay (e.g., 300ms) before rebuilding the UI. Ensure `mounted` is checked before updating state in the timer callback, and verify that widget tests are updated to wait for the debounce duration.
