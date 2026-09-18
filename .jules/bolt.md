## 2025-02-12 - [Transactions screen query search string filter optimization]
**Learning:** Found a major performance bottleneck where all transaction fields are mapped to strings and converted to lower case and check with short circuits simultaneously, leading to unnecessary upfront string allocations and evaluations during a filtering loop that runs over many transaction instances.
**Action:** Always optimize string checks by checking string contain using logical short-circuits. Do not allocate string fields before they are evaluated
