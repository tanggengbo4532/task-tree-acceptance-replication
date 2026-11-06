# -*- coding: utf-8 -*-
"""
scan_opcodes.py -- 从 Sss.mkf 块 4 静态扫描事件脚本操作码频次.

用途:
  1) 统计全部 43557 条 SCRIPTENTRY 里实际出现的 wOperation 频次(执行权重近似=条数);
  2) 从"前 N 个场景(默认 100)的 onEnter / onTeleport 脚本 + 这些场景事件对象的
     触发/自动脚本"出发做可达性分析, 统计真正会被执行到的 opcode 频次;
  3) 与 pal/script_vm.gd 的已实现清单比对, 输出覆盖率(种类覆盖率 + 执行频次覆盖率),
     并给出"未实现按频次排序"的优先级列表.

可达性依据 sdlpal script.c:
  PAL_RunTriggerScript 的 0x0000/0x0001 结束, 0x0002 把下一入口设为 op0,
  0x0003/0x0006/0x000A/0x001E/0x0020/0x0038/0x0058/0x005D/0x005E/0x0061/
  0x0064/0x0068/0x0074/0x0079/0x0081/0x0083/0x0084/0x0086/0x0091/0x0094/
  0x0095/0x009C/0x009E 为条件跳转, 0x0004 为子脚本调用, 0x0007 战斗有
  op1(lost)/op2(fled) 两个分支, 0x00A2 为向前随机跳.
  跳转目标一律视为新的脚本入口(与 sdlpal "entry" 语义一致).

输出: _rea_runtime/out/opcodes.json

用法:
  python tools/scan_opcodes.py [--scenes 100] [--out <path>]
"""
import json
import os
import struct
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import mkf  # noqa: E402

DATA_DIR = r'<LOCAL_PATH>'
OUT_DIR = r'<LOCAL_PATH>'

# 脚本块: Sss.mkf 块 4, 每条 SCRIPTENTRY = wOperation + 3×WORD, 共 43557 条
SCRIPT_CHUNK = 4
SCRIPT_COUNT = 43557
EVENT_COUNT = 5077
SCENE_COUNT = 295

# 脚本入口结束/分支语义 (依据 sdlpal script.c PAL_RunTriggerScript / PAL_InterpretInstruction)
STOP_OPS = {0x0000, 0x0001, 0x004E, 0x00A0}
# 跳转: opcode -> (操作数下标, "entry"=跳到 op 值作为入口 / "offset"=向前跳 op 个入口)
JUMP_OPS = {
    0x0003: (0, 'entry'),   # 无条件跳转
    0x0006: (1, 'entry'),   # 百分比跳转
    0x000A: (0, 'entry'),   # 是否选择(选"否"跳)
    0x001E: (1, 'entry'),   # 金钱不足跳
    0x0020: (2, 'entry'),   # 物品不足跳
    0x0038: (0, 'entry'),   # 离场脚本失败跳
    0x0058: (2, 'entry'),   # 指定物品数量不足跳
    0x005D: (1, 'entry'),   # 没有该毒跳
    0x005E: (1, 'entry'),   # 敌人没有该毒跳
    0x0061: (0, 'entry'),   # 未中毒跳
    0x0064: (1, 'entry'),   # 敌人 HP 超过百分比跳
    0x0068: (0, 'entry'),   # 敌人回合跳
    0x0074: (0, 'entry'),   # 不满血跳
    0x0079: (1, 'entry'),   # 指定角色在队伍跳
    0x0081: (2, 'entry'),   # 未面向事件对象跳
    0x0083: (2, 'entry'),   # 事件对象不在范围跳
    0x0084: (2, 'entry'),   # 放置物品为事件对象失败跳
    0x0086: (2, 'entry'),   # 未装备指定物品跳
    0x0091: (0, 'entry'),   # 不是同类第一个敌人跳
    0x0094: (2, 'entry'),   # 事件对象状态相等跳
    0x0095: (1, 'entry'),   # 当前场景相等跳
    0x009C: (1, 'entry'),   # 敌人分裂失败跳
    0x009E: (2, 'entry'),   # 敌人召唤失败跳
    0x00A2: (0, 'offset'),  # 向前随机跳 0..op0-1
}
# 0x0002: fEnded 且下一入口 = op0; 0x0004: 调用子脚本 op0; 0x0007: 战斗结果分支 op1/op2
CALL_OP = 0x0004
NEXT_ENTRY_OP = 0x0002
BATTLE_OP = 0x0007


