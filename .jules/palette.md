## 2024-06-25 - Custom GestureDetector tabs create redundant announcements

**Learning:** When building custom navigation pills or icon buttons using `GestureDetector` with an inner `Icon` and `Text`, Flutter's default accessibility tree announces the internal elements separately (e.g., reads the text, then says "icon"). This creates a verbose and confusing experience for screen reader users expecting a unified "button" announcement.

**Action:** Always wrap custom `GestureDetector` buttons containing text and icons in a `Semantics` widget configured with `button: true`, `label: '<button name>'`, and crucially, `excludeSemantics: true` to suppress the internal component announcements and provide a single, clean interaction target.
