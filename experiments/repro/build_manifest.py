import os, sys, json, hashlib, platform
from pathlib import Path

ROOT = Path(os.environ.get("IST_REPRO_ROOT", str(Path(__file__).resolve().parents[4])))
IST = Path(os.environ.get("IST_DIR", str(Path(__file__).resolve().parents[1])))
OUT = Path(os.environ.get("IST_MANIFEST_OUT", str(Path(__file__).resolve().parent / "manifest.json")))
HARNESS = [
    ROOT / "_playtest_regress_dev/round78/dev3_probe.py",
    ROOT / "_playtest_regress_dev/round78/run_probe_stream.py",
    ROOT / "_playtest_regress_dev/round78/run_paper_eval_guarded.py",
    ROOT / "_playtest_regress_dev/tools_backup/r73_verify.gd",
    IST / "ist_runner.py",
    IST / "ablation_runner.py",
    IST / "postprocess_a.py",
    IST / "build_manifest.py",
]

def sha(p: Path) -> str:
    h = hashlib.sha256()
    with open(p, "rb") as f:
        for b in iter(lambda: f.read(1 << 20), b""):
            h.update(b)
    return h.hexdigest()

def add_file(rows, p: Path):
    try:
        rel = str(p.relative_to(ROOT))
    except ValueError:
        rel = str(p)
    rows.append({"path": rel, "sha256": sha(p), "bytes": p.stat().st_size})

files = []
for p in sorted(IST.rglob("*")):
    if p.is_file() and p.name not in ("manifest.json",):
        add_file(files, p)
for p in HARNESS:
    if p.is_file():
        add_file(files, p)
# dedupe by path
uniq = {}
for r in files:
    uniq[r["path"]] = r
files = sorted(uniq.values(), key=lambda r: r["path"])
manifest = {
    "generated_at": "2026-11-06",
    "code_head": "f9972eb9670e6eea0ad612bd687d43ccedd43e43",
    "build": "R311",
    "godot": "4.7.2.stable.mono.official",
    "python": sys.version.split()[0],
    "platform": platform.platform(),
    "scope": "IST paper artifacts + test harness; commercial game data/assets are deliberately excluded",
    "excluded": ["proj/ game assets/data", "PAL98 commercial resources", "user slot files"],
    "files": files,
    "count": len(files),
}
OUT.write_text(json.dumps(manifest, ensure_ascii=False, indent=2), encoding="utf-8")
print("wrote", OUT, "files", len(files))
