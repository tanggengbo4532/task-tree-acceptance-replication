#!/usr/bin/env python3
"""holdprobe - long-press freeze/changeframe sampler for black-box playtest.

Measures during a HOLD: how many sampled frames changed, longest freeze gap, and
freeze ratio. Offline mode analyses an existing frame sequence; live mode holds a
key through the backend while sampling screenshots at --interval-ms.

Examples:
  python holdprobe.py --dir evidence/hold --interval-ms 90
  python holdprobe.py --config playtest.json --key DOWN --ms 800 --interval-ms 90
"""
from __future__ import annotations

import argparse
import json
import subprocess
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import common  # noqa: E402


def analyze(frames, interval_ms: int, threshold: float) -> dict:
    if len(frames) < 2:
        raise SystemExit("holdprobe needs at least 2 frames")
    changed = []
    diffs = []
    for i in range(1, len(frames)):
        d = common.diff_ratio(frames[i - 1], frames[i])
        diffs.append(d)
        changed.append(d > threshold)
    longest_run = run = 0
    for c in changed:
        run = 0 if c else run + 1
        longest_run = max(longest_run, run)
    changes = sum(1 for c in changed if c)
    return {"frames": len(frames), "samples": len(changed), "changed_samples": changes,
            "freeze_samples": len(changed) - changes,
            "change_rate": round(changes / len(changed), 3) if changed else 0.0,
            "longest_freeze_ms": (longest_run + 1) * interval_ms if longest_run else 0,
            "longest_freeze_samples": longest_run,
            "max_diff": max(diffs) if diffs else 0.0,
            "avg_diff": round(sum(diffs) / len(diffs), 5) if diffs else 0.0,
            "threshold": threshold, "interval_ms": interval_ms}


def live(args) -> dict:
    cfg = common.load_config(args.config)
    cfg["__config_path"] = str(Path(args.config).resolve())
    backend = common.find_backend(cfg)
    hold_cmd = ["powershell", "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", str(backend),
                "-Action", "hold", "-Value", f"{args.key},{args.ms}", "-Config", str(Path(args.config).resolve())]
    frames = []
    proc = subprocess.Popen(hold_cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    t0 = time.time()
    while proc.poll() is None and (time.time() - t0) * 1000 < args.ms + args.settle_ms:
        frames.append(common.take_shot(cfg, f"{args.prefix}_{len(frames):02d}"))
        time.sleep(args.interval_ms / 1000.0)
    try:
        outs, errs = proc.communicate(timeout=10)
    except subprocess.TimeoutExpired:
        proc.kill(); outs, errs = "", ""
    frames.append(common.take_shot(cfg, f"{args.prefix}_{len(frames):02d}_after"))
    res = analyze([Path(f) for f in frames], args.interval_ms, args.threshold)
    res.update({"mode": "live", "key": args.key, "hold_ms": args.ms, "backend_out": outs.strip(),
                "frames_dir": str(common.evidence_dir(cfg)), "frames": frames})
    return res


def main() -> None:
    ap = argparse.ArgumentParser(description="long-press freeze/changeframe probe")
    ap.add_argument("--config", help="playtest.json (live mode)")
    ap.add_argument("--dir", help="offline frame directory")
    ap.add_argument("--frames", help="offline explicit comma-separated frames")
    ap.add_argument("--key", default="DOWN")
    ap.add_argument("--ms", type=int, default=800, help="hold duration (live)")
    ap.add_argument("--interval-ms", type=int, default=90, help="sampling interval")
    ap.add_argument("--settle-ms", type=int, default=300)
    ap.add_argument("--threshold", type=float, default=0.0005)
    ap.add_argument("--prefix", default="hold")
    ap.add_argument("--json", dest="json_path", default="")
    ap.add_argument("--yes-i-am-the-owner-of-this-test", action="store_true")
    args = ap.parse_args()

    if args.config:
        if not args.yes_i_am_the_owner_of_this_test:
            raise SystemExit("live mode requires --yes-i-am-the-owner-of-this-test (single-instance discipline)")
        result = live(args)
    elif args.dir or args.frames:
        frames = [Path(p) for p in common.parse_csv_list(args.frames)] if args.frames else common.frame_list_from_dir(args.dir)
        result = analyze(frames, args.interval_ms, args.threshold)
        result["mode"] = "offline"
    else:
        raise SystemExit("offline mode needs --dir/--frames; live mode needs --config")

    print(json.dumps(result, ensure_ascii=False, indent=2))
    print(f"[holdprobe] mode={result['mode']} samples={result['samples']} changed={result['changed_samples']} "
          f"freeze={result['freeze_samples']} longest_freeze={result['longest_freeze_ms']}ms")
    if args.json_path:
        Path(args.json_path).write_text(json.dumps(result, ensure_ascii=False, indent=2), encoding="utf-8")
        print(f"[holdprobe] json={Path(args.json_path).resolve()}")


if __name__ == "__main__":
    main()
