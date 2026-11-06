#!/usr/bin/env python3
"""image_ops - small, dependency-free screenshot evidence operations.

CLI:
  python image_ops.py info   --file shot.png
  python image_ops.py stats  --dir evidence/shots
  python image_ops.py compare --a a.png --b b.png [--threshold 0.0005]
  python image_ops.py blank  --file shot.png
  python image_ops.py hash   --file shot.png
  python image_ops.py diffdir --dir evidence/shots [--out diffs.json]
"""
from __future__ import annotations

import argparse
import json
import sys
import zlib
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "probes"))
import common  # noqa: E402


def encode_png_rgba(w: int, h: int, rgba: bytes, out_path: Path) -> Path:
    """Minimal RGBA PNG encoder (no Pillow needed)."""
    raw = bytearray()
    stride = w * 4
    for y in range(h):
        raw.append(0)
        raw += rgba[y * stride:(y + 1) * stride]

    def chunk(typ: bytes, body: bytes) -> bytes:
        return (len(body).to_bytes(4, "big") + typ + body
                + (zlib.crc32(typ + body) & 0xFFFFFFFF).to_bytes(4, "big"))

    png = b"\x89PNG\r\n\x1a\n"
    png += chunk(b"IHDR", w.to_bytes(4, "big") + h.to_bytes(4, "big") + bytes((8, 6, 0, 0, 0)))
    png += chunk(b"IDAT", zlib.compress(bytes(raw), 6))
    png += chunk(b"IEND", b"")
    out_path.write_bytes(png)
    return out_path


def main() -> None:
    ap = argparse.ArgumentParser(description="screenshot evidence image ops")
    sub = ap.add_subparsers(dest="cmd", required=True)

    for name in ("info", "blank", "hash"):
        p = sub.add_parser(name)
        p.add_argument("--file", required=True)
    p = sub.add_parser("compare")
    p.add_argument("--a", required=True); p.add_argument("--b", required=True)
    p.add_argument("--threshold", type=float, default=0.0005)
    p = sub.add_parser("stats"); p.add_argument("--dir", required=True)
    p = sub.add_parser("diffdir")
    p.add_argument("--dir", required=True); p.add_argument("--out", default="")
    p.add_argument("--threshold", type=float, default=0.0005)

    args = ap.parse_args()
    if args.cmd == "info":
        st = common.frame_stats(args.file)
        print(json.dumps({"file": str(Path(args.file).resolve()), **st}, ensure_ascii=False))
    elif args.cmd == "blank":
        print(json.dumps({"file": str(Path(args.file).resolve()), "blank": common.is_blank(args.file)}))
    elif args.cmd == "hash":
        print(json.dumps({"file": str(Path(args.file).resolve()), "sha256": common.frame_sha256(args.file)}))
    elif args.cmd == "compare":
        d = common.diff_ratio(args.a, args.b)
        print(json.dumps({"a": str(Path(args.a).resolve()), "b": str(Path(args.b).resolve()),
                          "diff": d, "changed": d > args.threshold, "threshold": args.threshold}))
    elif args.cmd == "stats":
        frames = common.frame_list_from_dir(args.dir)
        rows = []
        for f in frames:
            st = common.frame_stats(f)
            st.update({"file": f.name, "sha256": common.frame_sha256(f)})
            rows.append(st)
        blank = sum(1 for r in rows if r["colors"] <= 2 or r["white"] > 0.9 or r["black"] > 0.9)
        print(json.dumps({"dir": str(Path(args.dir).resolve()), "frames": len(rows), "blank_frames": blank,
                          "rows": rows}, ensure_ascii=False, indent=2))
    elif args.cmd == "diffdir":
        frames = common.frame_list_from_dir(args.dir)
        rows = []
        for i in range(1, len(frames)):
            d = common.diff_ratio(frames[i - 1], frames[i])
            rows.append({"from": frames[i - 1].name, "to": frames[i].name, "diff": d, "changed": d > args.threshold})
        out = {"dir": str(Path(args.dir).resolve()), "pairs": len(rows),
               "changed": sum(1 for r in rows if r["changed"]), "rows": rows}
        if args.out:
            Path(args.out).write_text(json.dumps(out, ensure_ascii=False, indent=2), encoding="utf-8")
            out["json"] = str(Path(args.out).resolve())
        print(json.dumps(out, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
