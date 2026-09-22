
## 2024-06-03 - Interactive Card A11y
**Learning:** Using `GestureDetector` on a decorated `Container` for interactive cards lacks visual tap feedback and built-in keyboard focus states, reducing accessibility and micro-UX.
**Action:** Replace `GestureDetector` + `Container` with `Material` + `InkWell` + `Padding` on custom interactive components like cards or rows to ensure native rippling and standard a11y focus.
