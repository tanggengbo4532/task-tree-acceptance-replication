#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Anchor check: compare the app's current state with a recorded starting point.

Read-only: it only reads backend `state`; it never writes app state, saves or user data.
The ledger is append-only: an anchor id is recorded once and never overwritten.

Usage:
  python anchor_check.py --backend playtest.json --ledger anchor-ledger.json --record --id N03-start
  python anchor_check.py --backend playtest.json --ledger anchor-ledger.json --id N03-start [--pos-tol 8]
  python anchor_check.py --selfcheck
Exit code: 0 = matches / recorded; 1 = drift; 2 = config error (no ledger, unknown/duplicate id, no state).

Compared fields default to whichever of scene/floor/pos/flags/location/title the state exposes
(override with --fields). `flags` is a subset match; `pos` allows --pos-tol per axis.
"""
import argparse
import json
import os
import sys
import tempfile
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from common import load_backend, ConfigError  # noqa: E402

DEFAULT_FIELDS = ('scene', 'floor', 'pos', 'flags', 'location', 'title')


class MockBackend(object):
    def __init__(self, pos=(1088, 1648)):
        self.pos = list(pos)

    def state(self):
        return {'scene': 'scene4', 'floor': '1F', 'pos': list(self.pos),
                'flags': {'a13_stage': 0}, 'test_fast': False}


def load_ledger(path):
    if not os.path.exists(path):
        return {'anchors': []}
    with open(path, encoding='utf-8-sig') as f:
        data = json.load(f)
    if not isinstance(data, dict) or not isinstance(data.get('anchors', []), list):
        raise ConfigError('ledger must be {"anchors": [...]}: %s' % path)
    data.setdefault('anchors', [])
    return data


def _diff(exp, cur, pos_tol):
    fails = []
    for k, want in exp.items():
        if k in ('id', 'recorded', 'note'):
            continue
        got = cur.get(k)
        if k == 'flags' and isinstance(want, dict):
            for fk, fv in want.items():
                if (got or {}).get(fk) != fv:
                    fails.append('flag %s: %r != %r' % (fk, (got or {}).get(fk), fv))
        elif k == 'pos' and isinstance(want, (list, tuple)) and isinstance(got, (list, tuple)) and len(want) == len(got):
            try:
                if any(abs(float(a) - float(b)) > pos_tol for a, b in zip(got, want)):
                    fails.append('pos: %s != %s (tolerance %s)' % (list(got), list(want), pos_tol))
            except (TypeError, ValueError):
                if list(got) != list(want):
                    fails.append('pos: %s != %s' % (list(got), list(want)))
        elif got != want:
            fails.append('%s: %r != %r' % (k, got, want))
    return fails


def check(backend, ledger_path, record, anchor_id=None, fields=None, pos_tol=0.0):
    st = backend.state()
    if st.get('unsupported'):
        print('[anchor] backend cannot export state: %s' % str(st.get('raw'))[:200])
        return 2
    if st.get('error'):
        print('[anchor] state export failed: %s' % st['error'][:200])
        return 2
    use = list(fields) if fields else [k for k in DEFAULT_FIELDS if k in st]
    cur = {k: st.get(k) for k in use}
    print('[anchor] current=%s' % json.dumps(cur, ensure_ascii=False))
    try:
        ledger = load_ledger(ledger_path)
    except (ConfigError, ValueError) as e:
        print('[anchor] bad ledger: %s' % e)
        return 2
    anchors = ledger['anchors']

    if record:
        if not anchor_id:
            print('[anchor] --record needs --id <anchor id>')
            return 2
        if any(a.get('id') == anchor_id for a in anchors):
            print('[anchor] anchor "%s" already exists; anchors are immutable - record under a new id' % anchor_id)
            return 2
        entry = {'id': anchor_id, 'recorded': time.strftime('%Y-%m-%dT%H:%M:%S')}
        entry.update(cur)
        anchors.append(entry)
        ledger['updated'] = entry['recorded']
        d = os.path.dirname(os.path.abspath(ledger_path))
        os.makedirs(d, exist_ok=True)
        tmp = ledger_path + '.tmp'
        with open(tmp, 'w', encoding='utf-8') as f:
            json.dump(ledger, f, ensure_ascii=False, indent=2)
        os.replace(tmp, ledger_path)
        print('[anchor] recorded "%s" -> %s (%d anchors)' % (anchor_id, ledger_path, len(anchors)))
        return 0

    if not anchors:
        print('[anchor] ledger has no anchors (%s); record one first with --record --id <id>' % ledger_path)
        return 2
    if anchor_id:
        match = [a for a in anchors if a.get('id') == anchor_id]
        if not match:
            print('[anchor] unknown anchor id "%s" (known: %s)' % (anchor_id, ', '.join(str(a.get('id')) for a in anchors)))
            return 2
        exp = match[0]
    elif len(anchors) == 1:
        exp = anchors[0]
    else:
        print('[anchor] ledger has %d anchors; pass --id (known: %s)' % (len(anchors), ', '.join(str(a.get('id')) for a in anchors)))
        return 2
    fails = _diff(exp, st, pos_tol)
    if fails:
        print('[anchor] DRIFT vs "%s":\n- %s' % (exp.get('id', '?'), '\n- '.join(fails)))
        return 1
    print('[anchor] OK "%s"' % exp.get('id', '?'))
    return 0


def main():
    ap = argparse.ArgumentParser(description='compare current app state with a recorded anchor (read-only)')
    ap.add_argument('--backend', help='playtest.json (or legacy per-action cmd config)')
    ap.add_argument('--ledger', default='anchor-ledger.json')
    ap.add_argument('--id', dest='anchor_id', help='anchor id (required for --record and when the ledger has several)')
    ap.add_argument('--record', action='store_true', help='append the current state as a new anchor')
    ap.add_argument('--fields', default='', help='comma-separated state fields to record/compare')
    ap.add_argument('--pos-tol', type=float, default=0.0)
    ap.add_argument('--selfcheck', action='store_true')
    a = ap.parse_args()
    if a.selfcheck:
        with tempfile.TemporaryDirectory() as td:
            led = os.path.join(td, 'ledger.json')
            b = MockBackend()
            rcs = [check(b, led, True, 'a1'), check(b, led, False, 'a1'), check(b, led, True, 'a1'),
                   check(MockBackend((0, 0)), led, False, 'a1')]
        print('[selfcheck] record/check/duplicate/drift rc=%s' % rcs)
        return 0 if rcs == [0, 0, 2, 1] else 1
    if not a.backend:
        ap.error('--backend is required (or use --selfcheck)')
    try:
        backend = load_backend(a.backend)
    except ConfigError as e:
        print('[anchor] config error: %s' % e, file=sys.stderr)
        return 2
    fields = [x.strip() for x in a.fields.split(',') if x.strip()]
    return check(backend, a.ledger, a.record, a.anchor_id, fields, a.pos_tol)


if __name__ == '__main__':
    sys.exit(main())
