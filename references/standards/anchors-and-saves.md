# Starting anchors and saves

An anchor is a reproducible starting state for a node. It can be a normal in-app save, a specific account or URL, or an isolated test dataset. Check that loading it restores the expected page, scene, location, and visible state before referring to it in the task tree.

- Keep verified anchors read-only. Create a new entry when a different build or starting state needs a new anchor.
- Record load count, slot or path, build, and any mismatch. Stop on anchor drift and report it.
- Mark synthetic states as diagnostic. A save created through a debug jump cannot support a claim about normal progression.
- Diagnose compatibility after changes to saves, maps, or state schemas. Preserve historical anchors and reconstruct an appropriate starting state through ordinary use.
- Keep user progress, team progress, and fixed anchors separate. Use the [anchor ledger](../../templates/anchor-ledger.md) and [dual progress](../testing/human-ai-dual-progress.md).
