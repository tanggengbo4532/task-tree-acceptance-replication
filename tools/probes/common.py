#!/usr/bin/env python3
"""Shared helpers for game-playtest tools (engine-agnostic).

Responsibilities:
  - load playtest config (v2, with v1 fallbacks)
  - locate backend entry (PlaytestKit.ps1 / adapter) and run one action
  - parse "SHOT <abs path> ..." output
  - frame loading + lightweight diff (Pillow if present, stdlib PNG fallback)
  - JSON/human output helpers

No third-party hard dependency: Pillow is used when available; otherwise a
small stdlib PNG decoder handles common 8-bit RGB/RGBA/grayscale PNGs.
"""
from __future__ import annotations

import json
import os
import struct
import subprocess
import sys
import zlib
from pathlib import Path
from typing import Dict, List, Optional, Sequence, Tuple

PLUGIN_ROOT = Path(__file__).resolve().parents[1]


# ---------------------------------------------------------------- config
def load_config(path: str | Path) -> Dict:
    p = Path(path)
    if not p.is_absolute():
        p = Path.cwd() / p
    if not p.exists():
        raise SystemExit(f"config not found: {p}")
    cfg = json.loads(p.read_text(encoding="utf-8-sig"))
    # v1 compatibility
    if "hint_region" in cfg and not (cfg.get("capture") or {}).get("crop_hint"):
        cfg.setdefault("capture", {})["crop_hint"] = cfg["hint_region"]
    if "shot_dir" in cfg and not (cfg.get("evidence") or {}).get("dir"):
        cfg.setdefault("evidence", {})["dir"] = cfg["shot_dir"]
    return cfg


def evidence_dir(cfg: Dict, default: str = "playtest_shots") -> Path:
    d = (cfg.get("evidence") or {}).get("dir") or cfg.get("shot_dir") or default
    p = Path(d)
    p.mkdir(parents=True, exist_ok=True)
    return p.resolve()


# ---------------------------------------------------------------- backend
def find_backend(cfg: Dict) -> Path:
    """Prefer config.backend_path, then Windows reference implementation."""
    cand = cfg.get("backend_path")
    if cand:
        p = Path(cand)
        if not p.is_absolute():
            p = PLUGIN_ROOT / p
        if p.exists():
            return p
    p = PLUGIN_ROOT / "scripts" / "windows" / "PlaytestKit.ps1"
    if p.exists():
        return p
    raise SystemExit("backend not found: set playtest.json backend_path")


def run_backend(cfg: Dict, action: str, value: str = "", timeout: int = 120) -> str:
    backend = find_backend(cfg)
    cfg_path = cfg.get("__config_path")
    cmd = ["powershell", "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", str(backend),
           "-Action", action, "-Value", value]
    if cfg_path:
        cmd += ["-Config", str(cfg_path)]
    proc = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout)
    if proc.returncode != 0:
        raise RuntimeError(f"backend {action} failed rc={proc.returncode}: {proc.stderr.strip() or proc.stdout.strip()}")
    return proc.stdout


def parse_shot_path(out: str) -> str:
    for token in out.replace("\r", "\n").split():
        if token.upper().endswith(".PNG") or token.lower().endswith(".png"):
            t = token.strip("'\"")
            if os.path.isabs(t):
                return t
    for line in out.splitlines():
        if line.startswith("SHOT "):
            parts = line.split()
            if len(parts) >= 2:
                return parts[1]
    raise RuntimeError(f"cannot parse shot path from output: {out[:300]}")


def take_shot(cfg: Dict, name: str) -> str:
    out = run_backend(cfg, "shot", name)
    return parse_shot_path(out)


