# Four-element task tree

A node is the smallest unit that can be accepted independently. Map main, secondary, and exceptional routes. Later nodes start at the result of earlier nodes. Record finer-grained checks in the evidence notes.

| Element | JSON field | Meaning |
| --- | --- | --- |
| Who | `who` | Recognizable actor or relevant interactive entity. |
| Where | `where` | Reachable page, route, scene, or control with an identifiable entry point. |
| What | `action` | Ordinary input and the observable result or transition. |
| When | `t_node` | Unique ordered logical ID. Use ISO 8601 `t_exec` for execution and evidence timestamps. |

Keep the ID on retry. Refer to `t_node#retryN` in reports, anchor records, and evidence. Use physical timestamps to align files. Use `requires` only for earlier nodes.

## Validate and record

Use [task-tree.json](task-tree.json) or the [example](../examples/task-tree.json).

```powershell
python -B tools/verify/task_tree.py check --tree task-tree.json
python -B tools/verify/task_tree.py status --tree task-tree.json --strict
```

`check` validates structure, node ordering, transitions, and evidence. `status` also checks whether all declared nodes passed. Use `--manifest evidence/manifest.json` to verify against an evidence manifest. The normal states are `not_started`, `testing`, `blocked`, `fixing`, and `passed`.

The Tester records a build ID (from `--build` or the top-level `build`) and evidence files. The tool stores their SHA-256 in the attempt. Developer and Lead confirm the same attempt after reading its evidence.

```powershell
# Using the step runner after a normal start
python -B tools/verify/step_runner.py --backend playtest.json --steps n01.json --tree task-tree.json --build BUILD_ID

# For a manually executed node without required checkpoints
python -B tools/verify/task_tree.py record --tree task-tree.json --node A1 --role tester --who tester --build BUILD_ID --evidence evidence/A1_s05.png

# After reviewing the selected attempt
python -B tools/verify/task_tree.py record --tree task-tree.json --node A1 --role developer --who dev --attempt ATTEMPT_ID
python -B tools/verify/task_tree.py record --tree task-tree.json --node A1 --role lead --who lead --attempt ATTEMPT_ID
```

`--verdict reject` sends the node to `fixing` and archives the attempt. Reopen an accepted node for a new user defect or an implementation change to that node.

```powershell
python -B tools/verify/task_tree.py reopen --tree task-tree.json --node A1 --reason user_bug --who lead
```

Reopening leaves other verdicts in place. Capture fresh evidence for the reopened node. A `code_change` reopen requires a build ID different from the previous recorded build. Failed writes preserve the tree. Legacy v4.2 and earlier records can be read as history. Strict status requires a current attempt and build binding. Use [role permissions](../references/standards/role-permissions.md) when deployment binds writes to OS identities.

## Optional checkpoint evidence

Set `"checkpoints": [2, 4]` on the node to capture after steps two and four. Use increasing one-based step numbers before the final step. Each listed step must have an observable `expect` in the steps file.

Load the starting state and run `step_runner.py --tree`. The start, checkpoints, and end must all be captured from one attempt. The paths are recorded in `attempt.checkpoint_evidence`. Missing required captures prevent the Tester verdict. The Developer and Lead review the same attempt.

## Human-readable records

| Route | Type | Scope |
| --- | --- | --- |
| A | Main | Standard user path |
| B | Secondary | Optional behavior |
| C | Exceptional | Invalid input, boundary, or recovery |

| ID | Route | Who | Where | What | Executed at | Requires | Anchor | Status |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| A1 | A | User | Start page | Reach the home screen with normal input | | | | Not started |

| Round | Node | Transition | `t_exec` | Evidence |
| --- | --- | --- | --- | --- |
| | | | | |

| Node or retry | Anchor path | Created by normal use or synthetic | Notes |
| --- | --- | --- | --- |
| | | | |

| Node | Blockage or ledger ID | Blocking? | Tester suggestion | Developer response |
| --- | --- | --- | --- | --- |
| | | | | |

After a node, review granularity and record any split, merge, or prerequisite change with its reason. Archive a versioned main-route snapshot. On the second recurring failure, retain both attempt references, the design-level diagnosis, `ARCH_REVIEW`, and the result of verification.
