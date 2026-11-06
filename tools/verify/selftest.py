#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""v3.2 verify 工具自检（无真实游戏也可跑）：解析/走位/锚点/JSONL 约定。"""
import io
import json
import os
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

import hud_walker  # noqa: E402
import anchor_check  # noqa: E402


def test_parse():
    d, n = hud_walker.parse_hud('目标 店门｜下一步【→】剩 12 格 · 按空格出客栈')
    assert d == 'RIGHT' and n == 12, (d, n)
    d2, n2 = hud_walker.parse_hud('已到店门：按空格出客栈')
    assert d2 is None and n2 is None
    print('[verify-selftest] parse_hud OK')


def test_walk_jsonl():
    tmp = tempfile.mkdtemp()
    jsonl = os.path.join(tmp, 'walk.jsonl')
    b = hud_walker.MockBackend(steps=10)
    rc = hud_walker.walk(b, 'A14_1F', hud_walker.DEFAULT_SPECS, jsonl)
    assert rc == 0, rc
    lines = io.open(jsonl, encoding='utf-8').read().strip().split('\n')
    rec = json.loads(lines[-1])
    assert rec['ok'] is True and rec['steps'] > 0 and len(rec['n_seq']) > 0
    print('[verify-selftest] walk+jsonl OK')


def test_anchor():
    tmp = tempfile.mkdtemp()
    ledger = os.path.join(tmp, 'anchor-ledger.json')
    b = anchor_check.MockBackend()
    assert anchor_check.check(b, ledger, True) == 0
    assert anchor_check.check(b, ledger, False) == 0
    print('[verify-selftest] anchor record/check OK')


def test_contract_fields():
    # 文档对账：CONTRACT §6 必须含 v3.2 动作
    p = os.path.join(os.path.dirname(HERE), '..', 'scripts', 'backends', 'CONTRACT.md')
    if os.path.exists(p):
        t = io.open(p, encoding='utf-8').read()
        for k in ['verification backend', 'state', 'test_fast', 'failure_snapshot']:
            assert k in t, k
        print('[verify-selftest] CONTRACT v3.2 fields OK')
    else:
        print('[verify-selftest] CONTRACT missing (skip)')


if __name__ == '__main__':
    test_parse()
    test_walk_jsonl()
    test_anchor()
    test_contract_fields()
    print('[verify-selftest] ALL OK')
