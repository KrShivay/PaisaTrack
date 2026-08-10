## 2024-08-10 - Disable styling for CircularProgressIndicator in FilledButton
**Learning:** Hardcoding `color: Colors.white` for a `CircularProgressIndicator` inside a disabled `FilledButton` can lead to contrast issues because disabled buttons in Material 3 default to a light grey background, reducing contrast of a white spinner.
**Action:** Let the spinner inherit color from the theme or use `colorScheme.onSurface` instead of hardcoding `Colors.white` when the button is in a disabled state.
