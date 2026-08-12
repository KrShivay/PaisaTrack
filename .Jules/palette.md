## 2024-12-09 - Prefer Material and InkWell for tap feedback

**Learning:** When building custom interactive components like cards or rows, using a `GestureDetector` with a decorated `Container` results in no visual tap feedback and missing accessibility focus states.
**Action:** Always prefer using a `Material` widget (with `color` and `borderRadius`) wrapping an `InkWell` (and `Padding`) for interactive containers. This provides built-in material ripples for visual tap feedback and standard a11y focus states for keyboard navigation.
