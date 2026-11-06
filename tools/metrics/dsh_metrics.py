#!/usr/bin/env python3
"""dsh_metrics - estimate per-window token / time share across DSH agent sessions.

Model (same as the reference analysis in the source project):
  window = [start, end] derived from evidence-dir earliest file mtime -> report mtime
           (or --start/--end explicitly)
  for each DSH session (Lead/developer/tester/recorder):
      steps_in_window = count of "step/start" events with time in window
      share = steps_in_window / total_steps
      attributed tokens = share * session totals (uncachedInput/output/cacheRead)
This is an *estimate*: DSH stores cumulative totals per session, not per-node usage.
Windows may overlap when agents work concurrently; minutes are wall-clock.

CLI:
  python dsh_metrics.py --selftest
  python dsh_metrics.py --evidence-dir E:/proj/_playtest_round76 --report E:/proj/_playtest_round76/tester-report.md --out md
  python dsh_metrics.py --start 2026-10-26T13:00 --end 2026-10-26T14:30 --jsonl-dir _metrics --sessions-dir "%USERPROFILE%/.dsh/storages/session_projcache/sessions"
"""
from __future__ import annotations

import argparse
import csv
import glob
import json
import os
import tempfile
import time
from datetime import datetime
from pathlib import Path

DEFAULT_SESSIONS = Path(os.environ.get("USERPROFILE", str(Path.home()))) / ".dsh" / "storages" / "session_projcache" / "sessions"


def parse_dt(text: str) -> datetime:
    text = text.strip().replace("Z", "+00:00")
    for fmt in ("%Y-%m-%dT%H:%M:%S.%f%z", "%Y-%m-%dT%H:%M:%S%z", "%Y-%m-%dT%H:%M:%S",
                "%Y-%m-%d %H:%M:%S", "%Y-%m-%d"):
        try:
            dt = datetime.strptime(text, fmt)
            return dt.replace(tzinfo=None) if dt.tzinfo is None else dt.astimezone().replace(tzinfo=None)
        except ValueError:
            continue
    raise ValueError(f"cannot parse datetime: {text}")


def iso(ts: float) -> str:
    return datetime.fromtimestamp(ts).strftime("%Y-%m-%dT%H:%M:%S")


def derive_window(evidence_dir: str = "", report: str = "") -> tuple[datetime, datetime]:
    if not evidence_dir:
        raise ValueError("need --evidence-dir or --start/--end")
    files = [Path(p) for p in glob.glob(os.path.join(evidence_dir, "**", "*"), recursive=True) if os.path.isfile(p)]
    if not files:
        raise ValueError(f"no files under evidence dir: {evidence_dir}")
    start = min(f.stat().st_mtime for f in files)
    end = Path(report).stat().st_mtime if report and Path(report).exists() else max(f.stat().st_mtime for f in files)
    return datetime.fromtimestamp(start), datetime.fromtimestamp(end)


def read_session_totals(session_json: Path) -> dict:
    try:
        txt = session_json.read_text(encoding="utf-8-sig").replace("\ufeff", "")
        j = json.loads(txt)
        t = ((j.get("record") or {}).get("rows") or {}).get("tokenUsage", {}).get("val", {}).get("totals") or {}
        return {
            "in": int(t.get("uncachedInputTokens", t.get("inputTokens", 0)) or 0),
            "out": int(t.get("outputTokens", 0) or 0),
            "cache": int(t.get("cacheReadTokens", 0) or 0),
        }
    except Exception:
        return {}


def read_step_times(jsonl: Path) -> list[datetime]:
    times = []
    if not jsonl.exists():
        return times
    for line in jsonl.read_text(encoding="utf-8-sig", errors="ignore").splitlines():
        line = line.strip()
        if not line:
            continue
        try:
            o = json.loads(line)
        except Exception:
            continue
        if o.get("type") == "step/start" and o.get("time"):
            try:
                times.append(parse_dt(str(o["time"])))
            except ValueError:
                pass
    return times


def estimate(sessions_dir: Path, jsonl_dir: Path, start: datetime, end: datetime, session_ids: list[str] | None = None) -> dict:
    ids = session_ids or sorted(p.stem for p in Path(sessions_dir).glob("*.json"))
    rows = []
    for sid in ids:
        totals = read_session_totals(Path(sessions_dir) / f"{sid}.json")
        steps = read_step_times(Path(jsonl_dir) / f"{sid}.jsonl")
        if not totals or not steps:
            continue
        inside = [t for t in steps if start <= t <= end]
        share = len(inside) / len(steps) if steps else 0.0
        rows.append({
            "session": sid, "total_steps": len(steps), "window_steps": len(inside),
            "share": round(share, 4),
            "in": round(totals["in"] * share), "out": round(totals["out"] * share),
            "cache": round(totals["cache"] * share),
            "total": round((totals["in"] + totals["out"] + totals["cache"]) * share),
        })
    totals = {k: sum(r[k] for r in rows) for k in ("in", "out", "cache", "total", "window_steps")}
    minutes = (end - start).total_seconds() / 60.0
    return {"window": {"start": start.strftime("%Y-%m-%dT%H:%M:%S"), "end": end.strftime("%Y-%m-%dT%H:%M:%S"),
                       "minutes": round(minutes, 2)},
            "sessions": rows, "totals": totals,
            "method": "share = window step/start count / session total steps; tokens = share * session cumulative totals (estimate)"}


