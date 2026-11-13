#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""LIVE end-to-end check of the web backend (+ step runner) against tests/fixtures/webapp.

Needs Edge or Chrome installed; runs headless, so it is CI-friendly and takes no focus.
  python -B tests/Test-WebBackend.py [--keep]
Exit code 0 = all checks passed.
"""
import json
import os
import subprocess
import sys
import tempfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ADAPTER = os.path.join(ROOT, 'scripts', 'backends', 'web', 'adapter.py')
FIXTURE = os.path.join(ROOT, 'tests', 'fixtures', 'webapp', 'index.html')

fails = []


def check(name, fn):
    try:
        fn()
        print('PASS  ' + name)
    except AssertionError as e:
        fails.append(name)
        print('FAIL  %s : %s' % (name, e))


def main():
    keep = '--keep' in sys.argv
    tmp = tempfile.mkdtemp(prefix='gptkit-web-')
    cfg_path = os.path.join(tmp, 'playtest.json')
    cfg = {'name': 'notes', 'backend': 'web', 'launch': FIXTURE,
           'web': {'headless': True, 'viewport': [1000, 700]},
           'keys': {'gap_ms': 40}, 'evidence': {'dir': os.path.join(tmp, 'ev')}}
    with open(cfg_path, 'w', encoding='utf-8') as f:
        json.dump(cfg, f)

    def act(action, value=''):
        cmd = [sys.executable, '-B', ADAPTER, '-Action', action, '-Config', cfg_path]
        if value:
            cmd += ['-Value', value]
        p = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, cwd=tmp)
        lines = [l for l in (p.stdout or b'').decode('utf-8').splitlines() if l.startswith('{')]
        res = json.loads(lines[-1]) if lines else {}
        return p.returncode, res

    def ok(action, value=''):
        rc, res = act(action, value)
        assert rc == 0 and res.get('ok'), '%s %r -> rc=%d %s' % (action, value, rc, res.get('error') or res)
        return res

    def st():
        return ok('state')['state']

    def t_launch():
        r = ok('launch')
        assert r.get('url', '').endswith('#/login'), r
        assert st()['title'] == 'Notes - Sign in', st()['title']

    def t_single_instance():
        rc, res = act('launch')
        assert rc == 1 and 'single-instance' in res.get('error', ''), (rc, res)

    def t_gates():
        rc, res = act('click', 'css=#sso')
        assert rc == 1 and 'disabled' in res['error'], res
        rc, res = act('click', 'text=Sign in')
        assert rc == 1 and 'ambiguous' in res['error'], res

    def t_signin_flow():
        ok('click', 'css=#user'); ok('type', 'ann')
        ok('click', 'css=#pass'); ok('type', 'wrong')
        ok('click', 'css=#signin')
        assert 'Wrong user or password' in ok('read_text', 'css=#error')['text']
        ok('click', 'css=#pass'); ok('keys', 'BACKSPACE,BACKSPACE,BACKSPACE,BACKSPACE,BACKSPACE')
        ok('type', 'secret'); ok('click', 'css=#signin')
        s = st()
        assert s['title'] == 'Notes - List' and 'Welcome, ann' in s['visible_text'], s

    def t_unicode_and_enter():
        ok('click', 'css=#note'); ok('type', '牛奶 milk'); ok('keys', 'ENTER')
        assert ok('read_text', 'css=#count')['text'] == '1 note'
        assert '牛奶 milk' in ok('read_text', 'css=#list')['text']

    def t_covered_element_refused():
        rc, res = act('click', 'css=#covered')
        assert rc == 1 and 'covered' in res['error'], res

    def t_shot_append_only():
        a = ok('shot', 'same')['path']
        b = ok('shot', 'same')['path']
        assert a != b and os.path.exists(a) and os.path.exists(b), (a, b)

    def t_scroll():
        ok('scroll', '300,300,-5')
        assert st()['scroll'][1] > 0, st()['scroll']

    def t_unsupported():
        rc, res = act('test_fast', 'on')
        assert rc == 3 and res.get('unsupported'), (rc, res)

    def t_hint_needs_region():
        rc, res = act('hint', 'h')
        assert rc == 1 and 'crop_hint' in res['error'], res

    def t_step_runner():
        runner = os.path.join(ROOT, 'tools', 'verify', 'step_runner.py')
        steps = os.path.join(tmp, 'n01.json')
        with open(steps, 'w', encoding='utf-8') as f:
            json.dump({'node': 'W-N01', 'steps': [
                {'do': 'click', 'value': 'css=#note', 'expect': {'changed': True}},
                {'do': 'type', 'value': 'second'},
                {'do': 'keys', 'value': 'ENTER',
                 'expect': {'text_contains': '2 notes', 'state': {'title': 'Notes - List'}}},
                {'do': 'click', 'value': 'css=#covered', 'expect': {'text_contains': 'never'}, 'timeout_ms': 400},
            ]}, f)
        p = subprocess.run([sys.executable, '-B', runner, '--backend', cfg_path, '--steps', steps], cwd=tmp)
        assert p.returncode == 1, 'a swallowed click must fail the node (rc=%d)' % p.returncode
        snaps = os.path.join(tmp, 'ev', 'failures')
        assert os.path.isdir(snaps) and os.listdir(snaps), 'failure snapshot missing'

    def t_close():
        ok('close')
        rc, res = act('info')
        assert rc == 1, 'info after close must fail'

    for name, fn in [('launch + state', t_launch), ('single instance', t_single_instance),
                     ('input gates (disabled/ambiguous)', t_gates), ('sign-in flow', t_signin_flow),
                     ('unicode typing + Enter submit', t_unicode_and_enter),
                     ('covered element refused', t_covered_element_refused),
                     ('shots never overwrite', t_shot_append_only), ('scroll', t_scroll),
                     ('unsupported action -> exit 3', t_unsupported), ('hint needs crop_hint', t_hint_needs_region),
                     ('step_runner catches a swallowed click', t_step_runner), ('close', t_close)]:
        check(name, fn)

    if not keep:
        subprocess.run([sys.executable, '-B', ADAPTER, '-Action', 'close', '-Config', cfg_path], cwd=tmp,
                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        import shutil
        shutil.rmtree(tmp, ignore_errors=True)
    else:
        print('kept: ' + tmp)
    print('')
    if fails:
        print('== Test-WebBackend: %d failed: %s' % (len(fails), ', '.join(fails)))
        return 1
    print('== Test-WebBackend: ALL PASS ==')
    return 0


if __name__ == '__main__':
    sys.exit(main())
