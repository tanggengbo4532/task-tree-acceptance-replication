#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Machine-readable task tree: validate structure and enforce the acceptance rules.

The Markdown tree (templates/task-tree.md) stays the human view; this JSON tree is the one the
rules are checked against, so "a node is passed only with three confirmations" is no longer a
matter of good faith.

  python -B tools/verify/task_tree.py check  --tree task-tree.json [--root .] [--manifest evidence/manifest.json]
  python -B tools/verify/task_tree.py status --tree task-tree.json
  python -B tools/verify/task_tree.py check  --tree task-tree.json --json
  python -B tools/verify/task_tree.py record --tree task-tree.json --node A1 --role tester --verdict pass \
      --who tester --evidence evidence/A1.png [--source tool]
  python -B tools/verify/task_tree.py reopen --tree task-tree.json --node A1 --reason user_bug --who lead
  python -B tools/verify/task_tree.py --selfcheck

`check` exit code: 0 = structurally valid, 1 = rule violations, 2 = cannot read the tree.
`status` exit code: 0 = every node passed (overall pass), 1 = not yet, 2 = tree invalid.

`record` writes ONE role's verdict per invocation - that is the whole point:

  * a tool (step_runner) may only record the TESTER's own verdict (`--source tool`);
  * the developer review and the lead announcement are separate manual invocations
    (`--source manual`, the default) and cannot be produced by a test run;
  * the node becomes `passed` only on the lead's `pass`, and only after tester and developer
    both passed. No single command can turn a node into "passed" on its own.

`reopen` takes a passed node back to testing; it requires a reason (user_bug|code_change),
which is what makes "PASS is final" checkable rather than advisory.

Rules enforced by `check`:
  * every node has the four elements, all non-empty (who / where / action / t_node);
  * t_node is unique across the tree;
  * `requires` only points to nodes listed EARLIER (forward-only; also rejects cycles);
  * state is one of not_started/testing/blocked/fixing/passed;
  * history transitions follow the state machine, and a passed node may only go back to
    testing with reopen_reason user_bug|code_change (i.e. "PASS is final" is checked);
  * a passed node carries three confirmations - tester, developer, lead - all verdict "pass",
    each with who + t_exec;
  * a passed node lists at least one evidence file; with --manifest each file must be recorded
    there with a matching sha256 (append-only evidence, no silent rewrites).

The tool is read-only. Nodes are edited in the (versioned, reviewable) JSON file; git history is
the audit trail.
"""
import argparse
import hashlib
import json
import os
import re
import sys

SCHEMA = 1
STATES = ('not_started', 'testing', 'blocked', 'fixing', 'passed')
ROLES = ('tester', 'developer', 'lead')
ALLOWED = {
    'not_started': ('testing',),
    'testing': ('blocked', 'fixing', 'passed'),
    'blocked': ('testing', 'fixing'),
    'fixing': ('testing', 'passed'),
    'passed': ('testing',),
}
REOPEN_REASONS = ('user_bug', 'code_change')
LINE_TYPES = ('main', 'secondary', 'error', 'regression')
ISO_RE = re.compile(r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d+)?([+-]\d{2}:\d{2}|Z)?$')
T_NODE_RE = re.compile(r'^\S+$')


class Problem(object):
    def __init__(self, severity, path, message):
        self.severity, self.path, self.message = severity, path, message

    def __str__(self):
        return '%-5s %-28s %s' % (self.severity, self.path, self.message)


def _nonempty(v):
    if isinstance(v, str):
        return bool(v.strip())
    if isinstance(v, dict):
        return any(_nonempty(x) for x in v.values())
    return v is not None


def _where_text(where):
    if isinstance(where, str):
        return where
    if isinstance(where, dict):
        parts = [str(where.get(k)) for k in ('screen', 'entry', 'url', 'route', 'control') if where.get(k)]
        return ' / '.join(parts)
    return ''


def sha256(path):
    h = hashlib.sha256()
    with open(path, 'rb') as f:
        for chunk in iter(lambda: f.read(1 << 20), b''):
            h.update(chunk)
    return h.hexdigest()


def load_tree(path):
    if not os.path.exists(path):
        raise IOError('task tree not found: %s' % path)
    with open(path, encoding='utf-8-sig') as f:
        return json.load(f)


def load_manifest(path):
    """{absolute path: sha256} from tools/evidence/manifest.py's format."""
    with open(path, encoding='utf-8-sig') as f:
        data = json.load(f)
    out = {}
    for e in data.get('entries', []):
        if e.get('path') and e.get('sha256'):
            out[os.path.normcase(os.path.abspath(e['path']))] = e['sha256']
    return out


