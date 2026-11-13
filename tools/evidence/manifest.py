#!/usr/bin/env python3
"""manifest - append-only evidence manifest for playtest rounds.

Records every evidence file with sha256/size/mtime/tag/round, and never overwrites
an existing manifest: new entries are appended (duplicate sha256 rejected unless
--allow-duplicate). Verification recomputes hashes and reports drift.

CLI:
  python manifest.py init --index evidence/manifest.json --round round76
  python manifest.py add  --index evidence/manifest.json --files evidence/shots/*.png --tag walk --round round76
  python manifest.py add  --index evidence/manifest.json --dir evidence/shots --tag walk
  python manifest.py verify --index evidence/manifest.json
  python manifest.py list  --index evidence/manifest.json
"""
from __future__ import annotations

import argparse
import hashlib
import json
import time
from pathlib import Path


def sha256(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as fh:
        for chunk in iter(lambda: fh.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def load(index: Path) -> dict:
    if index.exists():
        return json.loads(index.read_text(encoding="utf-8-sig"))
    return {"schema": 1, "created": time.strftime("%Y-%m-%dT%H:%M:%S"), "entries": []}


def save(index: Path, data: dict) -> None:
    index.parent.mkdir(parents=True, exist_ok=True)
    tmp = index.with_suffix(index.suffix + ".tmp")
    tmp.write_text(json.dumps(data, ensure_ascii=False, indent=2), encoding="utf-8")
    tmp.replace(index)


def add_files(index: Path, files, tag: str, round_name: str, allow_duplicate: bool) -> dict:
    data = load(index)
    known = {e["sha256"] for e in data["entries"] if "sha256" in e}
    added, skipped = [], []
    for f in files:
        p = Path(f).resolve()
        if not p.is_file():
            continue
        digest = sha256(p)
        st = p.stat()
        if digest in known and not allow_duplicate:
            skipped.append({"path": str(p), "reason": "duplicate sha256"})
            continue
        entry = {"path": str(p), "sha256": digest, "size": st.st_size,
                 "mtime": time.strftime("%Y-%m-%dT%H:%M:%S", time.localtime(st.st_mtime)),
                 "tag": tag, "round": round_name,
                 "added": time.strftime("%Y-%m-%dT%H:%M:%S")}
        data["entries"].append(entry)
        known.add(digest)
        added.append(entry)
    data["updated"] = time.strftime("%Y-%m-%dT%H:%M:%S")
    if added:
        save(index, data)
    return {"index": str(index.resolve()), "added": len(added), "skipped": len(skipped),
            "entries": added, "skipped_entries": skipped, "total": len(data["entries"])}


def verify(index: Path) -> dict:
    data = load(index)
    missing, drift, ok = [], [], 0
    for e in data["entries"]:
        p = Path(e["path"])
        if not p.is_file():
            missing.append(e["path"])
            continue
        if sha256(p) != e.get("sha256"):
            drift.append(e["path"])
        else:
            ok += 1
    return {"index": str(index.resolve()), "entries": len(data["entries"]), "ok": ok,
            "missing": missing, "drift": drift, "pass": not missing and not drift}


def main() -> None:
    ap = argparse.ArgumentParser(description="append-only evidence manifest")
    sub = ap.add_subparsers(dest="cmd", required=True)
    p = sub.add_parser("init"); p.add_argument("--index", required=True); p.add_argument("--round", default="")
    p = sub.add_parser("add")
    p.add_argument("--index", required=True)
    p.add_argument("--files", nargs="*", default=[])
    p.add_argument("--dir", default="")
    p.add_argument("--tag", default="")
    p.add_argument("--round", default="")
    p.add_argument("--allow-duplicate", action="store_true")
    p = sub.add_parser("verify"); p.add_argument("--index", required=True)
    p = sub.add_parser("list"); p.add_argument("--index", required=True)
    args = ap.parse_args()

    index = Path(args.index)
    if args.cmd == "init":
        data = load(index)
        if args.round:
            data["round"] = args.round
        save(index, data)
        print(json.dumps({"index": str(index.resolve()), "entries": len(data["entries"]), "created": data["created"]}))
    elif args.cmd == "add":
        files = list(args.files)
        if args.dir:
            files += [str(f) for f in sorted(Path(args.dir).iterdir()) if f.is_file()]
        if not files:
            raise SystemExit("no files: use --files or --dir")
        res = add_files(index, files, args.tag, args.round, args.allow_duplicate)
        print(json.dumps(res, ensure_ascii=False, indent=2))
    elif args.cmd == "verify":
        res = verify(index)
        print(json.dumps(res, ensure_ascii=False, indent=2))
        raise SystemExit(0 if res["pass"] else 2)
    elif args.cmd == "list":
        data = load(index)
        for e in data["entries"]:
            print(f"{e.get('round','')}\t{e.get('tag','')}\t{e['sha256'][:12]}\t{e['size']}\t{e['path']}")


if __name__ == "__main__":
    main()
