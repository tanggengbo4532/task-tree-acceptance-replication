# Troubleshoot a test run

| Symptom | Check first |
| --- | --- |
| Input reaches the wrong target | Verify one instance, process ID, window locator, client coordinates, and focus. Use foreground input only with the target in front. |
| Clicks land off target | Check DPI awareness, window borders, scaling, screen layout, and whether an overlay intercepts the click. |
| Black or blank capture | Try the backend's screen-copy fallback. Compare actual visible content and capture mode before using the image as evidence. |
| Short inputs are lost | Compare short taps and a bounded hold on a clear route. Check the frame interval and focus. |
| A replay diverges | Check anchor, build, position, orientation, UI state, and input timing. Record what changed. |
| No apparent progress | Compare consecutive captures and visible state. Stop at the configured limit and report the evidence. |

Record build, target identity, ordinary reproduction, capture and input modes, screenshots, and what remains uncertain. See [the testing playbook](../testing/playbook.md).
