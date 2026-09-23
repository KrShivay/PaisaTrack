## 2024-11-05 - Lazy Evaluation in List Search
**Learning:** Found an anti-pattern in `transaction_filter_sheet.dart` where 11 fields for every transaction were eagerly converted to strings and aggregated in a list just for substring searching. This caused massive unnecessary string allocations on large lists.
**Action:** Always prefer lazy/short-circuit evaluation (using `||` and inline `.toLowerCase().contains()`) over upfront array allocations in UI search filters to reduce CPU and memory overhead.
