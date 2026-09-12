## 2026-08-25 - [Flattening grouped lists for virtualization]
**Learning:** Rendering grouped lists (like transactions grouped by day) using a synchronous `Column` inside `ListView.builder` breaks Flutter's virtualization if a single group contains many items. This causes severe lag during scrolling since all items in the group are built at once.
**Action:** Flatten the grouped data structure into a single 1D list (using a sealed class for Headers and Items in Dart 3) and let `ListView.builder` handle all elements individually.
