## 2026-09-13 - Enhance Tap Feedback
**Learning:** In Flutter, relying solely on GestureDetector for buttons and cards removes visual feedback (like Material ripples) and hurts accessibility because standard interactive focus/hover states are lost. Adding custom Semantics logic allows correct screen reader behavior.
**Action:** Replaced GestureDetector + Container with Material + InkWell (and Semantics for custom buttons) to restore native visual tap feedback and a11y focus states.
