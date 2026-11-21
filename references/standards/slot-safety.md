# Save-slot and test-data safety

The user owns Progress I. The team may read it and write only its separate Progress II or an explicitly authorized test instance. Fixed anchors are read-only. The same boundary applies to production accounts, documents, databases, and configuration.

## Input and state checks

Before any input, identify the single target and confirm the current UI. Send gameplay movement only in the game world. A save menu, dialog, cutscene, battle, or unknown screen requires a separately verified action. Stop on unknown state. Guessing with repeated confirm keys can select a default user slot.

For each save or load, select the slot explicitly and verify ownership. Confirm the destination again before writing. Automation checks the slot ID and team ownership against a write allowlist. Record load counts, input, UI state, time, and evidence. Never rely on the initially selected slot.

## P0 incident response

If a user slot might have been written, stop input immediately and preserve screenshots, the input trace, and save metadata. Report to the Lead and user, including whether recovery is possible. Do not attempt a second overwrite as recovery. Document the cause and prevention in a separate incident entry. Record chapter acceptance according to its evidence and report the affected user progress separately.

In the case archive, a gameplay recovery sequence reached a save menu and selected the default user slot. The resulting safeguards are explicit UI-state checks, explicit slot selection, and team-only write permissions. See [dual progress](../testing/human-ai-dual-progress.md) and the [anchor ledger](../../templates/anchor-ledger.md).
