# Engineering patterns for observable behavior

These patterns help testers observe and verify normal behavior.

1. **Shared feasibility.** Use the same walkability or eligibility rule for guidance and real interaction. Test a suggested action against the actual result.
2. **Single source of guidance.** Keep one active next-action message. Check for stale and competing instructions after a transition.
3. **Forward progression.** Track intended target changes and test that guidance does not oscillate between targets without a real state change.
4. **Bounded waits.** Set a timeout for loading, animations, network requests, and modal state. Clean up stale state without bypassing required content.
5. **Input buffering.** Where input can arrive during a busy frame, preserve one pending actionable event and measure whether short presses still work.
6. **Visibility and interaction.** Keep critical controls readable and reachable. A disabled control must reject clicks. Test occlusion and hit testing together.
7. **Cache and throttle.** Cache expensive per-frame queries or rendering and keep logging behind diagnostic settings. Compare equivalent input and capture intervals.
8. **Stable read-only signals.** Expose observable fields with clear semantics for evidence and troubleshooting. Keep diagnostic tools from modifying the user flow.

Record probe results, input, build, and screenshots together. See the [testing probes](../testing/probes-and-metrics.md).
