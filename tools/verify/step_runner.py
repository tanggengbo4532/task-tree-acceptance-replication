#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Step runner: execute a node's steps through any backend and assert that each one WORKED.

Every step is "one real input -> one observable response". After the input the runner polls
the backend until the step's expectations hold or the timeout expires (bounded waiting), so a
swallowed click, a page that never loads or a wrong screen is a FAILURE, never a silent pass.

For task-tree nodes with checkpoints, load the starting state before invoking the runner
with --tree. The runner captures the start, the designated steps, and the final state.

Usage:
  python step_runner.py --backend playtest.json --steps node-N03.json [--jsonl trace.jsonl] [--out DIR]
  python step_runner.py --selfcheck
Exit code: 0 = every step passed; 1 = a step failed; 2 = config error / backend lacks a needed ability.

Steps file:
  {
    "node": "L1-N03",                       # task-tree node id (t_node); used in evidence names
    "name": "sign in with a valid account",
    "steps": [
      {"do": "click", "value": "css=#user"},
      {"do": "type",  "value": "ann"},
      {"do": "click", "value": "css=#signin",
       "expect": {"text_contains": "Welcome, ann", "location_contains": "#/notes"},
       "timeout_ms": 3000, "shot": true}
    ]
  }
`do` is any backend action (keys/hold/diag/click/type/scroll/launch/...) or "wait" (value = ms).

`expect` (all listed conditions must hold):
  changed            true  = the observable state must differ from before the input (DEFAULT when
                             `expect` is omitted); false = it must stay the same
  text_contains      string or list - visible text must contain each
  text_not_contains  string or list - visible text must contain none
  location_contains / location_equals / title_contains
  state              {"dotted.path": value} - exact match on fields of the exported state
Use "expect": {} for a step that legitimately has no visible response.