def validate(tree, root='.', manifest=None):
    """Return (problems, summary). problems is a list of Problem."""
    p = []

    def err(path, msg):
        p.append(Problem('ERROR', path, msg))

    def warn(path, msg):
        p.append(Problem('WARN', path, msg))

    if not isinstance(tree, dict):
        err('tree', 'must be a JSON object')
        return p, {}
    if tree.get('schema') != SCHEMA:
        err('schema', 'expected %r, got %r' % (SCHEMA, tree.get('schema')))
    for k in ('project', 'version'):
        if not _nonempty(tree.get(k)):
            warn(k, 'missing (recommended: identifies the tree in reports)')

    lines = tree.get('lines')
    line_ids = set()
    if not isinstance(lines, list) or not lines:
        err('lines', 'must be a non-empty list')
        lines = []
    for i, ln in enumerate(lines):
        path = 'lines[%d]' % i
        if not isinstance(ln, dict) or not _nonempty(ln.get('id')):
            err(path, 'line needs a non-empty "id"')
            continue
        if ln['id'] in line_ids:
            err(path, 'duplicate line id %r' % ln['id'])
        line_ids.add(ln['id'])
        if ln.get('type') not in LINE_TYPES:
            err(path, 'type must be one of %s' % '/'.join(LINE_TYPES))

    nodes = tree.get('nodes')
    if not isinstance(nodes, list) or not nodes:
        err('nodes', 'must be a non-empty list')
        nodes = []

    seen = {}
    order = {}
    for i, n in enumerate(nodes):
        path = 'nodes[%d]' % i
        if not isinstance(n, dict):
            err(path, 'node must be an object')
            continue
        tn = n.get('t_node')
        if not _nonempty(tn):
            err(path, 'missing t_node (the node identifier)')
            tn = None
        elif not T_NODE_RE.match(str(tn)):
            err(path, 't_node must be a single token without spaces: %r' % tn)
        elif tn in seen:
            err(path, 'duplicate t_node %r (retries keep the same t_node; mark them in "retries")' % tn)
        else:
            seen[tn] = n
            order[tn] = i
        if tn:
            path = 'node %s' % tn

        for key, label in (('who', '人'), ('where', '地点'), ('action', '做到什么')):
            if not _nonempty(n.get(key)):
                err(path, 'four elements: missing "%s" (%s)' % (key, label))
        if not _nonempty(n.get('line')):
            err(path, 'missing "line"')
        elif line_ids and n['line'] not in line_ids:
            err(path, 'unknown line %r (declared: %s)' % (n['line'], ', '.join(sorted(line_ids))))

        st = n.get('state', 'not_started')
        if st not in STATES:
            err(path, 'state must be one of %s (got %r)' % ('/'.join(STATES), st))

        # forward-only: requires must point at nodes that appear earlier
        for req in n.get('requires') or []:
            if req not in seen:
                err(path, 'requires unknown node %r' % req)
            elif order[req] >= i:
                err(path, 'requires %r which is not earlier in the tree (nodes only move forward)' % req)

        # state history must follow the state machine
        hist = n.get('history') or []
        cur = 'not_started'
        for j, h in enumerate(hist):
            if not isinstance(h, dict):
                err('%s history[%d]' % (path, j), 'must be an object')
                continue
            frm, to = h.get('from', cur), h.get('to')
            if frm != cur:
                err('%s history[%d]' % (path, j), 'from %r but the node was at %r' % (frm, cur))
            if to not in STATES:
                err('%s history[%d]' % (path, j), 'to must be one of %s (got %r)' % ('/'.join(STATES), to))
            elif frm in ALLOWED and to not in ALLOWED[frm]:
                err('%s history[%d]' % (path, j), 'illegal transition %s -> %s' % (frm, to))
            if frm == 'passed' and to == 'testing' and h.get('reopen_reason') not in REOPEN_REASONS:
                err('%s history[%d]' % (path, j),
                    'reopening a passed node needs reopen_reason %s (PASS is final otherwise)'
                    % '/'.join(REOPEN_REASONS))
            if h.get('t_exec') and not ISO_RE.match(str(h['t_exec'])):
                warn('%s history[%d]' % (path, j), 't_exec is not ISO-8601: %r' % h['t_exec'])
            cur = to if to in STATES else cur
        if hist and cur != st:
            err(path, 'state is %r but the history ends at %r' % (st, cur))
        if not hist and st != 'not_started':
            warn(path, 'state is %r without history (add the transitions you made)' % st)
        if st == 'passed' and not hist:
            warn(path, 'passed without history: the three confirmations cannot be dated')

        # a passed node needs the three confirmations and evidence
        conf = n.get('confirmations') or {}
        if st == 'passed':
            for role in ROLES:
                c = conf.get(role)
                if not isinstance(c, dict):
                    err(path, 'passed but missing confirmation "%s" (tester -> developer -> lead)' % role)
                    continue
                if c.get('verdict') != 'pass':
                    err(path, 'confirmation "%s" verdict is %r, not "pass"' % (role, c.get('verdict')))
                if not _nonempty(c.get('who')):
                    err(path, 'confirmation "%s" has no "who"' % role)
                if not _nonempty(c.get('t_exec')):
                    warn(path, 'confirmation "%s" has no t_exec' % role)
            ev = n.get('evidence') or []
            if not ev:
                err(path, 'passed but lists no evidence')
            for rel in ev:
                full = rel if os.path.isabs(rel) else os.path.join(root, rel)
                if not os.path.isfile(full):
                    err(path, 'evidence not found: %s' % rel)
                    continue
                if manifest is not None:
                    want = manifest.get(os.path.normcase(os.path.abspath(full)))
                    if want is None:
                        err(path, 'evidence not in the manifest: %s (run manifest.py add)' % rel)
                    elif want != sha256(full):
                        err(path, 'evidence hash drift (file changed after it was recorded): %s' % rel)
        else:
            for role in ROLES:
                if role in conf:
                    warn(path, 'confirmation "%s" recorded on a %r node' % (role, st))

    # every line needs at least one node
    used = set(n.get('line') for n in nodes if isinstance(n, dict))
    for lid in sorted(line_ids - used):
        warn('line %s' % lid, 'line has no nodes')

    summary = summarize(tree)
    return p, summary


