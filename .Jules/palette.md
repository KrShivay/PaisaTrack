## 2024-08-27 - Custom Nav Pills with Icon and Text
**Learning:** When building custom navigation tabs (`GestureDetector` containing both an `Icon` and `Text`), screen readers will read each element separately, causing redundant and confusing announcements.
**Action:** Wrap the outer `GestureDetector` in a `Semantics` widget (e.g., `Semantics(button: true, selected: isSelected, label: tabName, excludeSemantics: true)`). The `excludeSemantics: true` property is critical as it hides the internal icon and text semantics, providing a clean, single-element announcement.
