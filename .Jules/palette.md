## 2024-05-23 - Interactive component ripples and accessibility
**Learning:** Custom interactive components like cards or buttons using `GestureDetector` lack visual tap feedback and standard keyboard accessibility focus states.
**Action:** Always prefer using `Material` coupled with an `InkWell` (and move inner padding to a `Padding` widget inside the `InkWell`) instead of `GestureDetector` with a decorated `Container`.
