
## 2024-10-10 - Replace GestureDetector with Material+InkWell wrapped in Semantics
**Learning:** When building interactive items with both text and icons, `GestureDetector` doesn't provide visual touch feedback or robust accessibility out-of-the-box. Moreover, `Semantics` with `excludeSemantics: true` explicitly drops descendant actions, meaning tap behaviors in inner components (like `InkWell`) won't be announced or handled by screen readers unless explicitly redefined.
**Action:** Wrap custom navigation buttons or pills in a `Semantics` node defining `button`, `selected`, `label`, `onTapHint`, and `onTap`. Inside `Semantics`, use a `Material` and `InkWell` to get default keyboard focus states and visual ripples.
