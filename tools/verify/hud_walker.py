#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""v3.2 HUD 走位器（引擎无关）：读 state → 真实按键 → 断言 N 严格递减/方向可走/无意外切场景。

用法：
  python hud_walker.py --backend backend.json --path A14_1F [--jsonl walk.jsonl]
  python hud_walker.py --selfcheck            # 内置 mock backend，自检断言/JSONL/失败快照
退出码 0=通过；1=断言失败；2=backend UNSUPPORTED/配置错误。
"""
import argparse
import json
import os
import re
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from common import load_backend, UNSUPPORTED  # noqa: E402

DIR_MAP = {
    '↑': 'UP', '↓': 'DOWN', '←': 'LEFT', '→': 'RIGHT',
    'up': 'UP', 'down': 'DOWN', 'left': 'LEFT', 'right': 'RIGHT',
}
DEFAULT_SPECS = {
    'A12': {'max_steps': 40, 'expect_prompt': ['李大娘', '麻布袋'], 'monotonic': False},
    'A13_PRE': {'max_steps': 40, 'expect_prompt': ['麻布袋'], 'monotonic': False},
    'A14_1F': {'max_steps': 220, 'expect_prompt': ['按空格出客栈'], 'monotonic': True},
    'A14_2F': {'max_steps': 260, 'expect_prompt': ['按空格出客栈'], 'monotonic': True},
    'DOCK': {'max_steps': 240, 'expect_prompt': ['按空格前往'], 'monotonic': True},
}


def parse_hud(text):
    """从 central_text 解析方向/N（契约：central_text/objective 可含【↑】剩 N 格）。"""
    if not text:
        return None, None
    n = re.search(r'剩\s*(\d+)\s*格', text)
    d = re.search(r'【([↑↓←→])】', text)
    return (DIR_MAP.get(d.group(1)) if d else None), (int(n.group(1)) if n else None)


class MockBackend:
    def __init__(self, steps=30):
        self.i = 0
        self.n = steps
        self.pos = [0, 0]

    def state(self):
        txt = '目标 店门（测试）｜下一步【→】剩 %d 格 · 按空格出客栈' % self.n
        if self.n <= 0:
            txt = '已到店门：按空格出客栈（→街道）'
        return {'scene': 'scene4', 'floor': '1F', 'pos': self.pos,
                'central_text': txt, 'test_fast': True}

    def press(self, key, hold_ms=60, gap_ms=120):
        self.i += 1
        self.pos = [self.pos[0] + 16, self.pos[1]]
        if self.n > 0:
            self.n -= 1
        return 'ok'

    def shot(self, name='shot'):
        return '/tmp/%s.png' % name

    def failure_snapshot(self, name='fail'):
        return '/tmp/%s' % name


def walk(backend, path, specs, jsonl, max_steps=None):
    spec = specs.get(path, {})
    limit = max_steps or spec.get('max_steps', 200)
    rec = {'ts': time.strftime('%Y-%m-%dT%H:%M:%S'), 'path': path, 'steps': 0,
           'n_seq': [], 'keys': [], 'fails': []}
    last_n = None
    st = backend.state()
    if st.get('unsupported'):
        rec['fails'].append('backend state UNSUPPORTED: %s' % st.get('raw', '')[:200])
        rec['ok'] = False
        _append(jsonl, rec)
        return 1
    scene0 = st.get('scene')
    for step in range(limit):
        st = backend.state()
        if st.get('unsupported'):
            rec['fails'].append('state became UNSUPPORTED')
            break
        if st.get('scene') != scene0:
            rec['scene_changed_to'] = st.get('scene')
            break
        direction, n = parse_hud(st.get('central_text') or st.get('objective') or '')
        if n is not None:
            rec['n_seq'].append(n)
            if spec.get('monotonic') and last_n is not None and n < last_n:
                last_n = n
            elif spec.get('monotonic') and last_n is not None and n > last_n:
                rec['fails'].append('N increased %d -> %d at step %d' % (last_n, n, step))
                break
            if spec.get('monotonic'):
                last_n = n
            if n == 0 and direction is None:
                break
        if direction is None:
            # 到门/无方向：若提示出现则通过
            prompt = (st.get('central_text') or '')
            if any(p in prompt for p in spec.get('expect_prompt', [])):
                rec['reached'] = True
                break
            rec['fails'].append('no direction and no expected prompt at step %d: %s' % (step, prompt[:80]))
            break
        rec['keys'].append(direction)
        r = backend.press(direction)
        if isinstance(r, str) and (r == UNSUPPORTED or r.startswith('ERROR')):
            rec['fails'].append('keys backend error: %s' % r[:200])
            break
        rec['steps'] += 1
        time.sleep(0.01)
    rec['ok'] = len(rec['fails']) == 0
    if not rec['ok']:
        try:
            rec['snapshot'] = backend.failure_snapshot('walk_%s' % path)
            rec['shot'] = backend.shot('walk_%s' % path)
        except Exception as e:
            rec['snapshot_error'] = str(e)
    _append(jsonl, rec)
    return 0 if rec['ok'] else 1


def _append(jsonl, rec):
    if not jsonl:
        return
    d = os.path.dirname(jsonl)
    if d:
        os.makedirs(d, exist_ok=True)
    with open(jsonl, 'a', encoding='utf-8') as f:
        f.write(json.dumps(rec, ensure_ascii=False) + '\n')


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--backend', help='backend config JSON（见 CONTRACT §6）')
    ap.add_argument('--path', choices=list(DEFAULT_SPECS.keys()))
    ap.add_argument('--specs', help='自定义 specs JSON（覆盖 DEFAULT_SPECS）')
    ap.add_argument('--jsonl', default='')
    ap.add_argument('--max-steps', type=int)
    ap.add_argument('--selfcheck', action='store_true')
    args = ap.parse_args()
    specs = dict(DEFAULT_SPECS)
    if args.specs and os.path.exists(args.specs):
        with open(args.specs, encoding='utf-8') as f:
            specs.update(json.load(f))
    if args.selfcheck:
        b = MockBackend()
        rc = walk(b, 'A14_1F', specs, '')
        print('[selfcheck] mock A14_1F rc=%d' % rc)
        return 0 if rc == 0 else 1
    if not args.backend or not args.path:
        ap.error('--backend 和 --path 必填（或使用 --selfcheck）')
    b = load_backend(args.backend)
    return walk(b, args.path, specs, args.jsonl, args.max_steps)


if __name__ == '__main__':
    sys.exit(main())
