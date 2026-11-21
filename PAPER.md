# Paper artifact index

This repository contains the materials for *Task-Tree-Guided Multi-Agent Acceptance Testing: Human–AI Collaboration and Agent-Originated Interface Evolution*. The framework is documented in English. Historical reports and case data retain their source language.

| Material | Location |
| --- | --- |
| Framework and workflow | [README](README.md), [SKILL](SKILL.md) |
| Action contract | [Backend contract](scripts/backends/CONTRACT.md) |
| Experiment matrices and code | [Experiments](experiments/) |
| PAL98 repairs and setup | [Case study](case-study/) |
| Task-tree snapshots | [Task trees](experiments/repro/task_tree/) |
| Experience records | [Experience](experiments/repro/experience/) |
| Audit | [Audit material](experiments/repro/audit/) |

The navigation comparison uses six routes, three variants, and three seeds (54 runs). The automated executor rule comparison uses four nodes, three conditions, and two seeds (24 runs). The reference experiments used Godot 4.7.2 Mono, Python 3.12.14, and a fixed 240 FPS. Use the [experiment notes](experiments/README.md) for build provenance and scope. The user save and proprietary game data are not supplied.

The numerical results concern the declared automated runs. User-facing quality, narrative meaning, and acceptance require separate judgment. The case study describes the game data needed to reproduce the project.
