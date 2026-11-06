#!/usr/bin/env python3
"""fps_probe - estimate visual update rate / stall samples from a frame sequence.

Offline: --dir evidence/shots --interval-ms 90  (or --frames a,b,c)
Live:    --config playtest.json --frames N --interval-ms 100  (samples screenshots,
         does not send input; use only when you own the test instance)

Output JSON + human summary: transitions, update_rate_hz, stalls (> stall_ms),
max_stall_ms, blank_frames.
"""
from __future__ import annotations

import argparse
import json
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import common  # noqa: E402


def analyze(frames, interval_ms: int, threshold: float, stall_ms: int) -> dict:
    if len(frames) < 2:
        raise SystemExit("fps_probe needs at least 2 frames")
    diffs, changed = [], []
    blank = 0
    for f in frames:
        try:
            blank += 1 if common.is_blank(f) else 0
        except Exception:
            pass
    for i in range(1, len(frames)):
        d = common.diff_ratio(frames[i - 1], frames[i])
        diffs.append(d)
        changed.append(d > threshold)
    transitions = sum(1 for c in changed if c)
    elapsed_s = (len(changed) * interval_ms) / 1000.0
    update_hz = transitions / elapsed_s if elapsed_s else 0.0
    stalls = []
    run = 0
    for c in changed:
        if not c:
            run += 1
        else:
            if run and (run + 1) * interval_ms >= stall_ms:
                stalls.append((run + 1) * interval_ms)
            run = 0
    if run and (run + 1) * interval_ms >= stall_ms:
        stalls.append((run + 1) * interval_ms)
    return {"frames": len(frames), "transitions": transitions,
            "update_rate_hz": round(update_hz, 2),
            "interval_ms": interval_ms, "stalls_over_ms": stall_ms,
            "stall_count": len(stalls), "stall_ms_list": stalls,
            "max_stall_ms": max(stalls) if stalls else 0,
            "blank_frames": blank, "threshold": threshold,
            "max_diff": max(diffs) if diffs else 0.0}


def live(args) -> dict:
    cfg = common.load_config(args.config)
    cfg["__config_path"] = str(Path(args.config).resolve())
    frames = []
    for i in range(args.frames):
        frames.append(Path(common.take_shot(cfg, f"{args.prefix}_{i:02d}")))
        time.sleep(args.interval_ms / 1000.0)
    res = analyze(frames, args.interval_ms, args.threshold, args.stall_ms)
    res["mode"] = "live"
    res["frames_dir"] = str(common.evidence_dir(cfg))
    return res


def main() -> None:
    ap = argparse.ArgumentParser(description="visual update-rate / stall probe")
    ap.add_argument("--config")
    ap.add_argument("--dir")
    ap.add_argument("--frames", help="offline: comma list; live: number of samples")
    ap.add_argument("--interval-ms", type=int, default=90)
    ap.add_argument("--stall-ms", type=int, default=250)
    ap.add_argument("--threshold", type=float, default=0.0005)
    ap.add_argument("--prefix", default="fps")
    ap.add_argument("--json", dest="json_path", default="")
    ap.add_argument("--yes-i-am-the-owner-of-this-test", action="store_true")
    args = ap.parse_args()

    if args.config:
        if not args.yes_i_am_the_owner_of_this_test:
            raise SystemExit("live mode requires --yes-i-am-the-owner-of-this-test (single-instance discipline)")
        args.frames = int(args.frames or 30)
        result = live(args)
    elif args.frames:
        frames = [Path(p) for p in common.parse_csv_list(args.frames)]
        result = analyze(frames, args.interval_ms, args.threshold, args.stall_ms)
        result["mode"] = "offline"
    elif args.dir:
        frames = common.frame_list_from_dir(args.dir)
        result = analyze(frames, args.interval_ms, args.threshold, args.stall_ms)
        result["mode"] = "offline"
    else:
        raise SystemExit("offline mode needs --dir/--frames; live mode needs --config")

    print(json.dumps(result, ensure_ascii=False, indent=2))
    print(f"[fps_probe] frames={result['frames']} transitions={result['transitions']} "
          f"rate={result['update_rate_hz']}Hz stalls>={args.stall_ms}ms={result['stall_count']} max={result['max_stall_ms']}ms")
    if args.json_path:
        Path(args.json_path).write_text(json.dumps(result, ensure_ascii=False, indent=2), encoding="utf-8")
        print(f"[fps_probe] json={Path(args.json_path).resolve()}")


if __name__ == "__main__":
    main()
