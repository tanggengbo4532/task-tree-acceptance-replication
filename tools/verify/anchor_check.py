#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""v3.2 锚点检查（引擎无关）：只读 backend state，与 anchor-ledger 比对；绝不写游戏状态。

用法：
  python anchor_check.py --backend backend.json --ledger anchor-ledger.json [--record]
  python anchor_check.py --selfcheck
"""
import argparse
import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from common import load_backend  # noqa: E402


class MockBackend:
    def state(self):
        return {'scene': 'scene4', 'floor': '1F', 'pos': [1088, 1648],
                'flags': {'a13_stage': 0}, 'test_fast': False}


def check(backend, ledger_path, record):
    st = backend.state()
    if st.get('unsupported'):
        print('[anchor] FAIL state UNSUPPORTED: %s' % str(st.get('raw'))[:200])
        return 2
    cur = {'scene': st.get('scene'), 'floor': st.get('floor'), 'pos': st.get('pos'),
           'flags': st.get('flags', {})}
    print('[anchor] current=%s' % json.dumps(cur, ensure_ascii=False))
    if record:
        data = {'updated': __import__('time').strftime('%Y-%m-%dT%H:%M:%S'),
                'anchors': [cur], 'note': '锚点台账由 tester/Lead 维护；本工具不写游戏状态'}
        with open(ledger_path, 'w', encoding='utf-8') as f:
            json.dump(data, f, ensure_ascii=False, indent=2)
        print('[anchor] recorded -> %s' % ledger_path)
        return 0
    if not os.path.exists(ledger_path):
        print('[anchor] ledger 不存在，可先 --record')
        return 2
    with open(ledger_path, encoding='utf-8') as f:
        ledger = json.load(f)
    fails = []
    for exp in ledger.get('anchors', []):
        if exp.get('scene') and exp['scene'] != cur['scene']:
            fails.append('scene %s != %s' % (cur['scene'], exp['scene']))
        if exp.get('pos') and cur['pos'] and list(exp['pos']) != list(cur['pos']):
            fails.append('pos %s != %s' % (cur['pos'], exp['pos']))
        for k, v in (exp.get('flags') or {}).items():
            if (cur['flags'] or {}).get(k) != v:
                fails.append('flag %s %s != %s' % (k, (cur['flags'] or {}).get(k), v))
    if fails:
        print('[anchor] FAIL:\n- ' + '\n- '.join(fails))
        return 1
    print('[anchor] OK')
    return 0


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--backend')
    ap.add_argument('--ledger', default='anchor-ledger.json')
    ap.add_argument('--record', action='store_true')
    ap.add_argument('--selfcheck', action='store_true')
    a = ap.parse_args()
    if a.selfcheck:
        b = MockBackend()
        rc = check(b, '', True) if False else 0
        rc = check(b, os.path.join(os.path.dirname(__file__), '_selfcheck-ledger.json'), True)
        rc2 = check(b, os.path.join(os.path.dirname(__file__), '_selfcheck-ledger.json'), False)
        try:
            os.remove(os.path.join(os.path.dirname(__file__), '_selfcheck-ledger.json'))
        except OSError:
            pass
        print('[selfcheck] mock anchor rc=%d/%d' % (rc, rc2))
        return 0 if rc == 0 and rc2 == 0 else 1
    if not a.backend:
        ap.error('--backend 必填（或 --selfcheck）')
    return check(load_backend(a.backend), a.ledger, a.record)


if __name__ == '__main__':
    sys.exit(main())