# ---------------------------------------------------------------- write helpers
class Refused(Exception):
    """A write that the rules do not allow (exit code 1); nothing is written."""


def now_iso(offset='+08:00'):
    import time
    return time.strftime('%Y-%m-%dT%H:%M:%S', time.localtime()) + offset


def find_node(tree, t_node):
    for n in tree.get('nodes') or []:
        if isinstance(n, dict) and n.get('t_node') == t_node:
            return n
    raise Refused('unknown node %r' % t_node)


def _cur_state(node):
    return node.get('state', 'not_started')


def _set_state(node, new, t_exec, **extra):
    """Append a legal transition to history and move the node to `new`."""
    cur = _cur_state(node)
    if new not in ALLOWED.get(cur, ()):
        raise Refused('illegal transition %s -> %s for node %s' % (cur, new, node.get('t_node')))
    h = {'from': cur, 'to': new, 't_exec': t_exec}
    h.update(extra)
    node.setdefault('history', []).append(h)
    node['state'] = new


def record(tree, t_node, role, verdict, who, evidence=(), source='manual', t_exec=None, note=''):
    """Record ONE role's verdict. Returns (changed, message).

    The tool may only ever write the tester's verdict; developer review and lead announcement are
    human actions and are refused when requested by a tool. A node reaches `passed` only on the
    lead's pass, and only when tester and developer have both passed already.
    """
    if role not in ROLES:
        raise Refused('role must be one of %s' % '/'.join(ROLES))
    if verdict not in ('pass', 'reject'):
        raise Refused('verdict must be pass or reject')
    if source == 'tool' and role != 'tester':
        raise Refused('a tool may only record the tester\'s own verdict; "%s" confirmation must be made by a '
                      'person (developer review / lead announcement cannot be automated)' % role)
    if not _nonempty(who):
        raise Refused('--who is required (the verdict must name who gave it)')
    node = find_node(tree, t_node)
    t_exec = t_exec or now_iso()
    if not ISO_RE.match(t_exec):
        raise Refused('t_exec must be ISO-8601: %r' % t_exec)
    st = _cur_state(node)
    if st == 'passed':
        raise Refused('node %s is already passed; reopen it first (PASS is final)' % t_node)

    conf = node.setdefault('confirmations', {})
    entry = {'who': who, 'verdict': verdict, 't_exec': t_exec, 'source': source}
    if note:
        entry['note'] = note
    conf[role] = entry
    if evidence:
        ev = node.setdefault('evidence', [])
        for rel in evidence:
            if rel not in ev:
                ev.append(rel)

    if verdict == 'reject':
        # a rejection sends the node back to work, never forward
        if st == 'not_started':
            _set_state(node, 'testing', t_exec)
            st = 'testing'
        if st == 'testing':
            _set_state(node, 'fixing', t_exec)
        return True, 'node %s: %s verdict = reject (state %s)' % (t_node, role, _cur_state(node))

    if st == 'not_started':
        _set_state(node, 'testing', t_exec)
        st = 'testing'
    if role == 'tester':
        msg = 'node %s: tester self-judgement recorded; awaiting developer review' % t_node
    elif role == 'developer':
        if (conf.get('tester') or {}).get('verdict') != 'pass':
            raise Refused('developer review requires the tester\'s pass first')
        msg = 'node %s: developer review recorded; awaiting the lead announcement' % t_node
    else:  # lead
        for r in ('tester', 'developer'):
            if (conf.get(r) or {}).get('verdict') != 'pass':
                raise Refused('the lead cannot announce a pass before %s has passed' % r)
        if not (node.get('evidence') or []):
            raise Refused('the lead cannot announce a pass without evidence on node %s '
                          '(attach at least one screenshot/log first)' % t_node)
        _set_state(node, 'passed', t_exec)
        msg = 'node %s: PASSED (tester -> developer -> lead, evidence %d)' % (t_node, len(node.get('evidence') or []))
    return True, msg


