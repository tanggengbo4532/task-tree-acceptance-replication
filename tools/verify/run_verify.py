#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""v3.2 一键验证（插件侧，引擎无关）：
  python run_verify.py --backend backend.json --paths A12,A14_1F,A14_2F,A13_PRE,DOCK \
      --jsonl walk-report.jsonl --ledger anchor-ledger.json
输出 PASS/FAIL 清单（名称/结果/耗时/证据路径），退出码 0=全过。
"""
import argparse
import os
import subprocess
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))


def run(cmd):
    t0 = time.time()
    p = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    out = (p.stdout or b'').decode('utf-8', 'replace') + (p.stderr or b'').decode('utf-8', 'replace')
    return p.returncode, out, round(time.time() - t0, 1)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--backend', required=True)
    ap.add_argument('--paths', default='A12,A14_1F,A14_2F,A13_PRE,DOCK')
    ap.add_argument('--jsonl', default=os.path.join(HERE, 'walk-report.jsonl'))
    ap.add_argument('--ledger', default=os.path.join(HERE, 'anchor-ledger.json'))
    ap.add_argument('--specs', default='')
    a = ap.parse_args()
    py = sys.executable
    rows, fail = [], 0
    for path in [x.strip() for x in a.paths.split(',') if x.strip()]:
        cmd = [py, os.path.join(HERE, 'hud_walker.py'), '--backend', a.backend,
               '--path', path, '--jsonl', a.jsonl]
        if a.specs:
            cmd += ['--specs', a.specs]
        rc, out, sec = run(cmd)
        ok = rc == 0
        rows.append(('walk_' + path, ok, sec, a.jsonl))
        fail += 0 if ok else 1
        print('[run_verify] walk_%s %s (%ss)' % (path, 'OK' if ok else 'FAIL', sec))
        if not ok:
            print(out[-2000:])
    rc, out, sec = run([py, os.path.join(HERE, 'anchor_check.py'), '--backend', a.backend, '--ledger', a.ledger])
    ok = rc == 0
    rows.append(('anchor_check', ok, sec, a.ledger))
    fail += 0 if ok else 1
    print('[run_verify] anchor_check %s (%ss)' % ('OK' if ok else 'FAIL', sec))

    print('\n===== VERIFY REPORT =====')
    for name, ok, sec, ev in rows:
        print('%-18s %s  %5ss  %s' % (name, 'PASS' if ok else 'FAIL', sec, ev))
    print('ALL OK' if fail == 0 else 'FAILURES: %d' % fail)
    return 0 if fail == 0 else 1


if __name__ == '__main__':
    sys.exit(main())
