## 2024-10-10 - Add visual tap feedback to TransactionRow
**Learning:** Using `GestureDetector` with a `Container` provides no visual feedback on tap, leaving users unsure if their action registered. Wrapping interactive list elements in `Material` and `InkWell` provides standard material ripples and accessibility focus states.
**Action:** Use `Material` and `InkWell` for all custom interactive list rows and cards to ensure consistent visual feedback and keyboard accessibility.
