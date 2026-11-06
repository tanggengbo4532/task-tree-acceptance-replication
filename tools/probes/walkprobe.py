#!/usr/bin/env python3
"""walkprobe - per-key movement sampling for black-box playtest.

Two modes (both emit JSON + human summary):
  offline: given a frame sequence directory (or explicit list), measure how many
           key presses produced a visible change (swallowed = unchanged frame).
  live:    drive the configured backend with N taps of one key and take one
           screenshot before/after each tap; report swallowed/moved counts.
           Never launches a game unless --yes-i-am-the-owner-of-this-test is given
           and the config is passed explicitly (single-instance discipline).

Examples:
  python walkprobe.py --dir evidence/shots --interval-ms 200
  python walkprobe.py --config playtest.json --key DOWN --taps 15 --hold-ms 60 --gap-ms 200
"""
from __future__ import annotations

import argparse
import json
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import common  # noqa: E402


def offline(args) -> dict:
    frames = [Path(p) for p in common.parse_csv_list(args.frames)] if args.frames else common.frame_list_from_dir(args.dir)
    if len(frames) < 2:
        raise SystemExit("offline walkprobe needs at least 2 frames")
    rows = []
    swallowed = 0
    for i in range(1, len(frames)):
        d = common.diff_ratio(frames[i - 1], frames[i])
        changed = d > args.threshold
        if not changed:
            swallowed += 1
        rows.append({"from": frames[i - 1].name, "to": frames[i].name, "diff": d, "changed": changed})
    moved = len(rows) - swallowed
    return {"mode": "offline", "keys": len(rows), "moved": moved, "swallowed": swallowed,
            "swallow_rate": round(swallowed / len(rows), 3) if rows else 0.0,
            "threshold": args.threshold, "rows": rows}


def live(args) -> dict:
    cfg = common.load_config(args.config)
    cfg["__config_path"] = str(Path(args.config).resolve())
    out_dir = common.evidence_dir(cfg)
    rows, swallowed = [], 0
    for i in range(args.taps):
        before = common.take_shot(cfg, f"{args.prefix}_{i:02d}_before")
        common.run_backend(cfg, "keys", args.key)
        time.sleep(args.gap_ms / 1000.0)
        after = common.take_shot(cfg, f"{args.prefix}_{i:02d}_after")
        try:
            d = common.diff_ratio(before, after)
        except ValueError as exc:
            raise SystemExit(f"frame size mismatch (window resized?): {exc}")
        changed = d > args.threshold
        if not changed:
            swallowed += 1
        rows.append({"tap": i + 1, "diff": d, "changed": changed, "before": before, "after": after})
        if args.interval_ms:
            time.sleep(args.interval_ms / 1000.0)
    moved = len(rows) - swallowed
    return {"mode": "live", "key": args.key, "taps": args.taps, "moved": moved, "swallowed": swallowed,
            "swallow_rate": round(swallowed / len(rows), 3) if rows else 0.0,
            "threshold": args.threshold, "evidence_dir": str(out_dir), "rows": rows}


def main() -> None:
    ap = argparse.ArgumentParser(description="per-key movement/was-swallowed probe")
    ap.add_argument("--config", help="playtest.json (live mode)")
    ap.add_argument("--dir", help="offline frame directory")
    ap.add_argument("--frames", help="offline explicit comma-separated frame paths")
    ap.add_argument("--key", default="DOWN", help="key name for live mode (default DOWN)")
    ap.add_argument("--taps", type=int, default=15, help="number of taps in live mode")
    ap.add_argument("--hold-ms", type=int, default=60, help="tap hold ms (config default if omitted)")
    ap.add_argument("--gap-ms", type=int, default=200, help="settle ms after each tap")
    ap.add_argument("--interval-ms", type=int, default=0, help="extra delay between taps")
    ap.add_argument("--threshold", type=float, default=0.0005, help="diff ratio considered changed")
    ap.add_argument("--prefix", default="walk")
    ap.add_argument("--yes-i-am-the-owner-of-this-test", action="store_true")
    ap.add_argument("--json", dest="json_path", default="", help="also write JSON to this path")
    args = ap.parse_args()

    if args.config:
        if not args.yes_i_am_the_owner_of_this_test:
            raise SystemExit("live mode requires --yes-i-am-the-owner-of-this-test (single-instance discipline)")
        result = live(args)
    elif args.dir or args.frames:
        result = offline(args)
    else:
        raise SystemExit("offline mode needs --dir/--frames; live mode needs --config")

    print(json.dumps(result, ensure_ascii=False, indent=2))
    print(f"[walkprobe] mode={result['mode']} options={result['keys'] if result['mode']=='offline' else result['taps']} "
          f"moved={result['moved']} swallowed={result['swallowed']} rate={result['swallow_rate']}")
    if args.json_path:
        Path(args.json_path).write_text(json.dumps(result, ensure_ascii=False, indent=2), encoding="utf-8")
        print(f"[walkprobe] json={Path(args.json_path).resolve()}")


if __name__ == "__main__":
    main()
