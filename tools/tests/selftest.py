#!/usr/bin/env python3
"""selftest - run offline self-checks for every game-playtest tool.

Checks (no game window, no input, safe on a shared host):
  1. PNG encode/decode, frame stats, blank detection, diff ratio
  2. image_ops + crop_region
  3. walkprobe / holdprobe / fps_probe offline analyzers
  4. evidence/manifest append-only + verify + duplicate rejection
  5. metrics/dsh_metrics.py --selftest
  6. JSON files parse (plugin.json / examples / templates/playtest.json)
  7. PowerShell files parse (if powershell available; uses [Parser]::ParseFile)

Usage:
  python tools/tests/selftest.py [--plugin-root E:\\plugin] [-v]
Exit code 0 = all pass.
"""
from __future__ import annotations

import sys as _sys
_sys.dont_write_bytecode = True  # package hygiene: never leave __pycache__ in the plugin

import argparse
import json
import subprocess
import sys
import tempfile
from pathlib import Path
from types import SimpleNamespace

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools" / "probes"))
sys.path.insert(0, str(ROOT / "tools" / "screen"))
sys.path.insert(0, str(ROOT / "tools" / "evidence"))
sys.path.insert(0, str(ROOT / "tools" / "metrics"))

import common  # noqa: E402
from image_ops import encode_png_rgba  # noqa: E402
import crop_region  # noqa: E402
import manifest  # noqa: E402
import walkprobe  # noqa: E402
import holdprobe  # noqa: E402
import fps_probe  # noqa: E402

RESULTS = []


def check(name: str, fn) -> None:
    try:
        detail = fn()
        RESULTS.append((name, True, detail or ""))
        print(f"PASS  {name}  {detail or ''}")
    except Exception as exc:  # noqa: BLE001
        RESULTS.append((name, False, repr(exc)))
        print(f"FAIL  {name}  {exc!r}")


