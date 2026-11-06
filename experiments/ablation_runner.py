import os, sys, json, csv, re, shutil, subprocess, hashlib, time
from pathlib import Path
from datetime import datetime

ROOT = os.environ.get("IST_ROOT", str(Path(__file__).resolve().parents[3]))
PY = os.environ.get("IST_PYTHON", sys.executable)
RUNNER = os.environ.get("IST_RUNNER", os.path.join(ROOT, r"_playtest_regress_dev\round78\run_probe_stream.py"))
APPDATA = os.environ.get("PAL98_APPDATA", os.path.join(os.environ.get("APPDATA",""), "Godot", "app_userdata", "PAL98 Godot (REA port)"))
SLOT1 = os.path.join(APPDATA, "pal_save_1.sav")
SLOT2 = os.path.join(APPDATA, "pal_save_2.sav")
SLOT2J = os.path.join(APPDATA, "pal_save_2.json")
BASE = os.environ.get("IST_ANCHOR_DIR", os.path.join(ROOT, r"_playtest_regress_dev\round78"))
IST = os.environ.get("IST_DIR", str(Path(__file__).resolve().parent))
AB = os.path.join(IST, "ablation")
RAW = os.path.join(AB, "raw")
os.makedirs(RAW, exist_ok=True)

NODES = {"R1":"slot2_scene207_qilin_anchor", "R3":"slot2_scene153_tower_inside_anchor",
         "R4":"slot2_scene253_prebattle_outside_anchor", "R6":"slot2_scene139_spider_anchor"}
CONDS = ["with_rules", "no_rules", "clear_context"]
SEEDS = [101, 202]

def sha(p):
    return hashlib.sha256(open(p,"rb").read()).hexdigest()

def run_one(node, cond, seed):
    s=os.path.join(BASE,NODES[node]+".sav"); j=os.path.join(BASE,NODES[node]+".json")
    shutil.copyfile(s,SLOT2)
    if os.path.isfile(j): shutil.copyfile(j,SLOT2J)
    rid=f"{node}_{cond}_seed{seed}"
    out=os.path.join(RAW,rid+".txt")
    cmd=[PY,RUNNER,"dev3exp",f"--expnode={node}",f"--expcond={cond}",f"--expseed={seed}"]
    t0=time.time()
    r=subprocess.run(cmd,capture_output=True,text=True,encoding="utf-8",errors="replace",timeout=300)
    elapsed=round(time.time()-t0,2)
    open(out,"w",encoding="utf-8").write("STDOUT\n"+r.stdout+"\nSTDERR\n"+r.stderr)
    rows=re.findall(r'^\[exp\] (\{.*\})\s*$',r.stdout,re.M)
    if not rows:
        return {"node":node,"condition":cond,"seed":seed,"success":False,"raw":out,"elapsed_s":elapsed,"error":"no [exp] output","exit":r.returncode}
    d=json.loads(rows[-1]);d["raw"]=out;d["elapsed_s"]=elapsed;d["exit"]=r.returncode
    return d

def main():
    bak_sav=os.path.join(AB,"_anchor.sav");bak_json=os.path.join(AB,"_slot2_backup.json")
    shutil.copyfile(SLOT2,bak_sav);shutil.copyfile(SLOT2J,bak_json)
    s1b=sha(SLOT1); rows=[]
    try:
        for node in ["R1","R3","R4","R6"]:
            for cond in CONDS:
                for seed in SEEDS:
                    print("RUN",node,cond,seed,flush=True)
                    row=run_one(node,cond,seed);rows.append(row)
                    print(json.dumps(row,ensure_ascii=False)[:240],flush=True)
    finally:
        shutil.copyfile(bak_sav,SLOT2);shutil.copyfile(bak_json,SLOT2J)
        os.remove(bak_sav);os.remove(bak_json)
    s1a=sha(SLOT1)
    keys=["node","condition","seed","start","target","start_scene","end_scene","end_pos","start_N","end_N",
          "success","steps","moved","invalid_moves","wrong_direction","repeated_failures","recovery_count","no_key",
          "shortest","path_deviation_abs","path_deviation_ratio","frames","time_ms","vm_active","battle","dialog","elapsed_s","exit","raw","error"]
    with open(os.path.join(AB,"experience_ablation.csv"),"w",encoding="utf-8-sig",newline="") as f:
        w=csv.DictWriter(f,fieldnames=keys);w.writeheader()
        for r in rows:w.writerow({k:r.get(k) for k in keys})
    meta={"phase":"B_experience_ablation","code_head":"f9972eb9670e6eea0ad612bd687d43ccedd43e43",
          "slot1_before":s1b,"slot1_after":s1a,"slot2_restored_sha":sha(SLOT2),
          "runs":len(rows),"nodes":list(NODES.keys()),"conditions":CONDS,"seeds":SEEDS,
          "timestamp":datetime.now().isoformat()}
    open(os.path.join(AB,"ablation_meta.json"),"w",encoding="utf-8").write(json.dumps(meta,ensure_ascii=False,indent=2))
    print("WROTE",os.path.join(AB,"experience_ablation.csv"),"slot1_unchanged",s1b==s1a,"runs",len(rows),flush=True)

if __name__=="__main__":
    main()
