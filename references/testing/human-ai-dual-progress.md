# User and team progress

Keep three separate kinds of starting state.

| State | Who writes it | Use |
| --- | --- | --- |
| Progress I | User only | The user's current progress. The team may load it read-only. |
| Progress II | Team | The team's continuation point. The user may read it for verification. |
| Fixed anchor | Created by the team through ordinary use and then kept read-only | Reproducible starting state for a node. |

## Continue and hand back

1. Where relevant, the team loads Progress I read-only, records the point, and resumes from a copy in Progress II.
2. Save Progress II before reporting a blockage. Keep the location, build, time, visible state, accepted nodes, and unfinished items.
3. Give the user the team's verified progress and how to verify it using ordinary controls. The user returns the result and may save Progress I. The team records alignment and updates Progress II to the accepted point.
4. Record user-accepted nodes and proceed without replay. The only reasons to reopen an accepted node are a new user-reported defect or a change to that node's implementation.
5. If the user's feedback explicitly accepts an implemented design, the Lead sends its scope and evidence for [design experience archiving](../standards/experience-library.md#user-accepted-designs).

Each handoff shows Progress I, Progress II, nodes accepted by the user, pending user checks, and the next action. Before input, confirm the instance and interface state. Use explicit slot selection and the [anchor ledger](../../templates/anchor-ledger.md). For an unintended overwrite, stop, preserve evidence, and report the incident under [slot safety](../standards/slot-safety.md).