def solid(w: int, h: int, rgb=(20, 30, 40), rect=None, rect_rgb=(240, 10, 10)):
    buf = bytearray()
    for y in range(h):
        for x in range(w):
            c = rect_rgb if (rect and rect[0] <= x < rect[0] + rect[2] and rect[1] <= y < rect[1] + rect[3]) else rgb
            buf += bytes((c[0], c[1], c[2], 255))
    return w, h, bytes(buf)


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--plugin-root", default=str(ROOT))
    ap.add_argument("-v", "--verbose", action="store_true")
    args = ap.parse_args()
    root = Path(args.plugin_root)

    def t_png():
        w, h = 64, 48
        rgba = bytearray()
        for y in range(h):
            for x in range(w):
                if 10 <= x < 18 and 10 <= y < 18:
                    c = (240, 10, 10, 255)
                elif 30 <= x < 38 and 10 <= y < 18:
                    c = (10, 240, 10, 255)
                elif 10 <= x < 18 and 30 <= y < 38:
                    c = (10, 10, 240, 255)
                else:
                    c = (10, 20, 30, 255)
                rgba += bytes(c)
        rgba = bytes(rgba)
        with tempfile.TemporaryDirectory() as td:
            p = Path(td) / "a.png"
            encode_png_rgba(w, h, rgba, p)
            st = common.frame_stats(p)
            assert st["w"] == 64 and st["h"] == 48
            assert common.frame_sha256(p)
            assert not common.is_blank(p)
            blank = Path(td) / "blank.png"
            encode_png_rgba(8, 8, solid(8, 8, (255, 255, 255))[2], blank)
            assert common.is_blank(blank), "white frame must be blank"
            return f"png {st['w']}x{st['h']} colors={st['colors']}"

    def t_diff():
        with tempfile.TemporaryDirectory() as td:
            wa, ha, ba = solid(64, 48)
            _, _, bb = solid(64, 48, rect=(0, 0, 16, 16))
            a, b = Path(td) / "a.png", Path(td) / "b.png"
            encode_png_rgba(wa, ha, ba, a); encode_png_rgba(wa, ha, bb, b)
            d = common.diff_ratio(a, b)
            assert d > 0.0, "changed frame must differ"
            d2 = common.diff_ratio(a, a)
            assert d2 == 0.0
            return f"diff changed={d} same={d2}"

    def t_crop():
        with tempfile.TemporaryDirectory() as td:
            w, h, rgba = solid(80, 60, rect=(20, 20, 10, 10))
            src = Path(td) / "src.png"
            encode_png_rgba(w, h, rgba, src)
            out = Path(td) / "crop.png"
            crop_region.crop(src, (20, 20, 10, 10), out)
            cw, ch, _ = common.load_rgba(out)
            assert (cw, ch) == (10, 10), (cw, ch)
            return "crop 10x10"

    def t_probes_offline():
        with tempfile.TemporaryDirectory() as td:
            d = Path(td)
            frames = []
            for i in range(6):
                w, h, rgba = solid(48, 32, rect=(i * 4, 0, 4, 4))
                p = d / f"f{i:02d}.png"
                encode_png_rgba(w, h, rgba, p)
                frames.append(str(p))
            ns = SimpleNamespace(frames=",".join(frames), dir=None, threshold=0.0001)
            r = walkprobe.offline(ns)
            assert r["keys"] == 5 and r["moved"] == 5, r
            r2 = holdprobe.analyze([Path(f) for f in frames], 90, 0.0001)
            assert r2["changed_samples"] == 5, r2
            r3 = fps_probe.analyze([Path(f) for f in frames], 90, 0.0001, 250)
            assert r3["transitions"] == 5, r3
            return f"walk={r['moved']}/5 hold_changed={r2['changed_samples']}/5 fps={r3['transitions']}/5"

    def t_manifest():
        with tempfile.TemporaryDirectory() as td:
            d = Path(td)
            w, h, rgba = solid(16, 16)
            f1, f2 = d / "a.png", d / "b.png"
            encode_png_rgba(w, h, rgba, f1)
            encode_png_rgba(w, h, solid(16, 16, rect=(0, 0, 4, 4))[2], f2)
            idx = d / "manifest.json"
            r1 = manifest.add_files(idx, [str(f1), str(f2)], "t", "selftest", False)
            assert r1["added"] == 2, r1
            r2 = manifest.add_files(idx, [str(f1)], "t", "selftest", False)
            assert r2["added"] == 0 and r2["skipped"] == 1, r2
            vr = manifest.verify(idx)
            assert vr["pass"], vr
            return f"entries={r1['total']} verify=ok"

    def t_metrics_selftest():
        p = subprocess.run([sys.executable, str(root / "tools" / "metrics" / "dsh_metrics.py"), "--selftest"],
                           capture_output=True, text=True)
        assert p.returncode == 0, p.stdout[-500:] + p.stderr[-500:]
        assert "PASS" in p.stdout
        return "dsh_metrics selftest PASS"

    def t_verify_selftest():
        p = subprocess.run([sys.executable, "-B", str(root / "tools" / "verify" / "selftest.py")],
                           capture_output=True, text=True)
        assert p.returncode == 0, p.stdout[-800:] + p.stderr[-800:]
        assert "ALL OK" in p.stdout
        return "verify tools selftest ALL OK"

    def t_json():
        files = [root / "plugin.json", root / "templates" / "playtest.json",
                 ]
        files += sorted((root / "examples").glob("*.json"))
        checked = 0
        for f in files:
            if f.exists():
                json.loads(f.read_text(encoding="utf-8-sig"))
                checked += 1
        return f"parsed {checked} json files"

    def t_ps1():
        import shutil
        pwsh = shutil.which("powershell") or shutil.which("pwsh")
        if not pwsh:
            return "skipped (no powershell)"
        scripts = sorted(root.glob("scripts/**/*.ps1"))
        if not scripts:
            raise AssertionError("no .ps1 files found")
        for f in scripts:
            cmd = ["powershell", "-NoProfile", "-Command",
                   f"$e=$null; [System.Management.Automation.Language.Parser]::ParseFile('{f}',[ref]$null,[ref]$e) | Out-Null; if($e.Count){{$e|%{{$_.Message}}; exit 1}}"]
            p = subprocess.run(cmd, capture_output=True, text=True)
            assert p.returncode == 0, f"{f}: {p.stdout} {p.stderr}"
        return f"parsed {len(scripts)} ps1"

    check("png encode/decode/stats", t_png)
    check("frame diff", t_diff)
    check("crop_region", t_crop)
    check("probes offline analyzers", t_probes_offline)
    check("evidence manifest append/verify", t_manifest)
    check("dsh_metrics --selftest", t_metrics_selftest)
    check("verify tools selftest (v3.2)", t_verify_selftest)
    check("json parse (plugin/examples/templates)", t_json)
    check("powershell parse", t_ps1)

    failed = [r for r in RESULTS if not r[1]]
    print("\n" + f"== selftest: {len(RESULTS) - len(failed)}/{len(RESULTS)} passed ==")
    if failed:
        for name, _, detail in failed:
            print(f"  FAILED: {name}: {detail}")
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
