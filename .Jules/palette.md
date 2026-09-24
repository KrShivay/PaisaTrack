## 2024-09-24 - Semantic navigation tabs
**Learning:** Using `excludeSemantics: true` on a `Semantics` widget wrapping an `InkWell` custom button is necessary to drop the inner tap semantics from the `InkWell` while still providing a clean single-element announcement.
**Action:** When building custom interactive components that contain multiple visual elements (like icons and text) and use `InkWell` for material ripples, always wrap them in a `Semantics` widget with `excludeSemantics: true` and explicitly redefine interactions like `onTap` and `onTapHint` on the `Semantics` node.
