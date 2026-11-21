# Testing and design experience

The Tester maintains `EXPERIENCE.md` for operating procedures and observations. The Recorder maintains `DESIGN_EXPERIENCE.md` in the project's fixed archive directory for designs explicitly accepted by the user.

## Testing experience

| ID | Write down |
| --- | --- |
| S | Successful input sequence, starting anchor, or verification procedure. Include its conditions and evidence. |
| F | A failed or misleading approach, its visible effect, and a better response if verified. |
| R | The second occurrence of a similar failure. Compare the earlier entries and give the Developer a concrete improvement to investigate. |

At the start of a round, read the successes, pitfalls, and verification status. At the end, write back new evidence and status. Keep source and implementation details out of the black-box log. Cross-reference the defect ledger when a design-level repair supersedes a workaround.

Check starting point, orientation, frame rate, view, and guidance version before reuse. A long hold that works in a straight corridor can overshoot at a turn. A fixed input sequence can fail at a shifted starting position. Mark uncertain transfers for verification and log failures as F entries.

## User-accepted designs

1. The Lead identifies the implemented design, build, accepted scope, and source of the user's explicit acceptance. Record preliminary implementation authorization separately.
2. The Recorder adds the problem, accepted approach, evidence, applicability, and observable verification method to [`DESIGN_EXPERIENCE.md`](../../templates/design-experience.md). Reuse the same project path across rounds. Consolidate identical references and append any later withdrawal or replacement.
3. The Lead supplies the path on future design or repair dispatches. The Developer looks up applicable entries before proposing a solution and returns the entry ID, how it was used, and what needs verification.
4. The Tester checks the current node's outcome. Preserve the existing verdicts on other nodes and the standard three-role acceptance workflow.