def reopen(tree, t_node, reason, who, t_exec=None):
    if reason not in REOPEN_REASONS:
        raise Refused('reason must be one of %s (PASS is final otherwise)' % '/'.join(REOPEN_REASONS))
    if not _nonempty(who):
        raise Refused('--who is required')
    node = find_node(tree, t_node)
    if _cur_state(node) != 'passed':
        raise Refused('node %s is %s, not passed; nothing to reopen' % (t_node, _cur_state(node)))
    t_exec = t_exec or now_iso()
    _set_state(node, 'testing', t_exec, reopen_reason=reason, by=who)
    return True, 'node %s reopened for %s; confirmations must be given again' % (t_node, reason)


def save_tree(tree, path):
    """Write atomically; indent 2 and a trailing newline keep diffs reviewable."""
    tmp = path + '.tmp'
    with open(tmp, 'w', encoding='utf-8', newline='\n') as f:
        json.dump(tree, f, ensure_ascii=False, indent=2)
        f.write('\n')
    os.replace(tmp, path)


def _write_command(a):
    """record / reopen: one atomic, rule-checked edit of the JSON tree."""
    try:
        tree = load_tree(a.tree)
    except (IOError, OSError, ValueError) as e:
        print('[task_tree] cannot read: %s' % e, file=sys.stderr)
        return 2
    if not a.node:
        print('[task_tree] --node is required for %s' % a.command, file=sys.stderr)
        return 2
    try:
        if a.command == 'record':
            changed, msg = record(tree, a.node, a.role, a.verdict, a.who, a.evidence,
                                  a.source, a.t_exec or None, a.note)
        else:
            changed, msg = reopen(tree, a.node, a.reason, a.who, a.t_exec or None)
    except Refused as e:
        print('[task_tree] refused: %s' % e, file=sys.stderr)
        return 1
    # the edit must leave a tree that can still be checked; report (do not silently accept) breakage
    root = a.root or os.path.dirname(os.path.abspath(a.tree))
    problems, summary = validate(tree, root, None)
    errs = [str(x) for x in problems if x.severity == 'ERROR']
    if not a.dry_run:
        save_tree(tree, a.tree)
    print('[task_tree] %s%s' % (msg, ' (dry-run, nothing written)' if a.dry_run else ''))
    for e in errs:
        print('  ' + e)
    print('[task_tree] %s %s: %d/%d passed' % (summary.get('project') or '?', summary.get('version') or '',
                                               summary['nodes_passed'], summary['nodes_total']))
    return 0


