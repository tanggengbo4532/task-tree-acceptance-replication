# Game Playtest

Game Playtest is a four-agent framework for long-running black-box acceptance of desktop apps, web apps, and games. It keeps the user's objective, progress, and evidence in a task tree that the team can consult across rounds of dialogue.

The PAL98 Godot case study illustrates the framework. Start with the [architecture and agent workflow](SKILL.md) or run the local web example below.

## How acceptance works

1. **Define the task.** The Developer maps user routes into independently verifiable nodes. Each node specifies who acts, where, what observable result is required, and its logical identifier, `t_node`.
2. **Run the current node.** The Lead assigns the node. The Tester uses ordinary input and records what happened. If blocked, the Tester saves team progress, records the observed failure, and stops. The Developer uses that evidence to diagnose and repair the same node.
3. **Review the evidence.** The Tester records a verdict, the Developer reviews it, and the Lead confirms the result. All three refer to the same build, attempt, and hashed evidence. The Recorder archives the result. An accepted node stays accepted unless a new defect or a change to that node's implementation warrants reopening it.
4. **Carry experience forward.** The Tester records successful procedures and pitfalls. The Recorder also preserves designs the user explicitly accepts. The Developer consults these design records when planning later work and verifies the result at the new node. See the [design experience template](templates/design-experience.md).

The user sets priorities, decides design trade-offs, and accepts delivery using a readable report. User-owned progress stays read-only to the team. Team progress and fixed starting anchors have separate ownership.

## Install on Windows

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\install.ps1 -DryRun
powershell -NoProfile -ExecutionPolicy Bypass -File .\install.ps1 -Force
```

Use `-Target` for a custom destination. The installer checks an existing destination before replacing it.

## Run the example

With Python 3.8+ and Edge or Chrome installed, run the local notes app example from the plugin directory.

```powershell
python -B examples/quickstart.py
```

The example records a failed login, retries with valid credentials, and shows why the Lead cannot confirm before Developer review. It prints the temporary task tree, screenshots, and input trace. In a real project, each role reviews the evidence before recording its own decision.

## Reference

| Area | Entry point |
| --- | --- |
| Agent roles | [Lead](references/roles/lead.md), [Developer](references/roles/developer.md), [Tester](references/roles/tester.md), [Recorder](references/roles/recorder.md) |
| Task trees and evidence | [Task-tree template](templates/task-tree.md), [evidence and acceptance](references/standards/evidence-and-acceptance.md), [role permissions](references/standards/role-permissions.md) |
| Human and team progress | [Dual progress](references/testing/human-ai-dual-progress.md), [user acceptance report](templates/acceptance-report-user.md) |
| Backends | [Action contract](scripts/backends/CONTRACT.md), [configuration](templates/playtest.json), [examples](examples/README.md) |
| Paper artifacts | [Artifact index](PAPER.md), [PAL98 case study](case-study/), [experiments](experiments/) |

The Windows backend drives desktop windows. The Web backend uses Edge or Chrome through the DevTools Protocol with an isolated browser profile. It locates elements by selector or text, and sends real input. A node may require start, intermediate, and end screenshots from one attempt.

## Verify

```powershell
python -B tools/verify/task_tree.py --selfcheck
python -B tests/Test-AcceptanceDesign.py
powershell -NoProfile -ExecutionPolicy Bypass -File tests\Test-Plugin.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File tests\Test-Backend.ps1
```

The last command opens a Windows test fixture. See [LICENSE](LICENSE) for the MIT license.
