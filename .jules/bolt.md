# Codebase Learnings & Performance Patterns

## Performance Optimizations
- **String Construction Slicing:** Avoid $O(N^2)$ string concatenation in ticker/timer loops (such as typing animation widgets). Use integer counter increments combined with `string.substring(0, index)` for $O(1)$ allocations per tick.
- **Store Query Caching:** For store classes like `ReportStore`, maintain cached status counter maps (`Map<Status, int>`) updated on insertions/mutations to make status queries $O(1)$ instead of scanning lists.
- **Subtree Short-circuiting:** Convert inline helper functions returning widgets into `const StatelessWidget` widgets with `Key` parameters to allow Flutter's build phase to short-circuit subtree rebuilds.
- **Static Const Hoisting:** Hoist immutable collection lists and model instances (like incident types or safety markers) to `static const` fields to prevent redundant heap allocations on widget build or `setState`.

## Architecture & Lifecycle Safety
- **State Disposal:** Always dispose `TextEditingController`s, `Timer`s, and `AnimationController`s in `State.dispose()`.
- **Async State Guarding:** Check `if (!mounted) return;` before calling `setState` inside asynchronous delayed blocks or timers.
- **Routing:** Use a centralized `AppDrawer` widget with current route checks (`ModalRoute.of(context)?.settings.name != route`) to avoid pushing duplicate route screens.