def summarize(tree):
    nodes = [n for n in tree.get('nodes') or [] if isinstance(n, dict)]
    lines = [ln for ln in tree.get('lines') or [] if isinstance(ln, dict)]
    by_line = {}
    for ln in lines:
        by_line[ln.get('id')] = {'total': 0, 'passed': 0, 'open': []}
    for n in nodes:
        b = by_line.setdefault(n.get('line'), {'total': 0, 'passed': 0, 'open': []})
        b['total'] += 1
        if n.get('state') == 'passed':
            b['passed'] += 1
        else:
            b['open'].append(n.get('t_node'))
    total = len(nodes)
    passed = sum(1 for n in nodes if n.get('state') == 'passed')
    return {'project': tree.get('project'), 'version': tree.get('version'),
            'nodes_total': total, 'nodes_passed': passed,
            'overall_passed': total > 0 and passed == total, 'lines': by_line}


def main(argv=None):
    ap = argparse.ArgumentParser(description='validate and maintain a machine-readable task tree')
    ap.add_argument('command', nargs='?', choices=('check', 'status', 'record', 'reopen'), default='check')
    ap.add_argument('--tree', required=False, help='task-tree.json')
    ap.add_argument('--root', default=None, help='base dir for evidence paths (default: the tree file directory)')
    ap.add_argument('--manifest', default='', help='evidence manifest: also verify sha256 (no drift)')
    ap.add_argument('--json', dest='as_json', action='store_true')
    ap.add_argument('--strict', action='store_true', help='treat warnings as errors')
    ap.add_argument('--node', default='', help='record/reopen: t_node to update')
    ap.add_argument('--role', default='', help='record: tester | developer | lead')
    ap.add_argument('--verdict', default='pass', help='record: pass | reject (default pass)')
    ap.add_argument('--who', default='', help='record/reopen: who gives the verdict')
    ap.add_argument('--evidence', action='append', default=[], help='record: evidence path to attach (repeatable)')
    ap.add_argument('--source', default='manual', choices=('manual', 'tool'),
                    help='record: "tool" may only write the tester verdict (used by step_runner)')
    ap.add_argument('--t-exec', dest='t_exec', default='', help='record/reopen: ISO-8601 time (default now)')
    ap.add_argument('--note', default='', help='record: free-form note')
    ap.add_argument('--reason', default='', help='reopen: user_bug | code_change')
    ap.add_argument('--dry-run', action='store_true', help='record/reopen: print the result, write nothing')
    ap.add_argument('--selfcheck', action='store_true')
    a = ap.parse_args(argv)
    if a.selfcheck:
        return selfcheck()
    if not a.tree:
        ap.error('--tree is required (or use --selfcheck)')

    if a.command in ('record', 'reopen'):
        return _write_command(a)

    try:
        tree = load_tree(a.tree)
        manifest = load_manifest(a.manifest) if a.manifest else None
    except (IOError, OSError, ValueError) as e:
        print('[task_tree] cannot read: %s' % e, file=sys.stderr)
        return 2
    root = a.root or os.path.dirname(os.path.abspath(a.tree))
    problems, summary = validate(tree, root, manifest)
    errors = [x for x in problems if x.severity == 'ERROR']
    failed = errors or (a.strict and problems)

    if a.as_json:
        print(json.dumps({'ok': not failed, 'problems': [str(x) for x in problems], 'summary': summary},
                         ensure_ascii=False, indent=2))
    else:
        for x in problems:
            print(str(x))
        s = summary
        print('[task_tree] %s %s: %d nodes, %d passed, overall %s'
              % (s.get('project') or '?', s.get('version') or '', s['nodes_total'], s['nodes_passed'],
                 'PASS' if s['overall_passed'] else 'NOT PASSED'))
        for lid, b in sorted(s['lines'].items(), key=lambda kv: str(kv[0])):
            print('  line %-4s %d/%d passed%s' % (lid, b['passed'], b['total'],
                                                 ('   open: ' + ', '.join(str(x) for x in b['open'])) if b['open'] else ''))

    if a.command == 'status':
        return 0 if (summary.get('overall_passed') and not failed) else (2 if failed else 1)
    return 1 if failed else 0


