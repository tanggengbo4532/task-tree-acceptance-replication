# Evidence and acceptance

The archive should let another person reconstruct what was attempted, observed, changed, and accepted. Keep the evidence and reports versioned.

- Give each attempt a separate location and label it with the node, build, attempt, and physical execution time. Use append-only records.
- Preserve a meaningful initial and final screenshot, any required checkpoints, visible blockage, input/action sequence, and failure logs. Capture the actual target window. If the Windows capture is blank, use the documented fallback and check the visible result.
- Log time, action, value, method, and target process in `input-log.jsonl`. Attach probe results to the same attempt. Preserve stderr and exit evidence for failures.
- Index evidence paths and SHA-256 with `tools/evidence/manifest.py`. Check that files exist, match their hashes, and belong to the relevant build.
- Keep the three confirmations on the same attempt. The Tester gives a self-verdict, the Developer checks the same evidence, and the Lead announces the decision. Disagreement keeps the node open. The Recorder archives without voting.
- A user's approved change in scope or design and acceptance of the implemented outcome are separate records. Retain the user's accepted scope with its evidence.

Use [the evidence index](../../templates/evidence-index.md), [round report](../../templates/report-template.md), and [user acceptance report](../../templates/acceptance-report-user.md). Include uncovered conditions, known safety incidents, and marked time or token estimates.
