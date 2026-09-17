## 2024-05-24 - Improve custom tab navigation accessibility
**Learning:** When building custom bottom navigation pills or buttons with both text and icons, using GestureDetector lacks proper semantic labeling for screen readers and native material ripple feedback.
**Action:** Wrap the interactive element (Material + InkWell) in a Semantics widget (with excludeSemantics: true) to provide a single, clean announcement, redefining interactions (onTap, onTapHint) directly on the Semantics node.
