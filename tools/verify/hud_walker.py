#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""HUD walker: follow an on-screen "next step" hint with real key presses and assert progress.

Loop: read state -> parse direction + remaining count N from the hint text -> press that key.
A walk PASSES only when the goal is actually reached. It FAILS when:
  - N goes up, or does not go down for `stall_limit` consecutive presses (swallowed input / stuck);
  - the position does not change for `still_limit` consecutive presses (blocked);
  - the scene changes to anything other than the spec's `end_scene`;
  - the hint shows neither a direction nor an expected arrival prompt;
  - the step limit is exhausted before arriving.

Usage:
  python hud_walker.py --backend playtest.json --specs walk-specs.json --path <name> [--jsonl walk.jsonl]
  python hud_walker.py --selfcheck
Exit code: 0 = reached the goal; 1 = assertion failed; 2 = config error / backend cannot export state.

Spec file (JSON object, one entry per path; see examples/pal98-walk-specs.json):
  {"<name>": {"max_steps": 200, "monotonic": true, "expect_prompt": ["..."], "end_scene": null,
              "stall_limit": 2, "still_limit": 3,
              "hud": {"n_regex": "(\\d+) left", "dir_regex": "\\[(\\w+)\\]", "dir_map": {"up": "UP"}}}}
"""
import argparse
import json
import os
import re
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from common import load_backend, ConfigError, UNSUPPORTED  # noqa: E402

DIR_MAP = {
    '↑': 'UP', '↓': 'DOWN', '←': 'LEFT', '→': 'RIGHT',
    'up': 'UP', 'down': 'DOWN', 'left': 'LEFT', 'right': 'RIGHT',
}
# Default hint format ("【→】剩 12 格"); override per spec with "hud": {n_regex, dir_regex, dir_map}.
DEFAULT_N_REGEX = r'剩\s*(\d+)\s*格'
DEFAULT_DIR_REGEX = r'【([↑↓←→])】'

RC_OK, RC_FAIL, RC_CONFIG = 0, 1, 2


def parse_hud(text, hud=None):
    """Return (direction key or None, remaining N or None) parsed from the hint text."""
    if not text:
        return None, None
    hud = hud or {}
    dir_map = dict(DIR_MAP)
    dir_map.update(hud.get('dir_map') or {})
    n = re.search(hud.get('n_regex') or DEFAULT_N_REGEX, text)
    d = re.search(hud.get('dir_regex') or DEFAULT_DIR_REGEX, text)
    direction = None
    if d:
        raw = d.group(1)
        direction = dir_map.get(raw) or dir_map.get(raw.lower())
    return direction, (int(n.group(1)) if n else None)


class MockBackend(object):
    """Offline stand-in for self-checks: N steps to the right, then an arrival prompt."""

    def __init__(self, steps=30):
        self.i = 0
        self.n = steps
        self.pos = [0, 0]

    def state(self):
        txt = '目标 店门（测试）｜下一步【→】剩 %d 格 · 按空格出客栈' % self.n
        if self.n <= 0:
            txt = '已到店门：按空格出客栈（→街道）'
        return {'scene': 'scene4', 'floor': '1F', 'pos': list(self.pos), 'central_text': txt, 'test_fast': True}

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


MOCK_SPECS = {'MOCK': {'max_steps': 60, 'expect_prompt': ['按空格出客栈'], 'monotonic': True}}


def walk(backend, path, specs, jsonl, max_steps=None):
    rec = {'ts': time.strftime('%Y-%m-%dT%H:%M:%S'), 'path': path, 'steps': 0,
           'n_seq': [], 'keys': [], 'fails': [], 'reached': False}

    def finish(rc):
        rec['ok'] = rc == RC_OK
        if rc == RC_FAIL:
            try:
                rec['snapshot'] = backend.failure_snapshot('walk_%s' % path)
                rec['shot'] = backend.shot('walk_%s' % path)
            except Exception as e:
                rec['snapshot_error'] = str(e)
        _append(jsonl, rec)
        return rc

    if path not in specs:
        rec['fails'].append('unknown path "%s" (known: %s)' % (path, ', '.join(sorted(specs)) or 'none; pass --specs'))
        return finish(RC_CONFIG)
    spec = specs[path]
    limit = max_steps or spec.get('max_steps', 200)
    monotonic = bool(spec.get('monotonic'))
    stall_limit = int(spec.get('stall_limit', 2))
    still_limit = int(spec.get('still_limit', 3))
    expected = spec.get('expect_prompt', [])

    scene0 = None
    last_n = last_pos = None
    stall = still = 0
    for step in range(limit + 1):
        st = backend.state()
        if st.get('unsupported'):
            rec['fails'].append('backend cannot export state: %s' % str(st.get('raw', ''))[:200])
            return finish(RC_CONFIG)
        if st.get('error'):
            rec['fails'].append('state export failed at step %d: %s' % (step, st['error'][:200]))
            break
        if step == 0:
            scene0 = st.get('scene')
        elif st.get('scene') != scene0:
            rec['scene_changed_to'] = st.get('scene')
            if spec.get('end_scene') is not None and st.get('scene') == spec['end_scene']:
                rec['reached'] = True
            else:
                rec['fails'].append('unexpected scene change %s -> %s at step %d' % (scene0, st.get('scene'), step))
            break

        prompt = st.get('central_text') or st.get('objective') or ''
        direction, n = parse_hud(prompt, spec.get('hud'))
        pos = st.get('pos')
        if step > 0:  # a key was pressed since the previous read: it must have had an effect
            if monotonic and n is not None and last_n is not None:
                if n > last_n:
                    rec['fails'].append('N increased %d -> %d at step %d' % (last_n, n, step))
                    break
                stall = stall + 1 if n == last_n else 0
                if stall >= stall_limit:
                    rec['fails'].append('N stuck at %d for %d consecutive key presses (input swallowed or blocked) at step %d'
                                        % (n, stall, step))
                    break
            if pos is not None and last_pos is not None:
                still = still + 1 if pos == last_pos else 0
                if still >= still_limit:
                    rec['fails'].append('position unchanged at %s for %d consecutive key presses at step %d'
                                        % (pos, still, step))
                    break
        if n is not None:
            rec['n_seq'].append(n)
            last_n = n
        last_pos = pos

        if direction is None:
            if n == 0 or any(p in prompt for p in expected):
                rec['reached'] = True
            else:
                rec['fails'].append('no direction and no expected prompt at step %d: %s' % (step, prompt[:80]))
            break
        if step == limit:
            rec['fails'].append('step limit %d reached without arriving (last N=%s)' % (limit, last_n))
            break
        rec['keys'].append(direction)
        r = backend.press(direction)
        if isinstance(r, str) and (r == UNSUPPORTED or r.startswith('ERROR')):
            rec['fails'].append('keys backend error: %s' % r[:200])
            break
        rec['steps'] += 1
        time.sleep(float(spec.get('settle_ms', 10)) / 1000.0)

    if not rec['fails'] and not rec['reached']:
        rec['fails'].append('walk ended without reaching the goal')
    return finish(RC_OK if not rec['fails'] else RC_FAIL)


def _append(jsonl, rec):
    if not jsonl:
        return
    d = os.path.dirname(jsonl)
    if d:
        os.makedirs(d, exist_ok=True)
    with open(jsonl, 'a', encoding='utf-8') as f:
        f.write(json.dumps(rec, ensure_ascii=False) + '\n')


def load_specs(path):
    if not path:
        return {}
    if not os.path.exists(path):
        raise ConfigError('specs file not found: %s' % path)
    try:
        with open(path, encoding='utf-8-sig') as f:
            specs = json.load(f)
    except ValueError as e:
        raise ConfigError('specs file is not valid JSON: %s (%s)' % (path, e))
    if not isinstance(specs, dict):
        raise ConfigError('specs file must be a JSON object of {name: spec}: %s' % path)
    return {k: v for k, v in specs.items() if isinstance(v, dict)}


def main():
    ap = argparse.ArgumentParser(description='follow an on-screen hint with real key presses and assert progress')
    ap.add_argument('--backend', help='playtest.json (or legacy per-action cmd config)')
    ap.add_argument('--path', help='name of the walk in the specs file')
    ap.add_argument('--specs', help='walk specs JSON ({name: spec})')
    ap.add_argument('--jsonl', default='')
    ap.add_argument('--max-steps', type=int)
    ap.add_argument('--selfcheck', action='store_true')
    args = ap.parse_args()
    if args.selfcheck:
        rc = walk(MockBackend(), 'MOCK', MOCK_SPECS, '')
        print('[selfcheck] mock walk rc=%d' % rc)
        return RC_OK if rc == RC_OK else RC_FAIL
    if not args.backend or not args.path or not args.specs:
        ap.error('--backend, --specs and --path are required (or use --selfcheck)')
    try:
        specs = load_specs(args.specs)
        backend = load_backend(args.backend)
    except ConfigError as e:
        print('[hud_walker] config error: %s' % e, file=sys.stderr)
        return RC_CONFIG
    return walk(backend, args.path, specs, args.jsonl, args.max_steps)


if __name__ == '__main__':
    sys.exit(main())
