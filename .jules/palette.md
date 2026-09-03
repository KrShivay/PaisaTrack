## 2026-09-03 - Accessible custom tabs/pills
**Learning:** Custom metric pills built with GestureDetector and Container lack semantic meaning (causing multiple readouts or lack of state announcement for screen readers) and visual touch feedback.
**Action:** Wrap custom tab/pill buttons with Semantics(button: true, selected: isSelected, label: tabName, excludeSemantics: true) and use Material + InkWell instead of GestureDetector + Container.
