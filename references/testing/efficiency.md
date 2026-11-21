# Speed and reproducibility

Use a verified node anchor to avoid replaying accepted work. Keep user and team progress separate. The task-tree checker verifies structure and recorded evidence. The step runner executes a node's input and visible checks. The HUD walker can measure progress and detect stalls where the backend exports the required state.

Use external probes or a labeled diagnostic run to locate a failure. Keep startup, user-path acceptance, and optional diagnostic acceleration distinct. A test-fast mode requires a separate test build or external harness and may change timing only. Preserve the means to reproduce any accepted result through normal use.

A failed automated attempt should leave its input trace, available state, last frame, and reason. Use `run_verify.py` for multiple configured checks. Label missing abilities as skipped or unsupported. Compare time, replayed steps, failure counts, and coverage under comparable conditions.

See the [backend action contract](../../scripts/backends/CONTRACT.md) and [probe guide](probes-and-metrics.md).