def render_md(res: dict) -> str:
    w = res["window"]
    lines = [f"# DSH window metrics (estimate)", "",
             f"- window: {w['start']} -> {w['end']} ({w['minutes']} min)",
             f"- method: {res['method']}", "",
             "| session | window steps | total steps | share | in | out | cache | total |",
             "|---|---|---|---|---|---|---|---|"]
    for r in res["sessions"]:
        lines.append(f"| {r['session']} | {r['window_steps']} | {r['total_steps']} | {r['share']:.2%} | "
                     f"{r['in']} | {r['out']} | {r['cache']} | {r['total']} |")
    t = res["totals"]
    lines.append(f"| **TOTAL** | {t['window_steps']} | | 100% | {t['in']} | {t['out']} | {t['cache']} | {t['total']} |")
    return "\n".join(lines) + "\n"


def selftest() -> int:
    with tempfile.TemporaryDirectory() as td:
        root = Path(td)
        sess = root / "sessions"; jsonl = root / "jsonl"
        sess.mkdir(); jsonl.mkdir()
        sid = "session-test"
        (sess / f"{sid}.json").write_text(json.dumps({"record": {"rows": {"tokenUsage": {"val": {"totals": {
            "uncachedInputTokens": 1000, "outputTokens": 500, "cacheReadTokens": 2000}}}}}}), encoding="utf-8")
        steps = [{"type": "step/start", "time": "2026-01-01T10:00:00"},
                 {"type": "step/start", "time": "2026-01-01T10:10:00"},
                 {"type": "step/start", "time": "2026-01-01T12:00:00"},
                 {"type": "step/start", "time": "2026-01-01T12:10:00"}]
        (jsonl / f"{sid}.jsonl").write_text("\n".join(json.dumps(s) for s in steps), encoding="utf-8")
        res = estimate(sess, jsonl, parse_dt("2026-01-01T10:00:00"), parse_dt("2026-01-01T10:30:00"))
        ok = (res["totals"]["window_steps"] == 2 and round(res["sessions"][0]["share"], 2) == 0.5
              and res["sessions"][0]["in"] == 500 and res["sessions"][0]["out"] == 250
              and res["sessions"][0]["cache"] == 1000)
        print(json.dumps(res, ensure_ascii=False, indent=2))
        print("[dsh_metrics] selftest", "PASS" if ok else "FAIL")
        return 0 if ok else 1


def main() -> None:
    ap = argparse.ArgumentParser(description="DSH session token/time share estimate")
    ap.add_argument("--sessions-dir", default=str(DEFAULT_SESSIONS))
    ap.add_argument("--jsonl-dir", default="")
    ap.add_argument("--evidence-dir", default="")
    ap.add_argument("--report", default="")
    ap.add_argument("--start", default="")
    ap.add_argument("--end", default="")
    ap.add_argument("--session-ids", default="")
    ap.add_argument("--out", choices=["md", "json", "csv"], default="md")
    ap.add_argument("--out-file", default="")
    ap.add_argument("--selftest", action="store_true")
    args = ap.parse_args()

    if args.selftest:
        raise SystemExit(selftest())

    if args.start and args.end:
        start, end = parse_dt(args.start), parse_dt(args.end)
    else:
        start, end = derive_window(args.evidence_dir, args.report)
    jsonl_dir = Path(args.jsonl_dir) if args.jsonl_dir else Path.cwd()
    ids = [s for s in args.session_ids.replace(",", " ").split() if s] or None
    res = estimate(Path(args.sessions_dir), jsonl_dir, start, end, ids)
    res["window"]["source"] = ("explicit" if args.start and args.end else "evidence-dir")
    if args.out == "json":
        text = json.dumps(res, ensure_ascii=False, indent=2)
    elif args.out == "csv":
        import io
        buf = io.StringIO()
        w = csv.writer(buf)
        w.writerow(["session", "window_steps", "total_steps", "share", "in", "out", "cache", "total"])
        for r in res["sessions"]:
            w.writerow([r["session"], r["window_steps"], r["total_steps"], r["share"], r["in"], r["out"], r["cache"], r["total"]])
        w.writerow(["TOTAL", res["totals"]["window_steps"], "", 1.0, res["totals"]["in"], res["totals"]["out"],
                    res["totals"]["cache"], res["totals"]["total"]])
        text = buf.getvalue()
    else:
        text = render_md(res)
    print(text)
    if args.out_file:
        Path(args.out_file).write_text(text, encoding="utf-8")
        print(f"[dsh_metrics] written: {Path(args.out_file).resolve()}")


if __name__ == "__main__":
    main()
