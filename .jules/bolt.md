# Bolt's Journal - Critical Learnings

## 2025-05-20 - Flutter Widget Tree Rebuilds & Collection Performance
**Learning:** In Flutter, calling helper functions (like `_buildCard()`) inside `build()` forces the subtree to rebuild unconditionally whenever the parent widget rebuilds. Converting helper functions to `const StatelessWidget`s allows Flutter to short-circuit rebuilds. Furthermore, O(N) list traversals in state stores or string concatenations in animation callbacks degrade frame rates.
**Action:** Extract nested helper widgets into `const StatelessWidget`s, maintain index/map counts for O(1) state queries, and use substring indexing instead of repeated string concatenation in ticker/timer loops.