def parse_scripts(sss_path):
    s = mkf.MKF(sss_path)
    raw = s.raw(SCRIPT_CHUNK)
    if len(raw) < SCRIPT_COUNT * 8:
        raise SystemExit('SSS 块 4 长度异常: %d' % len(raw))
    out = []
    for i in range(SCRIPT_COUNT):
        out.append(struct.unpack_from('<4H', raw, i * 8))
    return out


def parse_scenes(sss_path):
    s = mkf.MKF(sss_path)
    raw = s.raw(1)
    scenes = []
    for i in range(len(raw) // 8):
        scenes.append(dict(zip(
            ['wMapNum', 'wScriptOnEnter', 'wScriptOnTeleport', 'wEventObjectIndex'],
            struct.unpack_from('<4H', raw, i * 8))))
    return scenes


def parse_events(sss_path):
    s = mkf.MKF(sss_path)
    raw = s.raw(0)
    evs = []
    for i in range(len(raw) // 32):
        w = struct.unpack_from('<16H', raw, i * 32)
        evs.append({'wTriggerScript': w[4], 'wAutoScript': w[5]})
    return evs


def count_full(scripts):
    freq = {}
    for op, a0, a1, a2 in scripts:
        freq[op] = freq.get(op, 0) + 1
    return freq


def scene_event_range(scenes, scene_no_1based):
    """场景 n 的事件对象全局下标区间 [start, end) (0-based), 见 SSS-FORMAT.md."""
    start = 0
    if scene_no_1based - 2 >= 0:
        start = scenes[scene_no_1based - 2]['wEventObjectIndex']
    end = EVENT_COUNT
    if scene_no_1based - 1 < len(scenes):
        end = scenes[scene_no_1based - 1]['wEventObjectIndex']
    return start, end


def successors(scripts, e):
    """返回脚本地址 e 处的后继入口地址列表(与 sdlpal 语义一致)."""
    op, a0, a1, a2 = scripts[e]
    out = []
    if op in STOP_OPS:
        return out
    if op == NEXT_ENTRY_OP:
        if a0 != 0:
            out.append(a0)
        out.append(e + 1)          # idle 帧计数满足时继续下一行
        return out
    if op == CALL_OP:
        if a0 != 0:
            out.append(a0)
        out.append(e + 1)
        return out
    if op == BATTLE_OP:
        if a1 != 0:
            out.append(a1)
        if a2 != 0:
            out.append(a2)
        out.append(e + 1)
        return out
    if op in JUMP_OPS:
        idx, kind = JUMP_OPS[op]
        target = (a0, a1, a2)[idx]
        if kind == 'offset':
            for k in range(max(1, target)):
                out.append(e + 1 + k)
        elif target != 0:
            out.append(target)
        out.append(e + 1)
        return out
    out.append(e + 1)
    return out


def reachable(scripts, roots, limit_entries=SCRIPT_COUNT):
    """从 roots 出发做入口级可达性遍历, 返回 (可达入口集合, opcode 频次)."""
    seen = set()
    stack = [r for r in roots if 0 < r < limit_entries]
    freq = {}
    while stack:
        e = stack.pop()
        if e in seen or e <= 0 or e >= limit_entries:
            continue
        seen.add(e)
        op = scripts[e][0]
        freq[op] = freq.get(op, 0) + 1
        for n in successors(scripts, e):
            if 0 < n < limit_entries and n not in seen:
                stack.append(n)
    return seen, freq


# pal/script_vm.gd 已实现的操作码清单(与文件头注释表保持一致).
# 维护提示: 改 VM 时同步本表, 否则覆盖率报告会偏差.
#   full   = 完整移植(只依赖 PALState/PALText/PALAudio/World)
#   battle = 已写 case, 但语义依赖战斗系统(通过 vm.set_battle_proxy 注入; 无代理时按默认分支继续)
#   hook   = 已写 case, 但需要 World 尚未提供的界面/画面 hook(缺口见 script_vm.gd 文件头)
# 未列出的 opcode = 未实现(会走 script_note_unknown)。
IMPLEMENTED_FULL = {
    0x0000, 0x0001, 0x0002, 0x0003, 0x0004, 0x0005, 0x0006, 0x0007, 0x0008, 0x0009,
    0x000A, 0x000B, 0x000C, 0x000D, 0x000E, 0x000F,
    0x0010, 0x0011, 0x0012, 0x0013, 0x0014, 0x0015, 0x0016,
    0x0017, 0x0018, 0x0019, 0x001A, 0x001B, 0x001C, 0x001D, 0x001E, 0x001F,
    0x0020, 0x0022, 0x0023, 0x0024, 0x0025, 0x0026, 0x0027, 0x0029,
    0x002B, 0x002C, 0x002D, 0x002F,
    0x0030, 0x0031, 0x0034, 0x0036, 0x0038, 0x003B, 0x003C, 0x003D, 0x003E, 0x003F,
    0x0040, 0x0041, 0x0043, 0x0044, 0x0045, 0x0046, 0x0047, 0x0049, 0x004A, 0x004B,
    0x004C, 0x0050, 0x0051, 0x0052, 0x0053, 0x0054, 0x0055, 0x0056, 0x0057, 0x0058, 0x0059,
    0x005A, 0x005D, 0x005F, 0x0061, 0x0062, 0x0063, 0x0065, 0x006C, 0x006D, 0x006E,
    0x006F, 0x0070, 0x0071, 0x0073, 0x0074, 0x0075, 0x0077, 0x0078, 0x0079, 0x007A,
    0x007B, 0x007C, 0x007D, 0x007E, 0x007F, 0x0080, 0x0081, 0x0082, 0x0083, 0x0084,
    0x0085, 0x0086, 0x0087, 0x0088, 0x008B, 0x008D, 0x008E, 0x008F,
    0x0090, 0x0093, 0x0094, 0x0095, 0x0096, 0x0097, 0x0098, 0x0099, 0x009A, 0x009B,
    0x00A0, 0x00A1, 0x00A2, 0x00A3, 0x00A7, 0xFFFF,
}
IMPLEMENTED_BATTLE = {
    0x0021, 0x0028, 0x002A, 0x002E, 0x0033, 0x0039, 0x003A, 0x0042, 0x005B, 0x005C,
    0x005E, 0x0060, 0x0064, 0x0066, 0x0067, 0x0068, 0x0069, 0x006A, 0x006B, 0x0089,
    0x008A, 0x0091, 0x0092, 0x009C, 0x009E, 0x009F,
}
IMPLEMENTED_HOOK = {
    0x0035, 0x0037, 0x004D, 0x004E, 0x004F, 0x0076, 0x008C, 0x00A4, 0x00A5, 0x00A6,
}
IMPLEMENTED = IMPLEMENTED_FULL | IMPLEMENTED_BATTLE | IMPLEMENTED_HOOK


def impl_status(op):
    if op in IMPLEMENTED_FULL:
        return 'full'
    if op in IMPLEMENTED_BATTLE:
        return 'battle'
    if op in IMPLEMENTED_HOOK:
        return 'hook'
    return 'unknown'


def summarize(name, freq, total):
    items = sorted(freq.items(), key=lambda kv: (-kv[1], kv[0]))
    rows = []
    cum = 0
    for op, cnt in items:
        cum += cnt
        rows.append({
            'op': '0x%04X' % op,
            'opcode': op,
            'count': cnt,
            'pct': round(cnt * 100.0 / total, 4) if total else 0.0,
            'cum_pct': round(cum * 100.0 / total, 4) if total else 0.0,
            'implemented': op in IMPLEMENTED,
            'status': impl_status(op),
        })
    cover90 = []
    acc = 0
    for r in rows:
        if acc >= total * 0.9:
            break
        cover90.append(r['op'])
        acc += r['count']
    impl_cnt = sum(1 for r in rows if r['implemented'])
    impl_freq = sum(r['count'] for r in rows if r['implemented'])
    by_status = {'full': 0, 'battle': 0, 'hook': 0, 'unknown': 0}
    by_status_exec = {'full': 0, 'battle': 0, 'hook': 0, 'unknown': 0}
    for r in rows:
        by_status[r['status']] += 1
        by_status_exec[r['status']] += r['count']
    return {
        'opcode_kinds': len(rows),
        'executions': total,
        'implemented_kinds': impl_cnt,
        'implemented_exec_pct': round(impl_freq * 100.0 / total, 4) if total else 0.0,
        'kind_coverage_pct': round(impl_cnt * 100.0 / len(rows), 2) if rows else 0.0,
        'by_status': by_status,
        'by_status_exec_pct': {
            k: round(v * 100.0 / total, 4) if total else 0.0
            for k, v in by_status_exec.items()
        },
        'cover90_ops': cover90,
        'cover90_impl_pct': round(
            sum(r['count'] for r in rows if r['op'] in cover90 and r['implemented'])
            * 100.0 / max(1, sum(r['count'] for r in rows if r['op'] in cover90)), 2),
        'unimplemented_sorted': [r for r in rows if not r['implemented']],
        'sorted': rows,
    }


def main():
    scenes_n = 100
    out_path = os.path.join(OUT_DIR, 'opcodes.json')
    args = sys.argv[1:]
    for i, a in enumerate(args):
        if a == '--scenes' and i + 1 < len(args):
            scenes_n = int(args[i + 1])
        if a == '--out' and i + 1 < len(args):
            out_path = args[i + 1]

    sss = os.path.join(DATA_DIR, 'Sss.mkf')
    scripts = parse_scripts(sss)
    scenes = parse_scenes(sss)
    events = parse_events(sss)

    full_freq = count_full(scripts)

    # 根: 前 N 个场景的 onEnter/onTeleport + 这些场景事件对象的触发/自动脚本
    roots = []
    scenes_used = min(scenes_n, len(scenes))
    for sc in scenes[:scenes_used]:
        for k in ('wScriptOnEnter', 'wScriptOnTeleport'):
            if sc[k] != 0:
                roots.append(sc[k])
    for n in range(1, scenes_used + 1):
        s, e = scene_event_range(scenes, n)
        for i in range(max(0, s), min(e, len(events))):
            for k in ('wTriggerScript', 'wAutoScript'):
                if events[i][k] != 0:
                    roots.append(events[i][k])
    seen, reach_freq = reachable(scripts, roots)
    total_reach = sum(reach_freq.values()) or 1

    # ---- 静态合法性检查：跳转目标 / 场景号 / 事件对象号 ----
    bad_jumps = []
    bad_scenes = []
    bad_events = []
    inverted_ranges = []
    for e, (op, a0, a1, a2) in enumerate(scripts):
        if op in JUMP_OPS:
            idx, kind = JUMP_OPS[op]
            t = (a0, a1, a2)[idx]
            if kind == 'entry' and t != 0 and not (0 < t < SCRIPT_COUNT):
                bad_jumps.append([e, '0x%04X' % op, t])
            if kind == 'offset' and not (0 < e + t < SCRIPT_COUNT):
                bad_jumps.append([e, '0x%04X' % op, e + t])
        if op == 0x0007:
            for t in (a1, a2):
                if t != 0 and not (0 < t < SCRIPT_COUNT):
                    bad_jumps.append([e, '0x0007', t])
        if op == 0x0038 and a0 != 0 and not (0 < a0 < SCRIPT_COUNT):
            bad_jumps.append([e, '0x0038', a0])
        if op in (0x0059, 0x006D, 0x0099):
            t = a0
            if t not in (0, 0xFFFF) and not (1 <= t <= len(scenes)):
                bad_scenes.append([e, '0x%04X' % op, t])
        if op in (0x0012, 0x0013, 0x0016, 0x0024, 0x0025, 0x0040, 0x0049, 0x006F,
                  0x007D, 0x007E, 0x0081, 0x0083, 0x0084, 0x0094):
            if a0 != 0 and a0 != 0xFFFF and not (1 <= a0 <= EVENT_COUNT):
                bad_events.append([e, '0x%04X' % op, a0])
        if op == 0x009A:
            # sdlpal: for (i=op0; i<=op1; i++)，op0>op1 时循环不执行（数据里有 1 处这样的 no-op）
            if not (1 <= a0 <= EVENT_COUNT) or not (0 <= a1 <= EVENT_COUNT):
                bad_events.append([e, '0x009A', a0])
            elif a1 < a0:
                inverted_ranges.append([e, a0, a1])

    issues = {
        'bad_jump_targets': len(bad_jumps),
        'bad_scene_ids': len(bad_scenes),
        'bad_event_ids': len(bad_events),
        'inverted_event_ranges_noop': len(inverted_ranges),
        'bad_jump_samples': bad_jumps[:20],
        'bad_scene_samples': bad_scenes[:20],
        'bad_event_samples': bad_events[:20],
    }

    result = {
        'generated_by': 'tools/scan_opcodes.py',
        'source': sss,
        'chunk': 'Sss.mkf#4 SCRIPTENTRY[%d]' % SCRIPT_COUNT,
        'script_entries': len(scripts),
        'scene_count': len(scenes),
        'scenes_scanned': scenes_used,
        'reachable_roots': len(roots),
        'reachable_entries': len(seen),
        'implemented_ops_manifest': ['0x%04X' % x for x in sorted(IMPLEMENTED)],
        'full': summarize('full', full_freq, len(scripts)),
        'reachable': summarize('reachable', reach_freq, total_reach),
        'priority_by_reachable': [
            r for r in summarize('reachable', reach_freq, total_reach)['unimplemented_sorted']
        ][:40],
        'static_validation': issues,
    }

    os.makedirs(os.path.dirname(out_path), exist_ok=True)
    with open(out_path, 'w', encoding='utf-8') as f:
        json.dump(result, f, ensure_ascii=False, indent=1)
    print('wrote', out_path, os.path.getsize(out_path), 'bytes')

    for name in ('full', 'reachable'):
        s = result[name]
        print('[%s] opcode 种类=%d 执行数=%d 已实现种类=%d(%.1f%%) 执行覆盖=%.2f%%'
              % (name, s['opcode_kinds'], s['executions'], s['implemented_kinds'],
                 s['kind_coverage_pct'], s['implemented_exec_pct']))
        print('  状态分布 kinds=%s  exec%%=%s' % (s['by_status'], s['by_status_exec_pct']))
        print('  90%% 频次需 %d 种 opcode；这些 opcode 的实现率 %.1f%%'
              % (len(s['cover90_ops']), s['cover90_impl_pct']))
        print('  90%% 频次操作码:', ' '.join(s['cover90_ops']))
        print('  未实现 top:', ['%s:%d' % (r['op'], r['count'])
                                for r in s['unimplemented_sorted'][:20]])
    print('静态校验: 非法跳转=%d 非法场景号=%d 非法事件对象号=%d 反向事件区间(no-op)=%d'
          % (issues['bad_jump_targets'], issues['bad_scene_ids'],
             issues['bad_event_ids'], issues['inverted_event_ranges_noop']))
    if issues['bad_jump_samples']:
        print('  跳转样例:', issues['bad_jump_samples'][:5])
    if issues['bad_scene_samples']:
        print('  场景样例:', issues['bad_scene_samples'][:5])
    if issues['bad_event_samples']:
        print('  事件样例:', issues['bad_event_samples'][:5])


if __name__ == '__main__':
    main()
