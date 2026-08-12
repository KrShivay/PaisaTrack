## 2023-10-27 - [Dart UI Filtering] Short-circuiting multiple text fields
**Learning:** Performing multiple string `.toLowerCase()` conversions on multiple fields for every item in a large Flutter list filter is highly inefficient.
**Action:** Extract query parsing (`.toLowerCase()`) outside the `.where` map and use a short-circuited list of matching rules to avoid allocating memory for string copies when a matching element is already found.
