---
name: game-playtest
description: Task-tree-guided black-box acceptance for long-running desktop, web, and game projects. Four agents coordinate, repair, test, and archive. Use real inputs, protect user data, bind verdicts to evidence, and carry verified experience and user-accepted designs forward.
---

# Game Playtest v4.4

## 0. When to use this skill

Use this workflow to accept interactive software through ordinary user controls. It supports multiple user routes, long sessions, stopping and resuming at a verified point, and evidence that another person can review.

The task tree keeps the team oriented toward the user's objective across conversations. It shows the current node, verified progress, and what remains open. A blocked attempt sends its observations back to the same node. Acceptance determines when to advance. Distinguish observations from hypotheses when reporting progress.

## 1. Four agents and their responsibilities

Keep one Lead, one Developer, one Tester, and one Recorder. Resume work with the existing roles after a blockage or interruption. The Lead calls the Developer for design or repair, the Tester when a build is ready, and the Recorder for archiving. Carry project files and evidence into each handoff.

| Role | Responsibility | Boundary |
| --- | --- | --- |
| Lead | Clarifies goals and trade-offs with the user, dispatches the current node, resolves disagreements, announces decisions, and reports progress. | Leaves implementation, black-box testing, and archiving to their assigned roles. |
| Developer | Maps routes, maintains the task tree, diagnoses and repairs issues, reviews Tester evidence, and supplies a retest procedure. Escalates repeated classes of failure to design review. | Uses white-box tools for diagnosis. Leaves black-box acceptance to the Tester. |
| Tester | Uses ordinary user inputs, captures observations, reports blocked work, gives a self-verdict, and maintains testing experience. | Uses the interface, declared read-only observations, and approved testing materials. Source, arbitrary memory, and internal logs remain with the Developer. |
| Recorder | Reconciles the reports and maintains versioned, traceable archives. | Reads the supplied materials and writes archive records. The role has no acceptance vote and leaves application operation and code changes to others. |

Run only one target instance. Confirm the UI can receive input before sending it. User accounts, databases, configurations, documents, and saves are read-only to the team. Operations that delete, submit, overwrite, or pay require an explicit target and ownership check. An unintended write to user data is a P0 incident. Stop and report it immediately.

## 2. Routes, four-element nodes, and progress

The Developer maps main, secondary, and exceptional routes, including recovery and boundary cases. Divide each route into independently verifiable units.

| Element | Meaning |
| --- | --- |
| Who | The actor or relevant interactive entity. |
| Where | The reachable page, window, route, or scene and its entry point. |
| What | A real action and the visible result or transition it should achieve. |
| When | Ordered logical identifier `t_node`, such as `L1-N12`. Record physical time separately as ISO 8601 `t_exec`. |

Reuse the node ID on retry and record `t_node#retryN`. List the route, prerequisites, starting anchor, state, and evidence prefix. Later nodes continue from earlier accepted states. A node can be `not_started`, `testing`, `blocked`, `fixing`, or `passed`. Every node on the declared routes must pass before overall acceptance.

- **Progress I** belongs to the user. The team may load it read-only.
- **Progress II** belongs to the team and can be updated for resumption. Save it before reporting a blockage.
- **Fixed anchors** are separately preserved, read-only starting states produced by normal use. Label synthetic states as diagnostic. If an anchor no longer works, reconstruct through normal use or divide the node.

An accepted node keeps its verdict. Record user-tested nodes without replaying them. Reopen only the node affected by a new user-reported bug or a change to its implementation. See [dual progress](references/testing/human-ai-dual-progress.md), [slot safety](references/standards/slot-safety.md), and the [anchor ledger](templates/anchor-ledger.md).

## 3. Acceptance loop

1. The Lead gives the Developer the current objective, the problem, and the design experience index. The Tester receives the observable goal, starting anchor, and testing experience.
2. The Tester uses ordinary UI controls. Record screenshots, exact interface text, and the input trace. Label evidence with `t_node` and log `t_exec`.
3. Stop and report if progress stalls. For games, use the project's eight-minute guidance and any step or stall limits. Capture the last useful state, actual versus expected behavior, and a reproducible sequence. The Developer checks whether the issue affects the main route and escalates changes to its meaning through the Lead.
4. Diagnose and repair the observed failure. At the second occurrence of the same class of issue, write an `ARCH_REVIEW` covering root cause, why the earlier fix fell short, proposed design changes, risk, and regression scope. The Tester returns to the same node for verification.
5. The Tester records a self-verdict with evidence and open items. The Developer checks sufficiency, reproducibility, and the node outcome. The Lead confirms only after both agree. Disagreements keep the node open and can go to the user.
6. The Developer updates the task tree and the next starting anchor. The Recorder preserves the task and verdict, initial and final states, issues and fixes, code changes, explanation of the code, and main-route task-tree snapshot.
7. The Lead reports completed nodes, remaining work, and evidence to the user. Include the two progress points and any team results awaiting user review.

