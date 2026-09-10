## 2026-09-10 - Period Selector Interactive Accessibility
**Learning:** Custom navigation buttons and pills containing text and icons using GestureDetector lack clean screen reader announcements, built-in ripples, and keyboard focus states.
**Action:** Wrap interactive elements in Semantics(excludeSemantics: true) to provide a single-element announcement, and use Material + InkWell + Padding instead of GestureDetector + Container for visual tap feedback and a11y focus states.
