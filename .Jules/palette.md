## 2026-08-22 - [Navigation Pill Semantics]
**Learning:** Custom navigation pills (like Bloom Nav Pill) built with `GestureDetector` lack built-in accessibility. When internal components include text and icons, screen readers may read them poorly or repeatedly.
**Action:** Always wrap custom `GestureDetector`-based tab buttons with `Semantics(button: true, selected: isSelected, label: tabName, excludeSemantics: true)` to provide a clean, single-element announcement.
