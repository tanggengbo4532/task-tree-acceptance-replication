# Black-box testing playbook

Work from the current task-tree node, read-only anchor, and testing experience. Accept an observable result from ordinary user input.

1. Verify the build, isolated test instance, and target window. Check that the observed UI can accept the next input. Prepare unique evidence paths.
2. Read `EXPERIENCE.md` and log the initial state, starting save and load count, time, and relevant interface text.
3. Send ordinary keyboard, mouse, touch, or text input. Capture significant transitions and any required checkpoint. Record exactly which input preceded the result. A debug mode or internal state write can support diagnosis only.
4. If an input appears to fail, distinguish no visual change, inability to move, wrong direction, and a loading or modal state. Use the [probes](probes-and-metrics.md), successive screenshots, and current location. A static frame alone is insufficient to diagnose a freeze. Compare multiple captures if a window capture is blank.
5. Stop if the path is unclear, progress stalls, or an action repeatedly fails. Save team progress and record scene or page, last useful observation, actual versus expected behavior, attempts made, time limit, evidence, and the smallest reproducible sequence.
6. Give the Lead a self-verdict with build, `t_node`, `t_exec`, evidence for each check, and remaining items. Update S/F/R entries. Developer and Lead review the same attempt.

For Windows desktop targets, check focus, DPI, and capture mode. For Web targets, locate visible controls without bypassing ordinary clicks or typing. For games, observe motion, collision, dialogue, save and reload, and any user-visible transition relevant to the current node. Keep one active test target and keep user-owned state read-only.