# ---------------------------------------------------------------- self-check
def _node(tn, st='not_started', **kw):
    n = {'t_node': tn, 'line': 'A', 'who': 'user', 'where': {'screen': 'main', 'entry': 'exe'},
         'action': 'do %s' % tn, 'state': st}
    n.update(kw)
    return n


def _pass_hist(tn):
    return [{'from': 'not_started', 'to': 'testing', 't_exec': '2026-01-01T10:00:00+08:00'},
            {'from': 'testing', 'to': 'passed', 't_exec': '2026-01-01T10:05:00+08:00'}]


def _conf():
    return {r: {'who': r, 'verdict': 'pass', 't_exec': '2026-01-01T10:04:00+08:00'} for r in ROLES}


def selfcheck():
    import tempfile
    tmp = tempfile.mkdtemp(prefix='tt-selfcheck-')
    ev = os.path.join(tmp, 'shot.png')
    with open(ev, 'wb') as f:
        f.write(b'not-a-real-png')
    tree = {'schema': SCHEMA, 'project': 'demo', 'version': 'v1',
            'lines': [{'id': 'A', 'type': 'main'}],
            'nodes': [
                _node('N0', 'passed', history=_pass_hist('N0'), confirmations=_conf(), evidence=['shot.png']),
                _node('A1', requires=['N0']),
                _node('A2', requires=['A1']),
            ]}
    cases = []

    def case(name, mutate, want):
        import copy
        t = copy.deepcopy(tree)
        mutate(t)
        probs, _ = validate(t, tmp, None)
        ok = not [x for x in probs if x.severity == 'ERROR']
        cases.append((name, ok == want, [str(x) for x in probs]))

    case('valid tree with one passed node', lambda t: None, True)
    case('duplicate t_node', lambda t: t['nodes'].append(_node('A1')), False)
    case('missing four-element field', lambda t: t['nodes'][1].pop('where'), False)
    case('requires a later node', lambda t: t['nodes'][1].update(requires=['A2']), False)
    case('passed without developer confirmation',
         lambda t: t['nodes'][0]['confirmations'].pop('developer'), False)
    case('passed with lead veto',
         lambda t: t['nodes'][0]['confirmations']['lead'].update(verdict='reject'), False)
    case('passed without evidence', lambda t: t['nodes'][0].update(evidence=[]), False)
    case('reopen passed without reason',
         lambda t: t['nodes'][0].update(state='testing', history=_pass_hist('N0') + [
             {'from': 'passed', 'to': 'testing', 't_exec': '2026-01-02T10:00:00+08:00'}]),
         False)
    case('reopen passed with user_bug',
         lambda t: t['nodes'][0].update(state='testing', history=_pass_hist('N0') + [
             {'from': 'passed', 'to': 'testing', 't_exec': '2026-01-02T10:00:00+08:00', 'reopen_reason': 'user_bug'}]),
         True)
    case('state does not match history end', lambda t: t['nodes'][1].update(state='passed'), False)
    case('unknown state', lambda t: t['nodes'][1].update(state='done'), False)
    case('evidence file missing', lambda t: t['nodes'][0].update(evidence=['nope.png']), False)

    # ---- record / reopen: the three confirmations must be separable, and a tool may only sign as tester
    def rec_case(name, steps, want_ok, want_state=None, want_refuse_role=None):
        import copy
        t = copy.deepcopy(tree)
        t['nodes'][1].pop('confirmations', None)
        t['nodes'][1]['evidence'] = ['shot.png']
        ok = True
        refusal = None
        try:
            for kwargs in steps(t):
                record(t, 'A1', **kwargs)
        except Refused as e:
            ok = False
            refusal = str(e)
        n = t['nodes'][1]
        good = ok == want_ok
        if want_state is not None and ok:
            good = good and n.get('state') == want_state
        if want_refuse_role is not None:
            good = good and refusal is not None and want_refuse_role in refusal
        cases.append((name, good, [refusal or 'state=%s' % n.get('state')]))

    tester = dict(role='tester', verdict='pass', who='tester', evidence=['shot.png'])
    dev = dict(role='developer', verdict='pass', who='developer')
    lead = dict(role='lead', verdict='pass', who='lead')

    rec_case('record tester only -> node stays testing',
             lambda t: [dict(tester, source='tool')], True, 'testing')
    rec_case('record reject by tester -> node goes to fixing',
             lambda t: [dict(tester, verdict='reject')], True, 'fixing')
    rec_case('lead cannot announce before developer',
             lambda t: [dict(tester, source='tool'), lead], False, None, 'developer')
    rec_case('developer review requires tester first',
             lambda t: [dev], False, None, 'tester')
    rec_case('full chain tester -> developer -> lead -> passed',
             lambda t: [dict(tester, source='tool'), dev, lead], True, 'passed')
    rec_case('a tool cannot write the developer review',
             lambda t: [dict(dev, source='tool')], False, None, 'person')
    rec_case('a tool cannot write the lead announcement',
             lambda t: [dict(lead, source='tool')], False, None, 'person')
    rec_case('a reject never moves the node to passed',
             lambda t: [dict(tester, source='tool'), dict(dev, verdict='reject')], True, 'fixing')

    def reopen_case(name, steps, want_ok, want_state, want_msg=None):
        import copy
        t = copy.deepcopy(tree)
        ok = True
        msg = ''
        try:
            for kwargs in steps(t):
                _changed, msg = reopen(t, **kwargs)
        except Refused as e:
            ok = False
            msg = str(e)
        good = (ok == want_ok)
        if ok:
            good = good and t['nodes'][0].get('state') == want_state
        if want_msg:
            good = good and want_msg in msg
        cases.append((name, good, [msg]))

    reopen_case('reopen needs a known reason',
                lambda t: [dict(t_node='N0', reason='because', who='lead')], False, 'passed', 'user_bug')
    reopen_case('reopen with user_bug -> testing + reason in history',
                lambda t: [dict(t_node='N0', reason='user_bug', who='lead')], True, 'testing')
    reopen_case('reopen a non-passed node is refused',
                lambda t: [dict(t_node='A1', reason='user_bug', who='lead')], False, 'not_started', 'not passed')

    # a passed node must not accept further verdicts until reopened
    def double_pass(name):
        import copy
        t = copy.deepcopy(tree)
        try:
            record(t, 'N0', role='tester', verdict='pass', who='tester')
            cases.append((name, False, ['accepted a verdict on a passed node']))
        except Refused as e:
            cases.append((name, 'reopen' in str(e), [str(e)]))
    double_pass('a passed node refuses new verdicts until reopened')


    bad = [c for c in cases if not c[1]]
    for name, ok, probs in cases:
        print('%s  %s' % ('PASS ' if ok else 'FAIL ', name))
    probs, summary = validate(tree, tmp, None)
    allpass = summarize({'nodes': [dict(n, state='passed') for n in tree['nodes']], 'lines': tree['lines']})
    print('[task_tree] selfcheck %d/%d, overall=%s, partial=%s'
          % (len(cases) - len(bad), len(cases), allpass['overall_passed'], summary['overall_passed']))
    return 0 if not bad and allpass['overall_passed'] and not summary['overall_passed'] else 1


if __name__ == '__main__':
    sys.exit(main())
