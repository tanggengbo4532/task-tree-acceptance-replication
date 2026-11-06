import csv, json, os, re, statistics
from collections import defaultdict

IST = os.environ.get("IST_DIR", os.path.dirname(os.path.abspath(__file__)))
META_PATH = os.path.join(IST, "preflight_meta.json")
try:
    _META = json.load(open(META_PATH, encoding="utf-8"))
except Exception:
    _META = {}

def _guard_from_raw(path):
    try:
        txt = open(path, encoding="utf-8", errors="replace").read()
    except Exception:
        txt = ""
    before = re.search(r"\[HARNESS-GUARD\] slot1 before=([0-9a-fA-F]+)", txt)
    after = re.search(r"\[HARNESS-GUARD\] slot1 after=([0-9a-fA-F]+)", txt)
    b = before.group(1).lower() if before else str(_META.get("slot1_before","")).lower()
    a = after.group(1).lower() if after else str(_META.get("slot1_after","")).lower()
    return b, a

FINAL = ["R1", "R2", "R3", "R4", "R5E", "R6"]
CAT = {"R1": "complex", "R2": "simple", "R3": "simple", "R4": "simple", "R5E": "simple", "R6": "detour"}
TARGET_LABEL = {
    "R1": "evt3461(464,280) -> scene206",
    "R2": "evt3442(864,1280) -> A46 dialogue/VM (same scene)",
    "R3": "A39(960,1056) -> scene155",
    "R4": "A49 point(1680,1720) -> scene253",
    "R5E": "evt4365(896,1152) -> scene255",
    "R6": "evt2342(1376,1360) -> trigger/battle (no win required)",
}

def b(v):
    return str(v).lower() in ("true", "1")

def num(v, d=0.0):
    try: return float(v)
    except: return d

rows = list(csv.DictReader(open(os.path.join(IST, "hud_eval_runs.csv"), encoding="utf-8-sig")))
out = []
for r in rows:
    r["category"] = CAT.get(r["route"], "")
    r["target_label"] = TARGET_LABEL.get(r["route"], "")
    bfs = int(num(r.get("shortest"), -1))
    n0 = int(num(r.get("start_N"), 0))
    baseline = n0 if n0 > 0 else bfs
    source = "HUD N0" if n0 > 0 else ("BFS" if bfs >= 0 else "N/A")
    ok = b(r["success"])
    steps = int(num(r["steps"]))
    r["shortest_bfs"] = bfs
    r["path_baseline"] = baseline
    r["path_baseline_source"] = source
    r["path_deviation_abs"] = (steps - baseline) if ok and baseline >= 0 else -1
    r["path_deviation_ratio"] = (round(steps / baseline, 4) if ok and baseline > 0 else -1.0)
    gb, ga = _guard_from_raw(r.get("raw",""))
    r["guard_slot1_before"] = gb
    r["guard_slot1_after"] = ga
    out.append(r)

keys = ["route","category","variant","seed","target_label","start","target","start_scene","end_scene","end_pos",
        "start_N","end_N","success","steps","moved","invalid_moves","wrong_direction","recovery_count","no_key",
        "shortest_bfs","path_baseline","path_baseline_source","path_deviation_abs","path_deviation_ratio",
        "frames","time_ms","vm_active","battle","dialog","mis_trigger","exit","guard_slot1_before","guard_slot1_after","raw"]
with open(os.path.join(IST, "hud_eval_runs.csv"), "w", encoding="utf-8-sig", newline="") as f:
    w = csv.DictWriter(f, fieldnames=keys); w.writeheader()
    for r in out: w.writerow({k: r.get(k) for k in keys})

# preflight final C (seed101) from existing preflight results
pre = [r for r in csv.DictReader(open(os.path.join(IST, "preflight_runs.csv"), encoding="utf-8-sig")) if r["route"] in FINAL]
with open(os.path.join(IST, "preflight_final.csv"), "w", encoding="utf-8-sig", newline="") as f:
    w = csv.DictWriter(f, fieldnames=list(pre[0].keys()) if pre else ["route"]); w.writeheader()
    for r in pre: w.writerow(r)

# summaries
by = defaultdict(list)
for r in out: by[(r["route"], r["variant"])].append(r)
summary = {}
for route in FINAL:
    for v in ["A","B","C"]:
        rs = by[(route,v)]
        if not rs: continue
        def vals(k): return [num(r.get(k),-1) for r in rs]
        success = [1 if b(r["success"]) else 0 for r in rs]
        summary[f"{route}_{v}"] = {
            "route":route,"variant":v,"n":len(rs),"success_count":sum(success),"success_rate":round(sum(success)/len(success),3),
            "steps_mean":round(statistics.mean(vals("steps")),2),
            "steps_std":round(statistics.pstdev(vals("steps")),2),
            "invalid_mean":round(statistics.mean(vals("invalid_moves")),2),
            "wrong_mean":round(statistics.mean(vals("wrong_direction")),2),
            "recovery_mean":round(statistics.mean(vals("recovery_count")),2),
            "frames_mean":round(statistics.mean(vals("frames")),1),
            "path_dev_mean":round(statistics.mean([x for x in vals("path_deviation_abs") if x != -1]),2) if any(x!=-1 for x in vals("path_deviation_abs")) else None,
            "deterministic_identical": len(set((r["steps"],r["invalid_moves"],r["wrong_direction"],r["success"]) for r in rs)) == 1,
        }
json.dump(summary, open(os.path.join(IST, "hud_eval_summary.json"),"w",encoding="utf-8"), ensure_ascii=False, indent=2)
print("full rows",len(out),"preflight",len(pre))
for route in FINAL:
    print(route,[summary.get(f"{route}_{v}") for v in ["A","B","C"]])
