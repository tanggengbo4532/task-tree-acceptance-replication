# Godot integration

Use a normal exported or runnable build for acceptance. Configure `pal98-godot.json` or copy the generic desktop example. Supply an explicit launch target, normal startup arguments, process or window locator, and an evidence directory. Confirm that only one game instance is present.

Keep user slots read-only for the team. Use the team slot or a disposable save directory and validate the starting save against the anchor ledger. Record build, slot, load count, scene, and observed state.

Use the Windows backend to capture the client area and send normal input. Choose input mode based on what the target accepts, and verify focus. A custom Godot adapter may export a declared read-only state for checks such as movement or an expected scene. Keep headless or debug diagnostics separate from normal acceptance, preserve stdout and stderr, and record the execution mode.

Use `pal98-walk-specs.json` only with the corresponding historical PAL98 case setup. The [backend contract](../scripts/backends/CONTRACT.md) describes requirements for custom adapters.
