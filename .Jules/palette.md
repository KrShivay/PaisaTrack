## 2024-11-20 - Dashboard Metric Pills Interactive States
**Learning:** Custom tappable chips using `GestureDetector` lacked semantic context for screen readers and touch ripple feedback.
**Action:** Replaced `GestureDetector` with `Semantics(button: true)` + `Material` + `InkWell` to provide standard interactive widget behavior, preserving the custom rounded style using `clipBehavior`.