The step runner can record the Tester verdict after capturing an end screenshot. Each attempt binds its build and evidence SHA-256. Developer and Lead review the specified `--attempt`. Rejection or reopening archives the previous attempt. `reopen` takes `user_bug` or `code_change`; a code-change retest needs a different build ID. If a node specifies `checkpoints`, the runner must capture the start, listed steps, and end.

The [task-tree template](templates/task-tree.md) documents commands and migration. To bind verdict writes to distinct operating-system principals, use [role permissions](references/standards/role-permissions.md) and set the host access controls described there.

## 4. Reuse testing experience and user-accepted designs

The Tester reads `EXPERIENCE.md` at the start of each round and updates it afterward. Record successful procedures as S entries, pitfalls as F entries, and recurring failures with concrete repair advice as R entries. Explain when each item applies and cite its evidence.

When the user explicitly accepts an implemented design, the Lead forwards the accepted scope, build, feedback source, and evidence. The Recorder adds an entry to the project-level `DESIGN_EXPERIENCE.md`. Record the problem, accepted approach, where it applies, and how to verify it. Keep implementation authorization in its own record until the design has been accepted.

In subsequent design or repair work, the Lead includes the same index path. The Developer checks it before proposing a solution, reuses relevant approaches, and cites the entry and the current verification steps. Evaluate new use in the current node. See the [experience standard](references/standards/experience-library.md).

## 5. Evidence, safety, and reporting

Play through user-accessible interfaces using normal launch and real inputs. Preserve required dialogues, initialization, state transitions, and battles. Direct state or database edits, forced outcomes, skipped steps, widened triggers, fabricated saves or screenshots, and debug-mode captures are invalid acceptance evidence.

The Lead sends main-route trade-offs to the user with the symptom, evidence, and candidate approaches. Record authorization and verify the actual design. Review every round for shortcuts, normal startup, and relevant regressions.

Use append-only evidence under `evidence/roundNN/`. Keep a screenshot for meaningful passes and blocks, stderr and exit evidence for failures, and `input-log.jsonl` with action, time, value, and method. The evidence manifest keeps paths and SHA-256. Keep reports versioned. The [user report](templates/acceptance-report-user.md) summarizes the actual starting and ending states, changes, illustrative evidence, and open items, with the baseline-to-accepted Git diff.

## 6. Backends and observability

Backends implement the [action contract](scripts/backends/CONTRACT.md) and are selected by `playtest.json`. The Windows backend supports window messages or foreground input. The Web backend uses an isolated Edge or Chrome profile, rejects hidden or blocked controls, and exposes declared read-only state including URL, title, visible text, focus, and scroll position. Treat unavailable capabilities as unsupported.

When adding observability on the application side, use the same feasibility checks for guidance and interaction. Keep one source of next-action guidance, avoid oscillation, bound waits, buffer one pending input where needed, and give disabled or obscured controls meaningful interaction semantics. Cache expensive work and gate diagnostic logs. Expose only stable, read-only diagnostic state in a production build.

## 7. Tools and setup

1. Run the installer with `-DryRun`, then install with `-Force` or choose a fresh `-Target`. Copy [playtest.json](templates/playtest.json) into the target project and configure the backend and instance identifiers.
2. Run `python -B examples/quickstart.py` to try the local Web example.
3. Set up the four roles from [references/roles](references/roles/). Prepare the route and initial node with [task-tree.json](templates/task-tree.json).
4. Run the node with supported backend actions or [step_runner.py](tools/verify/step_runner.py). Use `task_tree.py check` and `status` to validate the tree and read its state.

| Tool | Use |
| --- | --- |
| `tools/verify/step_runner.py` | Execute inputs and check observable responses, keep JSONL and failure snapshots. |
| `tools/verify/hud_walker.py` | Follow game guidance with bounded stalls, movement checks, and scene guards. |
| `tools/verify/anchor_check.py` | Check starting anchors with position tolerance. |
| `tools/verify/run_verify.py` | Run multiple nodes, reporting PASS, FAIL, or skip for missing capabilities. |
| `tools/probes/` | Measure missed input, freeze intervals, and frame changes. Keep measurements with same-round evidence. |
| `tools/screen/` | Crop screenshots, sample pixel regions, or compare captures. |
| `tools/evidence/manifest.py` | Build a path and hash index for evidence. |
| `tools/metrics/dsh_metrics.py` | Estimate per-node time and token use. Mark estimates in reports. |

For user-reported issues, preserve the user's words, reproduce through the reported path, diagnose, repair, and return the new build ID, retest instructions, and remaining limits. Issue a new report version when the user confirms the result.
