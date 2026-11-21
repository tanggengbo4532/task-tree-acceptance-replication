# Backend action contract v4

Game Playtest dispatches backend actions through `tools/backendlib.py`. Use the Windows reference backend for desktop windows and the Web reference backend for a browser viewport. The Web backend uses Python 3.8+ and the Edge or Chrome DevTools Protocol. Choose a registered `backend` in playtest.json or give a custom `backend_path`.

## Invocation and results

    <runner> <adapter> -Action <name> [-Value <args>] -Config <playtest.json>

Use PowerShell for `.ps1` adapters and Python for `.py` adapters. The last stdout line must be a single JSON object. Put diagnostic details on stderr. Use exit 0 for success, 1 for an error, and 3 for `UNSUPPORTED`. Return `ok` and `action` on each result, `error` on failure, and `"unsupported": true` for exit 3. A missing capability never counts as a pass.

## Required actions

| Action | Value | Result |
| --- | --- | --- |
| `launch` | Configuration | Start one target, wait for readiness, return PID and window or URL metadata. Fail if readiness cannot be established. |
| `close` | | Close the tracked target. Avoid unrelated processes and ambiguous target matches. |
| `focus` | | Bring the target into focus. |
| `info` | | Read target identity, title, and window or viewport geometry. |
| `keys` | KEY[,KEY...] | Validate the whole sequence before sending ordinary short presses. Use configured timing. |
| `hold` | KEY,MS | Hold for the specified milliseconds, then release. |
| `shot` | NAME | Capture the client area or viewport. Return an absolute path and add a suffix rather than overwrite. |
| `click` | X,Y[,left/right/double] | Send a normal click within the target. Reject invalid coordinates or a location covered by another window. |
| `type` | TEXT | Enter Unicode text into the active control. |
| `scroll` | X,Y,NOTCHES | Scroll at the coordinates. Positive values scroll up. |

## Optional actions

| Action | Value | Result |
| --- | --- | --- |
| `diag` | KEY1,KEY2,MS | Hold two keys for the specified time. |
| `hint` | NAME | Capture the full frame and configured hint region. Fail if the crop is missing. |
| `read_text` | Empty or `css=<selector>` | Read visible text only. |
| `state` | | Return read-only observable state. |
| `test_fast` | on/off | Apply time-only acceleration in a separate test build if supported. |
| `failure_snapshot` | NAME | Capture the frame, recent input, and available observable state. |

The reference Windows backend provides pixel capture plus `diag` and `hint`. It reports `state`, `read_text`, `test_fast`, and `failure_snapshot` as unsupported. The Web backend additionally accepts `css=<selector>` or `text=<visible text>` for `click`. Element lookup obtains a coordinate. A normal mouse event follows. Reject hidden, disabled, ambiguous, or obscured targets.

## Observable state and configuration

Use location, title, visible_text, focus, busy, viewport, and scroll for shared fields. A game backend may declare scene, floor, pos, central_text, or objective. The step runner can evaluate declared nested paths such as focus.value. Return unsupported or an error when state cannot be observed. Preserve the application state and saves.

See [the template](../../templates/playtest.json) for the v3 configuration. Set launch and a target locator (title_pattern or process_name for Windows, or the configured URL for Web). Existing shot_dir and hint_region fields are supported for compatibility. Windows coordinates are physical client pixels. Web coordinates are CSS viewport pixels.

| Input method | Use |
| --- | --- |
| `postmessage` | Windows messages to the target. Raw Input applications may ignore them. Validate all keys and ensure clicks reach the target process. |
| `sendinput` | Global Windows input. Refuse when the target is not foreground. |
| `cdp-input` | Browser keyboard, mouse, and text events. |

Track the single launched instance, including its identity and start time where available. Refuse ambiguous or unspecified targets. Append successful inputs to input-log.jsonl with timestamp, action, value, and method. On Windows, prefer PrintWindow with screen-copy fallback for invalid frames. Keep evidence paths unique.

## Verification and failure records

When state is unavailable, the step runner may compare screenshots for changed-state checks. Other state expectations report a configuration error. Missing read_text is acceptable only when the requested text is available in state or unnecessary. The runner builds failure snapshots from a capture, keys.jsonl, optional state.json, and manifest.json.

Production builds exclude test-only shortcuts and time-scaling switches. A separate diagnostic build or external harness can support time-only acceleration. Record the build and mode in the evidence. For a custom backend, register its adapter path, runtime, platforms, actions, and unsupported capabilities in plugin.json.
