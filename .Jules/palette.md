## 2024-05-24 - Interactive Card Feedback
**Learning:** Users lack visual feedback when tapping custom cards built with `GestureDetector` wrapping a decorated `Container`. This also misses standard a11y focus states for keyboard navigation.
**Action:** Prefer using a `Material` widget coupled with an `InkWell` instead. Move inner padding to a `Padding` widget inside the `InkWell` to maintain layout while gaining built-in material ripples and focus states.
