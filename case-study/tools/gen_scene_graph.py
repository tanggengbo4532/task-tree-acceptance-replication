# -*- coding: utf-8 -*-
"""生成场景转移图 data/scene_graph.json（供自动长跑做“最短路径到未访问场景”导航）。

规则：对每个场景收集 onEnter/onTeleport 脚本与所有事件触发/自动脚本中**可达**的 0x0059 目标。
可达性沿线性顺序 + 条件/跳转/调用类操作码的跳转目标遍历（与 script_vm 的跳转语义近似）。
"""
import json
import os
import struct
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import mkf

DATA_DIR = None
for cand in (
    r"<LOCAL_PATH>",
    r"<LOCAL_PATH>",
):
    if os.path.isdir(cand):
        DATA_DIR = cand
        break
assert DATA_DIR, "data dir not found"

Sss = mkf.MKF(os.path.join(DATA_DIR, "Sss.mkf"))
scenes_raw = Sss.raw(1)
scripts = Sss.raw(4)
events = Sss.raw(0)
scenes = [struct.unpack_from("<4H", scenes_raw, i * 8) for i in range(len(scenes_raw) // 8)]
n = len(scripts) // 8

JUMP_OPS = {
    0x0002, 0x0003, 0x0004, 0x0006, 0x000A, 0x0016, 0x001A, 0x0064, 0x0066,
    0x0067, 0x0068, 0x0069, 0x006A, 0x006B, 0x0078, 0x008A, 0x0091, 0x009C,
    0x009E, 0x00A2,
}


def op(e):
    return struct.unpack_from("<4H", scripts, e * 8)


def walk(start):
    seen = set()
    work = [start]
    targets = set()
    while work:
        e = work.pop()
        if e <= 0 or e >= n or e in seen:
            continue
        seen.add(e)
        q = op(e)
        code = q[0]
        if code == 0x0059 and 0 < q[1] <= 295:
            targets.add(q[1])
        if code == 0x0000:
            continue
        work.append(e + 1)
        if code in JUMP_OPS:
            for t in (q[1], q[2], q[3]):
                if 1 <= t < n:
                    work.append(t)
    return targets


graph = {}
for s in range(1, 295):
    start, end = scenes[s - 1][3], scenes[s][3]
    tg = set()
    for idx in (1, 2):
        if scenes[s - 1][idx]:
            tg |= walk(scenes[s - 1][idx])
    for i in range(start, end):
        o = struct.unpack_from("<16H", events, i * 32)
        for f in (4, 5):
            if o[f]:
                tg |= walk(o[f])
    graph[s] = sorted(tg)

out = r"<LOCAL_PATH>"
os.makedirs(os.path.dirname(out), exist_ok=True)
with open(out, "w", encoding="utf-8") as f:
    json.dump(graph, f, ensure_ascii=False, separators=(",", ":"))
print("scene graph written:", out, "scenes:", len(graph))
print("39 ->", graph[39], " 37 ->", graph[37], " 36 ->", graph[36])
