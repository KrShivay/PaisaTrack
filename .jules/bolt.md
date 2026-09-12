## 2024-05-24 - Short-circuit search filtering
**Learning:** Found a list filtering method `_filterItems` in `lib/features/transactions/transactions_screen.dart` that converted 10 string fields to lowercase on every iteration, regardless of if a previous field already matched the search query. It was also converting the query to lowercase on every iteration.
**Action:** When filtering lists by search queries, convert the query to lowercase outside the list traversal loop, and use short-circuiting logic `if (condition) return true;` to avoid evaluating strings after a match is found.
