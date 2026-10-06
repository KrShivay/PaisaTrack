## 2024-10-24 - Accessible Gradient Buttons
**Learning:** Icon-only buttons using GestureDetector inside complex containers (like gradients) miss both a11y labels and visual ripple feedback.
**Action:** Wrap gradient Containers in Semantics, and use an inner Material (type transparency) with an InkWell (custom border) to provide both screen reader support and proper material ink splashes.
