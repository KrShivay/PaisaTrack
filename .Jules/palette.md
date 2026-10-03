## 2026-09-12 - Semantics Overlapping with Exclude Semantics
**Learning:** When using `excludeSemantics: true` on a custom button (like wrapping an InkWell in a Semantics node to combine multiple children into a single announcement), descendant semantic events like InkWell's native tap interaction get masked out.
**Action:** When wrapping interactive widgets in `Semantics` with `excludeSemantics: true`, always explicitly redefine interaction callbacks like `onTap` and `onTapHint` on the `Semantics` node itself.