Observation uses backend `state` (plus `read_text` when the state has no visible_text). A backend
without `state` (pixels only, e.g. the Windows reference backend) can still check `changed` by
screenshot difference; any other expectation is then a config error (exit 2), not a pass.
"""
import argparse
import json
import os
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from common import load_backend, ConfigError, BackendError, BackendUnsupported  # noqa: E402

RC_OK, RC_FAIL, RC_CONFIG = 0, 1, 2
INPUT_ACTIONS = ('keys', 'hold', 'diag', 'click', 'type', 'scroll')
EXPECT_KEYS = ('changed', 'text_contains', 'text_not_contains', 'location_contains', 'location_equals',
               'title_contains', 'state')
POLL_S = 0.15
SHOT_DIFF_THRESHOLD = 0.0005


class Abort(Exception):
    """Stop the run with a config-level error (exit 2)."""


def _as_list(v):
    return v if isinstance(v, list) else [v]


def _dig(obj, dotted):
    cur = obj
    for part in dotted.split('.'):
        if isinstance(cur, dict) and part in cur:
            cur = cur[part]
        elif isinstance(cur, list) and part.isdigit() and int(part) < len(cur):
            cur = cur[int(part)]
        else:
            return None
    return cur


class Observer(object):
    """Reads what a user could observe, through `state` when available, pixels otherwise."""

    def __init__(self, backend, node):
        self.backend = backend
        self.node = node
        self.has_state = None
        self.seq = 0

    def observe(self, need_text=False):
        if self.has_state is not False:
            st = self.backend.state()
            if st.get('unsupported'):
                if self.has_state:
                    raise BackendError('state became unsupported mid-run')
                self.has_state = False
            elif st.get('error'):
                raise BackendError(st['error'])
            else:
                self.has_state = True
                obs = {'kind': 'state', 'state': st, 'text': st.get('visible_text')}
                if obs['text'] is None and need_text:
                    obs['text'] = self.backend.read_text('')
                return obs
        self.seq += 1
        path = self.backend.shot('%s_obs%03d' % (self.node, self.seq))
        if not isinstance(path, str) or path.startswith('ERROR') or path == 'UNSUPPORTED':
            raise BackendError('cannot observe: no state and screenshot failed (%s)' % path)
        return {'kind': 'shot', 'shot': path, 'text': None}

    @staticmethod
    def differs(a, b):
        if a['kind'] == 'state' and b['kind'] == 'state':
            return a['state'] != b['state']
        return _shot_diff(a['shot'], b['shot']) > SHOT_DIFF_THRESHOLD


def _shot_diff(a, b):
    # tools/probes/common.py shares its module name with verify/common.py, so load it by path
    import importlib.util
    spec = importlib.util.spec_from_file_location('probe_common', os.path.join(os.path.dirname(HERE), 'probes', 'common.py'))
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    try:
        return mod.diff_ratio(a, b)
    except ValueError:
        return 1.0  # frame size changed: that is a visible change


def unmet(expect, before, now):
    """List of human-readable reasons the expectations do not hold yet (empty = satisfied)."""
    out = []
    st = now.get('state') or {}
    text = now.get('text') or ''
    if 'changed' in expect:
        diff = Observer.differs(before, now)
        if bool(expect['changed']) != diff:
            out.append('expected the app to %s after the input, but it %s'
                       % ('respond' if expect['changed'] else 'stay unchanged', 'changed' if diff else 'did not change'))
    for want in _as_list(expect.get('text_contains', [])):
        if want not in text:
            out.append('visible text does not contain "%s"' % want)
    for bad in _as_list(expect.get('text_not_contains', [])):
        if bad in text:
            out.append('visible text still contains "%s"' % bad)
    loc = str(st.get('location', ''))
    if 'location_contains' in expect and expect['location_contains'] not in loc:
        out.append('location "%s" does not contain "%s"' % (loc, expect['location_contains']))
    if 'location_equals' in expect and expect['location_equals'] != loc:
        out.append('location is "%s", expected "%s"' % (loc, expect['location_equals']))
    if 'title_contains' in expect and expect['title_contains'] not in str(st.get('title', '')):
        out.append('title "%s" does not contain "%s"' % (st.get('title', ''), expect['title_contains']))
    for path, want in (expect.get('state') or {}).items():
        got = _dig(st, path)
        if got != want:
            out.append('state.%s is %r, expected %r' % (path, got, want))
    return out


def validate(spec):
    if not isinstance(spec, dict) or not isinstance(spec.get('steps'), list) or not spec['steps']:
        raise Abort('steps file must be {"node": ..., "steps": [ ... ]} with at least one step')
    for i, s in enumerate(spec['steps'], 1):
        if not isinstance(s, dict) or not s.get('do'):
            raise Abort('step %d: missing "do"' % i)
        exp = s.get('expect')
        if exp is not None and not isinstance(exp, dict):
            raise Abort('step %d: "expect" must be an object' % i)
        bad = [k for k in (exp or {}) if k not in EXPECT_KEYS]
        if bad:
            raise Abort('step %d: unknown expectation(s) %s (known: %s)' % (i, ', '.join(bad), ', '.join(EXPECT_KEYS)))
        if s['do'] == 'wait' and not str(s.get('value', '')).isdigit():
            raise Abort('step %d: wait needs value = milliseconds' % i)


def capture_screenshot(backend, name):
    path = backend.shot(name)
    if not path or not os.path.isfile(path):
        raise BackendError('screenshot backend did not return a file: %s' % path)
    return path


def run(backend, spec, jsonl='', out_dir='', checkpoints=()):
    """Run all steps. Returns (rc, summary dict)."""
    try:
        validate(spec)
        for number in checkpoints:
            if not 0 < number < len(spec['steps']):
                raise Abort('checkpoint %d must precede the final step' % number)
            if not spec['steps'][number - 1].get('expect'):
                raise Abort('checkpoint %d needs an explicit expectation' % number)
    except Abort as e:
        return RC_CONFIG, {'ok': False, 'error': str(e)}
    node = str(spec.get('node') or 'node')
    obs = Observer(backend, node)
    done = []
    summary = {'node': node, 'name': spec.get('name', ''), 'started': time.strftime('%Y-%m-%dT%H:%M:%S'),
               'steps_total': len(spec['steps']), 'steps_passed': 0, 'ok': False}

    def fail(rc, step_no, step, reasons, last=None):
        summary.update({'failed_step': step_no, 'do': step.get('do'), 'value': step.get('value', ''), 'reasons': reasons})
        if rc == RC_FAIL:
            summary['snapshot'] = _snapshot(backend, node, step_no, step, reasons, done, last, out_dir)
        _append(jsonl, dict(summary, record='summary'))
        return rc, summary

    if checkpoints:
        try:
            path = capture_screenshot(backend, '%s_entry' % node)
        except Exception as e:
            return fail(RC_FAIL, 0, {'do': 'capture_start'}, ['missing starting screenshot: %s' % e])
        summary.update(evidence=[path], checkpoint_evidence=[{'step': 0, 'path': path}])

    for i, step in enumerate(spec['steps'], 1):
        action, value = step['do'], str(step.get('value', ''))
        expect = step.get('expect')
        if expect is None:
            expect = {'changed': True} if action in INPUT_ACTIONS else {}
        need_text = any(k in expect for k in ('text_contains', 'text_not_contains'))
        timeout = float(step.get('timeout_ms', 5000)) / 1000.0
        t0 = time.time()
        rec = {'record': 'step', 'ts': time.strftime('%Y-%m-%dT%H:%M:%S'), 'node': node, 'step': i,
               'do': action, 'value': value}
        try:
            before = obs.observe(need_text) if expect else None
            if before and before['kind'] == 'shot':
                needs_state = [k for k in expect if k != 'changed']
                if needs_state:
                    raise Abort('step %d expects %s, but this backend exports no state/text (pixels only); '
                                'only "changed" can be checked' % (i, ', '.join(needs_state)))
            if action == 'wait':
                time.sleep(int(value) / 1000.0)
            else:
                backend.act(action, value)
            now, reasons = before, []
            while expect:
                now = obs.observe(need_text)
                reasons = unmet(expect, before, now)
                if not reasons or time.time() - t0 > timeout:
                    break
                time.sleep(POLL_S)
        except Abort as e:
            rec.update({'ok': False, 'error': str(e)})
            _append(jsonl, rec)
            return fail(RC_CONFIG, i, step, [str(e)])
        except BackendUnsupported as e:
            rec.update({'ok': False, 'error': str(e)})
            _append(jsonl, rec)
            return fail(RC_CONFIG, i, step, [str(e)])
        except BackendError as e:
            rec.update({'ok': False, 'error': str(e), 'elapsed_ms': int((time.time() - t0) * 1000)})
            _append(jsonl, rec)
            return fail(RC_FAIL, i, step, [str(e)])
        rec['elapsed_ms'] = int((time.time() - t0) * 1000)
        st = (now or {}).get('state') or {}
        for k in ('location', 'title', 'scene', 'pos'):
            if k in st:
                rec[k] = st[k]
        if reasons:
            reasons = ['%s (waited %d ms)' % (r, rec['elapsed_ms']) for r in reasons]
            rec.update({'ok': False, 'unmet': reasons})
            _append(jsonl, rec)
            return fail(RC_FAIL, i, step, reasons, now)
        rec['ok'] = True
        final_step = i == len(spec['steps'])
        required_shot = checkpoints and (i in checkpoints or final_step)
        if step.get('shot') or final_step or required_shot:
            try:
                shot = capture_screenshot(backend, '%s_s%02d' % (node, i))
                rec['shot'] = shot
                summary.setdefault('evidence', []).append(rec['shot'])
                if final_step:
                    summary['final_evidence'] = rec['shot']
                if required_shot:
                    summary['checkpoint_evidence'].append({'step': i, 'path': shot})
            except Exception as e:
                rec['shot_error'] = str(e)
                if required_shot:
                    rec['ok'] = False
                    _append(jsonl, rec)
                    return fail(RC_FAIL, i, step, ['missing required screenshot: %s' % e], now)
        _append(jsonl, rec)
        done.append({'step': i, 'do': action, 'value': value, 'ts': rec['ts']})
        summary['steps_passed'] = i

    summary['ok'] = True
    _append(jsonl, dict(summary, record='summary'))
    return RC_OK, summary


def _snapshot(backend, node, step_no, step, reasons, done, last, out_dir):
    """Failure snapshot directory (CONTRACT 6.2): what was done, what was seen, why it failed."""
    base = out_dir or backend.evidence_dir() or os.getcwd()
    d = os.path.join(base, 'failures', 'fail_%s_%s_s%02d' % (node, time.strftime('%Y%m%d-%H%M%S'), step_no))
    try:
        os.makedirs(d, exist_ok=True)
        with open(os.path.join(d, 'keys.jsonl'), 'w', encoding='utf-8') as f:
            for r in done + [{'step': step_no, 'do': step.get('do'), 'value': step.get('value', ''), 'failed': True}]:
                f.write(json.dumps(r, ensure_ascii=False) + '\n')
        state = (last or {}).get('state')
        if state is not None:
            with open(os.path.join(d, 'state.json'), 'w', encoding='utf-8') as f:
                json.dump(state, f, ensure_ascii=False, indent=2)
        frame = ''
        try:
            frame = backend.shot('fail_%s_s%02d' % (node, step_no))
        except Exception as e:
            frame = 'ERROR: %s' % e
        with open(os.path.join(d, 'manifest.json'), 'w', encoding='utf-8') as f:
            json.dump({'node': node, 'failed_step': step_no, 'do': step.get('do'), 'value': step.get('value', ''),
                       'expect': step.get('expect'), 'reasons': reasons, 'frame': frame,
                       'files': sorted(os.listdir(d)) + ['manifest.json']}, f, ensure_ascii=False, indent=2)
        return d
    except OSError as e:
        return 'ERROR: %s' % e


def _append(jsonl, rec):
    if not jsonl:
        return
    d = os.path.dirname(jsonl)
    if d:
        os.makedirs(d, exist_ok=True)
    with open(jsonl, 'a', encoding='utf-8') as f:
        f.write(json.dumps(rec, ensure_ascii=False) + '\n')


class MockApp(object):
    """Offline stand-in for self-checks: a sign-in page whose button can be made to swallow clicks."""

    def __init__(self, swallow=False, has_state=True):
        self.page, self.typed, self.swallow, self.has_state, self.shots = 'login', '', swallow, has_state, 0

    def state(self):
        if not self.has_state:
            return {'unsupported': True}
        text = 'Sign in' if self.page == 'login' else 'Welcome, %s' % self.typed
        return {'location': 'app://' + self.page, 'title': self.page, 'visible_text': text, 'focus': {'value': self.typed}}

    def act(self, action, value=''):
        if action == 'type':
            self.typed += value
        elif action == 'click' and value == 'signin' and not self.swallow:
            self.page = 'home'
        elif action not in ('click', 'keys'):
            raise BackendUnsupported("backend does not support '%s'" % action)
        return {'ok': True}

    def read_text(self, value=''):
        return None

    def shot(self, name='shot'):
        return 'ERROR: mock has no screen'

    def evidence_dir(self):
        return ''


SELFCHECK_STEPS = {'node': 'MOCK-N01', 'steps': [
    {'do': 'type', 'value': 'ann', 'expect': {'state': {'focus.value': 'ann'}}},
    {'do': 'click', 'value': 'signin', 'expect': {'text_contains': 'Welcome, ann', 'location_contains': 'home'},
     'timeout_ms': 300},
]}


def main():
    ap = argparse.ArgumentParser(description='run a node\'s steps through a backend and assert every response')
    ap.add_argument('--backend', help='playtest.json (or legacy per-action cmd config)')
    ap.add_argument('--steps', help='steps JSON file')
    ap.add_argument('--jsonl', default='', help='append a per-step trace to this file')
    ap.add_argument('--out', default='', help='directory for failure snapshots (default: the evidence dir)')
    ap.add_argument('--tree', default='', help='task-tree.json: after a pass, record the TESTER self-judgement here')
    ap.add_argument('--who', default='tester', help='--tree: who gives the tester verdict (default tester)')
    ap.add_argument('--build', help='--tree: ID of the application build under test')
    ap.add_argument('--selfcheck', action='store_true')
    a = ap.parse_args()
    if a.selfcheck:
        import tempfile
        with tempfile.TemporaryDirectory() as td:
            ok, _ = run(MockApp(), SELFCHECK_STEPS, out_dir=td)
            swallowed, _ = run(MockApp(swallow=True), SELFCHECK_STEPS, out_dir=td)
        print('[selfcheck] pass rc=%d, swallowed click rc=%d' % (ok, swallowed))
        return RC_OK if (ok, swallowed) == (RC_OK, RC_FAIL) else RC_FAIL
    if not a.backend or not a.steps:
        ap.error('--backend and --steps are required (or use --selfcheck)')
    try:
        backend = load_backend(a.backend)
        with open(a.steps, encoding='utf-8-sig') as f:
            spec = json.load(f)
        validate(spec)
    except ConfigError as e:
        print('[step_runner] config error: %s' % e, file=sys.stderr)
        return RC_CONFIG
    except (OSError, ValueError, Abort) as e:
        print('[step_runner] cannot read steps file: %s' % e, file=sys.stderr)
        return RC_CONFIG
    checkpoints = ()
    if a.tree:
        import task_tree
        a.tree = os.path.realpath(a.tree)
        try:
            tree = task_tree.load_tree(a.tree)
            task_tree.authorize(tree, a.tree, 'tester', a.who)
            node = task_tree.find_node(tree, spec.get('node'))
            if node.get('state') == 'passed':
                raise task_tree.Refused('reopen the passed node before retesting')
            build = a.build or tree.get('build')
            if not isinstance(build, str) or not build.strip():
                raise task_tree.Refused('--tree requires --build or a build ID in the task tree')
            test_context = (node, tree.get('build'), tree.get('role_policy'))
            checkpoints = task_tree.node_checkpoints(node)
        except (OSError, ValueError, task_tree.Refused) as e:
            print('[step_runner] could not start a tester attempt: %s' % e, file=sys.stderr)
            return RC_CONFIG
    rc, summary = run(backend, spec, a.jsonl, a.out, checkpoints=checkpoints)
    message = ''
    if a.tree and rc == RC_OK:
        try:
            if not summary.get('final_evidence'):
                raise task_tree.Refused('final screenshot was not captured')
            evidence = [os.path.abspath(path) for path in summary['evidence']]
            frames = [{'step': frame['step'], 'path': os.path.abspath(frame['path'])}
                      for frame in summary.get('checkpoint_evidence', [])]

            def record(tree, root, manifest, principal):
                return task_tree.record(tree, summary['node'], 'tester', 'pass', a.who, evidence,
                                        source='tool', build=build, root=root, manifest=manifest,
                                        principal=principal, checkpoint_evidence=frames,
                                        steps_passed=summary['steps_passed'])

            message, _ = task_tree.edit_tree(a.tree, summary['node'], 'tester', a.who, record,
                                             test_context=test_context)
            summary['tester_recorded'] = True
        except (OSError, ValueError, task_tree.Refused) as e:
            print('[step_runner] could not record the tester verdict in %s: %s' % (a.tree, e), file=sys.stderr)
            summary.update(ok=False, tester_recorded=False, record_error=str(e))
            rc = RC_CONFIG
    print(json.dumps(summary, ensure_ascii=False, indent=2))
    if message:
        print('[step_runner] ' + message)
    print('[step_runner] %s node=%s steps=%d/%d' % ('PASS' if rc == RC_OK else ('FAIL' if rc == RC_FAIL else 'CONFIG ERROR'),
                                                    summary.get('node', '?'), summary.get('steps_passed', 0),
                                                    summary.get('steps_total', 0)))
    return rc


if __name__ == '__main__':
    sys.exit(main())
