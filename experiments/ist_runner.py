import os, sys, json, csv, re, shutil, subprocess, hashlib, time
from datetime import datetime
from pathlib import Path

# F8: path-parameterized, no hard-coded drive letters. Override via env if needed.
ROOT = os.environ.get("IST_ROOT", str(Path(__file__).resolve().parents[3]))
PY = os.environ.get("IST_PYTHON", sys.executable)
RUNNER = os.environ.get("IST_RUNNER", os.path.join(ROOT, r"_playtest_regress_dev\round78\run_probe_stream.py"))
APPDATA = os.environ.get("PAL98_APPDATA", os.path.join(os.environ.get("APPDATA", ""), "Godot", "app_userdata", "PAL98 Godot (REA port)"))
SLOT1 = os.path.join(APPDATA, "pal_save_1.sav")
SLOT2 = os.path.join(APPDATA, "pal_save_2.sav")
SLOT2J = os.path.join(APPDATA, "pal_save_2.json")
BASE = os.environ.get("IST_ANCHOR_DIR", os.path.join(ROOT, r"_playtest_regress_dev\round78"))
IST = os.environ.get("IST_DIR", str(Path(__file__).resolve().parent))
RAW = os.path.join(IST, "raw")
os.makedirs(RAW, exist_ok=True)

FINAL_ROUTES = ["R1", "R2", "R3", "R4", "R5E", "R6"]
ROUTES = {
    "R1": {"anchor": "slot2_scene207_qilin_anchor", "category": "complex"},
    "R2": {"anchor": "slot2_scene206_a46_entry_anchor", "category": "simple"},
    "R3": {"anchor": "slot2_scene153_tower_inside_anchor", "category": "simple"},
    "R4": {"anchor": "slot2_scene253_prebattle_outside_anchor", "category": "simple"},
    "R5": {"anchor": "slot2_scene247_nanzhao_anchor", "category": "complex"},
    "R6": {"anchor": "slot2_scene139_spider_anchor", "category": "detour"},
    "R5A": {"anchor": "slot2_scene185_forest_anchor", "category": "complex"},
    "R5B": {"anchor": "slot2_scene188_forest_gate_anchor", "category": "detour"},
    "R5C": {"anchor": "slot2_scene188_door_anchor", "category": "detour"},
    "R5D": {"anchor": "slot2_scene178_miao_anchor", "category": "simple"},
    "R5E": {"anchor": "slot2_scene247_beforepalace_anchor", "category": "simple"},
}

def sha(p):
    return hashlib.sha256(open(p, "rb").read()).hexdigest()

def restore_slot2(bak_sav, bak_json):
    shutil.copyfile(bak_sav, SLOT2)
    shutil.copyfile(bak_json, SLOT2J)

def copy_anchor(name):
    s = os.path.join(BASE, name + ".sav")
    j = os.path.join(BASE, name + ".json")
    if not os.path.isfile(s):
        raise FileNotFoundError(s)
    shutil.copyfile(s, SLOT2)
    if os.path.isfile(j):
        shutil.copyfile(j, SLOT2J)

def run_one(route, variant, seed, phase):
    copy_anchor(ROUTES[route]["anchor"])
    rid = f"{phase}_{route}_{variant}_seed{seed}"
    out = os.path.join(RAW, rid + ".txt")
    cmd = [PY, RUNNER, "dev3ist", f"--evalroute={route}", f"--evalvariant={variant}", f"--evalseed={seed}"]
    t0 = time.time()
    r = subprocess.run(cmd, capture_output=True, text=True, encoding="utf-8", errors="replace", timeout=300)
    elapsed = time.time() - t0
    open(out, "w", encoding="utf-8").write(("STDOUT\n" + r.stdout + "\nSTDERR\n" + r.stderr))
    rows = re.findall(r'^\[ist\] (\{.*\})\s*$', r.stdout, re.M)
    if not rows:
        return {"route": route, "variant": variant, "seed": seed, "success": False,
                "raw": out, "elapsed_s": round(elapsed, 2), "error": "no [ist] output",
                "exit": r.returncode}
    d = json.loads(rows[-1])
    d["raw"] = out
    d["elapsed_s"] = round(elapsed, 2)
    d["exit"] = r.returncode
    return d

def main():
    # P0 guard: slot1 is read-only; record hash before/after. slot2 is restored at end.
    if not os.path.isfile(SLOT2) or not os.path.isfile(SLOT2J):
        raise SystemExit("slot2 missing")
    bak_sav = os.path.join(IST, "_anchor.sav")
    bak_json = os.path.join(IST, "_slot2_backup.json")
    shutil.copyfile(SLOT2, bak_sav); shutil.copyfile(SLOT2J, bak_json)
    s1_before = sha(SLOT1)
    rows = []
    try:
        for route in FINAL_ROUTES:
            for variant in ["A", "B", "C"]:
                for seed in [101, 202, 303]:
                    print("RUN full", route, variant, seed, flush=True)
                    row = run_one(route, variant, seed, "full")
                    rows.append(row)
                    print(json.dumps(row, ensure_ascii=False)[:240], flush=True)
    finally:
        restore_slot2(bak_sav, bak_json)
        os.remove(bak_sav); os.remove(bak_json)
    s1_after = sha(SLOT1)
    keys = ["route","variant","seed","start","target","start_scene","end_scene","end_pos","start_N","end_N",
            "success","steps","moved","invalid_moves","wrong_direction","recovery_count","no_key",
            "shortest","path_deviation_abs","path_deviation_ratio","frames","time_ms","elapsed_s",
            "vm_active","battle","dialog","mis_trigger","exit","raw","error"]
    out_csv = os.path.join(IST, "hud_eval_runs.csv")
    with open(out_csv, "w", encoding="utf-8-sig", newline="") as f:
        w = csv.DictWriter(f, fieldnames=keys); w.writeheader()
        for row in rows: w.writerow({k: row.get(k) for k in keys})
    meta = {"phase":"full","code_head":"f9972eb9670e6eea0ad612bd687d43ccedd43e43",
            "slot1_before":s1_before,"slot1_after":s1_after,
            "slot2_restored_sha":sha(SLOT2),"timestamp":datetime.now().isoformat()}
    open(os.path.join(IST, "preflight_meta.json"), "w", encoding="utf-8").write(json.dumps(meta, ensure_ascii=False, indent=2))
    print("WROTE", out_csv, "slot1_unchanged", s1_before == s1_after, flush=True)

if __name__ == "__main__":
    main()
