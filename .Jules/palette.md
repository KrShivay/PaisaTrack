
## 2024-05-18 - Improve Add Button Accessibility
**Learning:** Replaced GestureDetector and Container with Semantics, Material, and InkWell for the "Add" button to ensure proper a11y focus states for keyboard navigation and provide built-in material ripples for visual tap feedback. The excludeSemantics drop descendant semantics (like InkWell's tap), requiring explicit redefinition of interactions on the Semantics node.
**Action:** Always prefer Material+InkWell over GestureDetector for interactive elements to guarantee standard accessibility and UX behavior.
