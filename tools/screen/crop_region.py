#!/usr/bin/env python3
"""crop_region - crop a screenshot region into a new PNG (dependency-free).

Used to cut hint bars / counters from full frames for fast per-step evidence.
Coordinates are client-area pixels: x,y,w,h (top-left origin), matching
playtest.json capture.crop_hint.

Examples:
  python crop_region.py --src shot.png --region 60,145,1160,100 --out hint.png
  python crop_region.py --src shot.png --region 60,145,1160,100 --dir evidence/crops
"""
from __future__ import annotations

import argparse
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "probes"))
import common  # noqa: E402
sys.path.insert(0, str(Path(__file__).resolve().parent))
from image_ops import encode_png_rgba  # noqa: E402


def parse_region(text: str):
    parts = [int(p) for p in text.replace(" ", "").split(",")]
    if len(parts) != 4:
        raise SystemExit("--region must be x,y,w,h")
    return parts


def crop(src: str | Path, region, out: Path) -> Path:
    x, y, w, h = region
    W, H, buf = common.load_rgba(src)
    if x < 0 or y < 0 or w <= 0 or h <= 0:
        raise SystemExit(f"invalid region {region}")
    if x + w > W or y + h > H:
        w = max(1, min(w, W - x))
        h = max(1, min(h, H - y))
    out.parent.mkdir(parents=True, exist_ok=True)
    rows = bytearray()
    stride = W * 4
    for yy in range(y, y + h):
        rows += buf[yy * stride + x * 4: yy * stride + (x + w) * 4]
    return encode_png_rgba(w, h, bytes(rows), out)


def main() -> None:
    ap = argparse.ArgumentParser(description="crop screenshot region")
    ap.add_argument("--src", required=True)
    ap.add_argument("--region", required=True, help="x,y,w,h (client pixels)")
    ap.add_argument("--out", default="")
    ap.add_argument("--dir", default="", help="output directory (auto name)")
    args = ap.parse_args()

    region = parse_region(args.region)
    if args.out:
        out = Path(args.out)
    elif args.dir:
        out = Path(args.dir) / (Path(args.src).stem + f"_crop_{region[0]}_{region[1]}_{region[2]}x{region[3]}.png")
    else:
        out = Path(args.src).with_name(Path(args.src).stem + "_crop.png")
    out = out.resolve()
    crop(args.src, region, out)
    print(f"CROP {out} region={region[0]},{region[1]},{region[2]},{region[3]} src={Path(args.src).resolve()}")


if __name__ == "__main__":
    main()
