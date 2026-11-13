#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Offline self-check for tools/verify (no app, no window): parsing, walker verdicts, anchors, config.

Positive AND negative cases on purpose: the walker used to pass a run whose keys were all
swallowed, so every "must fail" case here is a regression guard.
"""
import io
import json
import os
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

import hud_walker  # noqa: E402
import anchor_check  # noqa: E402
import step_runner  # noqa: E402
import common  # noqa: E402
import task_tree  # noqa: E402


class Stuck(hud_walker.MockBackend):
    def press(self, *a, **k):
        return 'ok'  # keys swallowed: N never decreases


class Warp(hud_walker.MockBackend):
    def state(self):
        s = super().state()
        if self.i >= 2:
            s['scene'] = 'scene99'
        return s


class Backwards(hud_walker.MockBackend):
    def press(self, *a, **k):
        self.i += 1
        self.n += 1  # hint flips backwards
        return 'ok'


class Blocked(hud_walker.MockBackend):
    def state(self):
        s = super().state()
        s['pos'] = [0, 0]  # never moves
        return s


class EnglishHud(hud_walker.MockBackend):
    def state(self):
        s = super().state()
        self.n = 0 if self.n < 0 else self.n
        s['central_text'] = 'Target: door | next [left] %d left' % self.n if self.n > 0 else 'Reached the lobby'
        return s


def test_parse():
    d, n = hud_walker.parse_hud('目标 店门｜下一步【→】剩 12 格 · 按空格出客栈')
    assert d == 'RIGHT' and n == 12, (d, n)
    d2, n2 = hud_walker.parse_hud('已到店门：按空格出客栈')
    assert d2 is None and n2 is None
    hud = {'n_regex': r'(\d+) left', 'dir_regex': r'\[(\w+)\]', 'dir_map': {'left': 'LEFT'}}
    d3, n3 = hud_walker.parse_hud('next [left] 7 left', hud)
    assert d3 == 'LEFT' and n3 == 7, (d3, n3)
    print('[verify-selftest] parse_hud OK (default + per-spec hint format)')


def test_walk_verdicts():
    specs = hud_walker.MOCK_SPECS
    with tempfile.TemporaryDirectory() as td:
        jsonl = os.path.join(td, 'walk.jsonl')
        assert hud_walker.walk(hud_walker.MockBackend(steps=10), 'MOCK', specs, jsonl) == 0
        rec = json.loads(io.open(jsonl, encoding='utf-8').read().strip().split('\n')[-1])
        assert rec['ok'] is True and rec['reached'] is True and rec['steps'] > 0 and len(rec['n_seq']) > 0
    assert hud_walker.walk(Stuck(), 'MOCK', specs, '') == 1, 'swallowed keys must fail'
    assert hud_walker.walk(Backwards(), 'MOCK', specs, '') == 1, 'N going up must fail'
    assert hud_walker.walk(Blocked(), 'MOCK', specs, '') == 1, 'no movement must fail'
    assert hud_walker.walk(Warp(), 'MOCK', specs, '') == 1, 'unexpected scene change must fail'
    assert hud_walker.walk(hud_walker.MockBackend(steps=10), 'MOCK', specs, '', max_steps=3) == 1, 'step limit must fail'
    assert hud_walker.walk(hud_walker.MockBackend(steps=10), 'NOPE', specs, '') == 2, 'unknown path must be a config error'
    en_hud = {'n_regex': r'(\d+) left', 'dir_regex': r'\[(\w+)\]', 'dir_map': {'left': 'LEFT'}}
    en_ok = {'L': {'monotonic': True, 'expect_prompt': ['Reached the lobby'], 'hud': en_hud}}
    en_bare = {'L': {'monotonic': True, 'expect_prompt': ['Reached the lobby']}}
    assert hud_walker.walk(EnglishHud(steps=5), 'L', en_ok, '') == 0, 'custom hint format must be honoured'
    assert hud_walker.walk(EnglishHud(steps=5), 'L', en_bare, '') == 1, 'unparsed hint must not silently pass'
    print('[verify-selftest] walker verdicts OK (pass/stuck/backwards/blocked/scene/limit/unknown path)')


def test_anchor():
    with tempfile.TemporaryDirectory() as td:
        led = os.path.join(td, 'ledger.json')
        b = anchor_check.MockBackend()
        rcs = [anchor_check.check(b, led, True, 'a1'), anchor_check.check(b, led, False, 'a1'),
               anchor_check.check(b, led, True, 'a1'), anchor_check.check(anchor_check.MockBackend((0, 0)), led, False, 'a1')]
        assert rcs == [0, 0, 2, 1], 'record/check/duplicate/drift = %s' % rcs
        assert anchor_check.check(b, led, True, 'a2') == 0
        assert anchor_check.check(anchor_check.MockBackend((0, 0)), led, False, None) == 2, 'several anchors need --id'
        assert anchor_check.check(anchor_check.MockBackend((1088, 1652)), led, False, 'a1', pos_tol=8) == 0
    print('[verify-selftest] anchor append/immutable/id-select/tolerance OK')


def test_step_runner():
    with tempfile.TemporaryDirectory() as td:
        rc0, _ = step_runner.run(step_runner.MockApp(), step_runner.SELFCHECK_STEPS, out_dir=td)
        assert rc0 == 0, 'passing node must pass (rc=%d)' % rc0
        rc, s = step_runner.run(step_runner.MockApp(swallow=True), step_runner.SELFCHECK_STEPS, out_dir=td)
        assert rc == 1 and s['failed_step'] == 2 and os.path.isdir(s['snapshot'])
        bad = {'steps': [{'do': 'click', 'expect': {'nonsense': 1}}]}
        rc_bad, _ = step_runner.run(step_runner.MockApp(), bad, out_dir=td)
        assert rc_bad == 2
        unchanged = {'steps': [{'do': 'click', 'value': 'signin', 'expect': {'changed': False}}]}
        rc_un, _ = step_runner.run(step_runner.MockApp(), unchanged, out_dir=td)
        assert rc_un == 1, 'a click that DID respond but was expected not to must fail'
    print('[verify-selftest] step_runner pass/swallowed/bad-expectation/unchanged OK')


def test_backend_dispatch():
    here = os.path.dirname(HERE)
    root = os.path.dirname(here)
    sys.path.insert(0, here)
    import backendlib
    cfg = backendlib.load_config(os.path.join(root, 'templates', 'playtest.json'))
    assert backendlib.resolve_backend(cfg).endswith(os.path.join('scripts', 'windows', 'PlaytestKit.ps1'))
    cfg2 = dict(cfg, backend='web')
    assert backendlib.resolve_backend(cfg2).endswith(os.path.join('scripts', 'backends', 'web', 'adapter.py'))
    for bad, msg in [({'backend': 'nope'}, 'unknown backend'), ({'backend_path': 'missing.ps1'}, 'backend_path not found')]:
        try:
            backendlib.resolve_backend(dict(cfg, **bad))
            raise AssertionError('expected an error for %s' % bad)
        except backendlib.BackendError as e:
            assert msg in str(e), e
    assert backendlib.parse_result('SHOT C:\\My Name\\a.png method=x\n{"ok":true,"path":"C:\\\\a b.png"}')['path'] == 'C:\\a b.png'
    assert backendlib.parse_result('no json here') is None
    print('[verify-selftest] backend dispatch OK (windows/web, unknown name, missing path, JSON line)')


def test_task_tree():
    root = os.path.dirname(os.path.dirname(HERE))
    rc = task_tree.selfcheck.__wrapped__ if False else task_tree.selfcheck()
    assert rc == 0, 'task_tree selfcheck failed'
    # the shipped templates/examples must be valid, and a partially-done tree must not report overall pass
    probs, summary = task_tree.validate(task_tree.load_tree(os.path.join(root, 'templates', 'task-tree.json')),
                                        os.path.join(root, 'templates'))
    assert not [x for x in probs if x.severity == 'ERROR'], [str(x) for x in probs]
    ex = os.path.join(root, 'examples', 'task-tree.json')
    probs, summary = task_tree.validate(task_tree.load_tree(ex), os.path.join(root, 'examples'))
    assert not [x for x in probs if x.severity == 'ERROR'], [str(x) for x in probs]
    assert summary['overall_passed'] is False, 'a tree with open nodes must not be "overall passed"'
    print('[verify-selftest] task tree rules OK (template valid, partial tree not passed)')


def test_contract_and_plugin():
    root = os.path.dirname(os.path.dirname(HERE))
    contract = io.open(os.path.join(root, 'scripts', 'backends', 'CONTRACT.md'), encoding='utf-8').read()
    # every action a registered backend claims must be documented, and vice versa
    plugin = json.load(io.open(os.path.join(root, 'plugin.json'), encoding='utf-8-sig'))
    assert plugin['backends'], 'plugin.json registers no backends'
    for b in plugin['backends']:
        for a in b.get('actions', []) + b.get('unsupported', []):
            assert ('`%s`' % a) in contract, 'CONTRACT.md does not document action "%s" (backend %s)' % (a, b['name'])
        assert os.path.isfile(os.path.join(root, b['path'].replace('/', os.sep))), 'backend adapter missing: ' + b['path']
    for k in ('state', 'test_fast', 'failure_snapshot', 'input-log.jsonl', 'UNSUPPORTED'):
        assert k in contract, k
    print('[verify-selftest] CONTRACT <-> plugin.json backends OK (%d backends)' % len(plugin['backends']))


if __name__ == '__main__':
    test_parse()
    test_walk_verdicts()
    test_anchor()
    test_step_runner()
    test_backend_dispatch()
    test_task_tree()
    test_contract_and_plugin()
    print('[verify-selftest] ALL OK')