# ---------------------------------------------------------------- PNG loading
def _png_decode(data: bytes) -> Tuple[int, int, bytes]:
    """Minimal PNG -> (w, h, RGBA bytes). Supports 8-bit RGB/RGBA/gray/gray-alpha."""
    if data[:8] != b"\x89PNG\r\n\x1a\n":
        raise ValueError("not a PNG")
    pos = 8
    w = h = 0
    bitdepth = colortype = 0
    idat = bytearray()
    plte = None
    while pos < len(data):
        (ln,) = struct.unpack(">I", data[pos:pos + 4])
        typ = data[pos + 4:pos + 8]
        body = data[pos + 8:pos + 8 + ln]
        pos += 12 + ln
        if typ == b"IHDR":
            w, h, bitdepth, colortype = struct.unpack(">IIBB", body[:10])
        elif typ == b"PLTE":
            plte = body
        elif typ == b"IDAT":
            idat += body
        elif typ == b"IEND":
            break
    if bitdepth != 8:
        raise ValueError(f"unsupported png bitdepth {bitdepth}")
    raw = zlib.decompress(bytes(idat))
    channels = {0: 1, 2: 3, 3: 1, 4: 2, 6: 4}[colortype]
    stride = w * channels
    out = bytearray(w * h * 4)
    prev = bytearray(stride)
    p = 0
    for y in range(h):
        ft = raw[p]
        p += 1
        line = bytearray(raw[p:p + stride])
        p += stride
        if ft == 1:
            for i in range(channels, stride):
                line[i] = (line[i] + line[i - channels]) & 0xFF
        elif ft == 2:
            for i in range(stride):
                line[i] = (line[i] + prev[i]) & 0xFF
        elif ft == 3:
            for i in range(stride):
                a = line[i - channels] if i >= channels else 0
                line[i] = (line[i] + ((a + prev[i]) >> 1)) & 0xFF
        elif ft == 4:
            for i in range(stride):
                a = line[i - channels] if i >= channels else 0
                b = prev[i]
                c = prev[i - channels] if i >= channels else 0
                pp = a + b - c
                pa, pb, pc = abs(pp - a), abs(pp - b), abs(pp - c)
                pr = a if (pa <= pb and pa <= pc) else (b if pb <= pc else c)
                line[i] = (line[i] + pr) & 0xFF
        for x in range(w):
            o = (y * w + x) * 4
            if colortype in (0, 4):
                g = line[x * channels]
                out[o:o + 4] = bytes((g, g, g, 255 if channels == 1 else line[x * channels + 1]))
            elif colortype == 3:
                idx = line[x]
                if plte and idx * 3 + 2 < len(plte):
                    out[o:o + 3] = plte[idx * 3:idx * 3 + 3]
                out[o + 3] = 255
            else:
                out[o:o + 3] = line[x * channels:x * channels + 3]
                out[o + 3] = 255 if channels == 3 else line[x * channels + 3]
        prev = line
    return w, h, bytes(out)


def load_rgba(path: str | Path) -> Tuple[int, int, bytes]:
    path = Path(path)
    try:
        from PIL import Image  # type: ignore
        with Image.open(path) as im:
            im = im.convert("RGBA")
            return im.width, im.height, im.tobytes()
    except Exception:
        return _png_decode(path.read_bytes())


# ---------------------------------------------------------------- frame diff
def frame_stats(path: str | Path, grid: int = 16) -> Dict:
    w, h, buf = load_rgba(path)
    step_x = max(1, w // grid)
    step_y = max(1, h // grid)
    colors = set()
    white = black = total = 0
    for y in range(0, h, step_y):
        for x in range(0, w, step_x):
            o = (y * w + x) * 4
            r, g, b = buf[o], buf[o + 1], buf[o + 2]
            total += 1
            if r >= 238 and g >= 238 and b >= 238:
                white += 1
            if r <= 18 and g <= 18 and b <= 18:
                black += 1
            colors.add((r >> 4, g >> 4, b >> 4))
    return {"w": w, "h": h, "colors": len(colors),
            "white": round(white / total, 3) if total else 0.0,
            "black": round(black / total, 3) if total else 0.0}


def is_blank(path: str | Path) -> bool:
    s = frame_stats(path)
    return s["colors"] <= 2 or s["white"] > 0.9 or s["black"] > 0.9


def diff_ratio(a: str | Path, b: str | Path, grid: int = 32) -> float:
    """Fraction of sampled pixels that differ (0..1). Raises on size mismatch."""
    wa, ha, ba = load_rgba(a)
    wb, hb, bb = load_rgba(b)
    if (wa, ha) != (wb, hb):
        raise ValueError(f"frame size mismatch: {(wa, ha)} vs {(wb, hb)}")
    step_x = max(1, wa // grid)
    step_y = max(1, ha // grid)
    total = diff = 0
    for y in range(0, ha, step_y):
        row = y * wa * 4
        for x in range(0, wa, step_x):
            o = row + x * 4
            if (ba[o] != bb[o] or ba[o + 1] != bb[o + 1] or ba[o + 2] != bb[o + 2]):
                diff += 1
            total += 1
    return round(diff / total, 4) if total else 0.0


def frame_sha256(path: str | Path) -> str:
    import hashlib
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


# ---------------------------------------------------------------- output
def emit(data: Dict, human_lines: Sequence[str] = (), as_json: bool = True) -> None:
    if as_json:
        print(json.dumps(data, ensure_ascii=False, indent=2))
    for line in human_lines:
        print(line)


def parse_csv_list(text: str) -> List[str]:
    return [p.strip() for p in (text or "").split(",") if p.strip()]


def frame_list_from_dir(path: str | Path) -> List[Path]:
    p = Path(path)
    if not p.is_dir():
        raise SystemExit(f"--dir not a directory: {p}")
    exts = {".png", ".jpg", ".jpeg", ".bmp"}
    return sorted([f for f in p.iterdir() if f.suffix.lower() in exts], key=lambda f: f.name)
