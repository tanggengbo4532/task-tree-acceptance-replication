# Probes and measurements

Use the probes to characterize a visible problem and keep their output with the same-round input and screenshots.

| Tool | Typical measurement |
| --- | --- |
| `tools/probes/walkprobe.py` | Changed captures over attempted taps, missed input estimate, and longest unchanged period. |
| `tools/probes/holdprobe.py` | Changed frames, largest gap, and longest freeze while a key is held. |
| `tools/probes/fps_probe.py` | Approximate frame update rate and pauses from visual sampling. |
| `tools/screen/image_ops.py` | Crop, compare, and sample a consistent region. |
| `tools/evidence/manifest.py` | Link evidence paths, counts, timestamps, and hashes. |
| `tools/metrics/dsh_metrics.py` | Time and token estimates. Report the allocation method and mark the figures as estimates. |

Inspect command options with `--help`. Use a verified starting point, one instance, known focus, and a continuously movable scene where appropriate. An animation, dialog, collision, or blank capture can bias frame-difference measures. Confirm the UI state and compare visible position before inferring missed input. Use a consistent region and sample interval. Early project calibrations used 800 ms holds and about 90 ms sampling. Recalibrate before applying thresholds elsewhere.

Save the command, input mode, timing, region, build, evidence paths, and original probe output. Distinguish a failed check, an unsupported capability, and an uncovered condition.
