## 2024-10-04 - Accessible Filter Chips
**Learning:** Using `Material` + `InkWell` instead of `GestureDetector` for pills provides essential ripple feedback, while wrapping it in `Semantics(excludeSemantics: true)` with explicit properties ensures clean screen reader announcements without redundant nested elements.
**Action:** Use this composite `Semantics` + `Material` + `InkWell` pattern for any interactive chip or pill widget.
