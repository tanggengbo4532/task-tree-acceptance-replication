#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Run a whole verification pass through one backend config (any engine/app).

  python run_verify.py --backend playtest.json --steps "L1-N01:n01.json,L1-N02:n02.json" \
      [--anchor N01-start] [--ledger anchor-ledger.json] [--jsonl report.jsonl] [--out DIR]
  python run_verify.py --backend playtest.json --steps node.json --walk specs.json:path-name
  python run_verify.py --backend playtest.json --steps node.json --launch     # start/stop the app
  python run_verify.py --backend playtest.json --tree task-tree.json --manifest evidence/manifest.json
  python run_verify.py --selfcheck

Checks, in order: optional launch -> task-tree rules -> optional anchor check -> steps per node
-> optional HUD walks.
Backend lack of ability (exit 2) is reported as `skip`, never as PASS.
Exit code: 0 = everything passed (skips allowed); 1 = at least one failure; 2 = config error.
"""
import argparse
import json
import os
import subprocess
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from common import load_backend, ConfigError, BackendError, BackendUnsupported  # noqa: E402
import step_runner  # noqa: E402

RC_OK, RC_FAIL, RC_CONFIG = 0, 1, 2


def _run_child_cmd(cmd):
    t0 = time.time()
    p = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    out = (p.stdout or b'').decode('utf-8', 'replace') + (p.stderr or b'').decode('utf-8', 'replace')
    return p.returncode, out, round(time.time() - t0, 1)


def _run_child(argv):
    t0 = time.time()
    p = subprocess.run([sys.executable, '-B'] + argv, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    out = (p.stdout or b'').decode('utf-8', 'replace') + (p.stderr or b'').decode('utf-8', 'replace')
    return p.returncode, out, round(time.time() - t0, 1)


def main():
    ap = argparse.ArgumentParser(description='one verification pass over any backend')
    ap.add_argument('--backend', required=True, help='playtest.json (or legacy per-action cmd config)')
    ap.add_argument('--steps', default='', help='node id:steps.json pairs, comma-separated')
    ap.add_argument('--anchor', default='', help='anchor id to check before running the steps')
    ap.add_argument('--ledger', default='anchor-ledger.json')
    ap.add_argument('--walk', default='', help='specs.json:path-name for a HUD walk')
    ap.add_argument('--jsonl', default='verify-report.jsonl')
    ap.add_argument('--out', default='', help='failure snapshot directory (default: the evidence dir)')
    ap.add_argument('--tree', default='', help='task-tree.json: validate the rules before running')
    ap.add_argument('--manifest', default='', help='evidence manifest for the task-tree hash check')
    ap.add_argument('--launch', action='store_true', help='launch before and close after (single instance)')
    ap.add_argument('--selfcheck', action='store_true')
    a = ap.parse_args()
    if a.selfcheck:
        print('[run_verify] delegate to step_runner --selfcheck')
        return step_runner.main(['--selfcheck'])
    try:
        backend = load_backend(a.backend)
    except ConfigError as e:
        print('[run_verify] config error: %s' % e, file=sys.stderr)
        return RC_CONFIG

    rows = []

    def add(name, state, detail='', sec=0.0):
        rows.append((name, state, detail, sec))
        print('[run_verify] %-24s %-5s %6ss  %s' % (name, state, sec, detail))

    try:
        if a.launch:
            try:
                res = backend.act('launch')
                add('launch', 'PASS', '', 0)
            except BackendUnsupported:
                add('launch', 'FAIL', 'backend has no launch action')
        if a.tree:
            cmd = [sys.executable, '-B', os.path.join(HERE, 'task_tree.py'), 'check', '--tree', a.tree]
            if a.manifest:
                cmd += ['--manifest', a.manifest]
            rc, out, sec = _run_child_cmd(cmd)
            state = {0: 'PASS', 1: 'FAIL'}.get(rc, 'CONFIG')
            tail = [l for l in out.strip().splitlines() if l.startswith('[task_tree]')]
            detail = tail[-1][len('[task_tree] '):][:110] if tail else 'rc=%d' % rc
            add('task_tree', state, detail, sec)

        if a.anchor:
            rc = step_runner.subprocess.call([sys.executable, '-B', os.path.join(HERE, 'anchor_check.py'),
                                              '--backend', a.backend, '--ledger', a.ledger, '--id', a.anchor],
                                             stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            add('anchor:' + a.anchor, 'PASS' if rc == 0 else ('FAIL' if rc == 1 else 'FAIL'), 'rc=%d' % rc)

        for pair in [x.strip() for x in a.steps.split(',') if x.strip()]:
            if ':' not in pair:
                add(pair, 'CONFIG', 'expected node:steps.json')
                continue
            node, path = pair.split(':', 1)
            try:
                with open(path, encoding='utf-8-sig') as f:
                    spec = json.load(f)
            except (OSError, ValueError) as e:
                add(node, 'CONFIG', 'steps file: %s' % e)
                continue
            spec.setdefault('node', node)
            rc, summary = step_runner.run(backend, spec, a.jsonl, a.out)
            state = {RC_OK: 'PASS', RC_FAIL: 'FAIL', RC_CONFIG: 'CONFIG'}[rc]
            detail = summary.get('snapshot') or (summary.get('reasons') or [''])[0]
            add(node, state, detail, 0)
            if rc == RC_CONFIG and summary.get('reasons'):
                add(node, 'SKIP', 'backend lacks an ability: %s' % summary['reasons'][0])

        if a.walk:
            specs, _, name = a.walk.rpartition(':')
            if not specs or not name:
                add('walk:' + a.walk, 'CONFIG', 'expected specs.json:path-name')
            else:
                rc, out, sec = _run_child([os.path.join(HERE, 'hud_walker.py'), '--backend', a.backend,
                                           '--specs', specs, '--path', name])
                state = {0: 'PASS', 1: 'FAIL', 2: 'CONFIG'}.get(rc, 'CONFIG')
                add('walk:' + name, state, (out.strip().splitlines() or [''])[-1][:120], sec)
    finally:
        if a.launch:
            try:
                backend.act('close')
                add('close', 'PASS', '', 0)
            except (BackendError, BackendUnsupported) as e:
                add('close', 'FAIL', str(e))

    fails = [r for r in rows if r[1] in ('FAIL', 'CONFIG')]
    print('\n===== VERIFY REPORT =====')
    for name, state, detail, sec in rows:
        print('%-26s %-6s %6ss  %s' % (name, state, sec, detail))
    print('ALL OK' if not fails else 'FAILURES: %d' % len(fails))
    return RC_OK if not fails else RC_FAIL


if __name__ == '__main__':
    sys.exit(main())
