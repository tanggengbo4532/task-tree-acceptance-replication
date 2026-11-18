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
      --who tester --build BUILD_ID --evidence evidence/A1.png [--source tool]
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

Writes use a locked read-validate-replace transaction. Reopen and rejection archive the
active attempt; fresh evidence and a build ID are required to start the next one.
"""
import argparse
from contextlib import contextmanager
from copy import deepcopy
from datetime import datetime
import hashlib
import json
import os
import re
import sys
import tempfile
from uuid import uuid4

from role_policy import authorize

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
            out[os.path.normcase(os.path.realpath(e['path']))] = e['sha256']
    return out


def evidence_path(root, path):
    return os.path.realpath(os.path.join(root, path))


def evidence_hash(root, path, manifest):
    full = evidence_path(root, path)
    if not os.path.isfile(full):
        raise Refused('evidence not found: %s' % path)
    digest = sha256(full)
    if manifest is not None:
        expected = manifest.get(os.path.normcase(full))
        if expected is None:
            raise Refused('evidence not in the manifest: %s (run manifest.py add)' % path)
        if expected != digest:
            raise Refused('evidence hash drift: %s' % path)
    return digest


def validate(tree, root='.', manifest=None, evidence_node=None):
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
        if not isinstance(tn, str) or not tn.strip():
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

        conf = n.get('confirmations') or {}
        ev = n.get('evidence') or []
        if not isinstance(conf, dict) or not isinstance(ev, list) or not all(
                isinstance(rel, str) and rel.strip() for rel in ev):
            err(path, 'confirmations must be an object and evidence must be a list of paths')
            continue
        attempt = n.get('attempt')
        if attempt is not None:
            if not isinstance(attempt, dict) or not all(
                    isinstance(attempt.get(key), str) and attempt[key].strip()
                    for key in ('id', 'build')):
                err(path, 'attempt requires an ID and a build')
                continue
            hashes = attempt.get('sha256')
            if not isinstance(hashes, dict) or not ev or hashes.keys() != set(ev):
                err(path, 'the attempt must bind every evidence file to its SHA-256')
                continue
            for role, confirmation in conf.items():
                if not isinstance(confirmation, dict) or confirmation.get('attempt_id') != attempt['id']:
                    err(path, 'confirmation "%s" belongs to a different attempt' % role)
            if evidence_node is None or tn == evidence_node:
                for rel in ev:
                    try:
                        if evidence_hash(root, rel, manifest) != hashes[rel]:
                            err(path, 'evidence changed since the tester recorded it: %s' % rel)
                    except (OSError, Refused) as e:
                        err(path, str(e))
        elif st == 'passed':
            warn(path, 'legacy pass without a build or attempt binding (reopen to obtain a current pass)')
            if any(isinstance(h, dict) and h.get('from') == 'passed' for h in hist):
                err(path, 'legacy pass was reissued after reopening without a fresh attempt binding')
            if evidence_node is None or tn == evidence_node:
                for rel in ev:
                    try:
                        evidence_hash(root, rel, manifest)
                    except (OSError, Refused) as e:
                        err(path, str(e))

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
            if not ev:
                err(path, 'passed but lists no evidence')
        elif conf and attempt is None:
            warn(path, 'legacy confirmations on an open node (a fresh tester verdict is required)')

    # every line needs at least one node
    used = set(n.get('line') for n in nodes if isinstance(n, dict))
    for lid in sorted(line_ids - used):
        warn('line %s' % lid, 'line has no nodes')

    summary = summarize(tree)
    return p, summary


# ---------------------------------------------------------------- write helpers
class Refused(Exception):
    """A write that the rules do not allow (exit code 1); nothing is written."""


def now_iso():
    return datetime.now().astimezone().isoformat(timespec='seconds')


def find_node(tree, t_node):
    if not isinstance(tree, dict):
        raise Refused('task tree must be a JSON object')
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


def archive_attempt(node, **details):
    previous = {}
    for key in ('attempt', 'confirmations', 'evidence'):
        value = node.pop(key, None)
        if value:
            previous[key] = value
    previous.update(details)
    if previous:
        node.setdefault('previous_attempts', []).append(previous)


def record(tree, t_node, role, verdict, who, evidence=(), source='manual',
           t_exec=None, note='', *, build=None, attempt_id=None, root='.', manifest=None,
           principal=None):
    """Record one role against the current build and evidence snapshot."""
    if role not in ROLES:
        raise Refused('role must be one of %s' % '/'.join(ROLES))
    if verdict not in ('pass', 'reject'):
        raise Refused('verdict must be pass or reject')
    if source == 'tool' and role != 'tester':
        raise Refused('a tool may only record the tester verdict; %s must be reviewed by a person' % role)
    if not isinstance(who, str) or not who.strip():
        raise Refused('--who is required')
    original = find_node(tree, t_node)
    node = deepcopy(original)
    t_exec = t_exec or now_iso()
    if not ISO_RE.fullmatch(t_exec):
        raise Refused('t_exec must be ISO-8601: %r' % t_exec)
    st = _cur_state(node)
    if st == 'passed':
        raise Refused('node %s is already passed; reopen it first' % t_node)

    entry = {'who': who, 'verdict': verdict, 't_exec': t_exec, 'source': source}
    if principal:
        entry['principal'] = principal
    if note:
        entry['note'] = note
    attempt = node.get('attempt')
    if attempt_id and (not attempt or attempt_id != attempt['id']):
        raise Refused('this review refers to a different attempt; inspect the current evidence')
    if verdict == 'reject':
        if attempt is not None and build and build != attempt['build']:
            raise Refused('rejection build does not match the current attempt')
        archive_attempt(node, rejection=dict(entry, role=role, build=build, evidence={
            path: evidence_hash(root, path, manifest) for path in evidence
        }))
        if st == 'not_started':
            _set_state(node, 'testing', t_exec)
            st = 'testing'
        if st != 'fixing':
            _set_state(node, 'fixing', t_exec)
        msg = 'node %s: %s rejected the result; a fresh tester verdict is required' % (t_node, role)
    elif role == 'tester':
        build = build or tree.get('build')
        if not isinstance(build, str) or not build.strip():
            raise Refused('tester pass requires --build or a build ID in the task tree')
        if not evidence:
            raise Refused('tester pass requires at least one evidence file from this run')
        build = build.strip()
        last_reopen = next((event for event in reversed(node.get('history', []))
                            if event.get('from') == 'passed'), {})
        if last_reopen.get('reopen_reason') == 'code_change' and last_reopen.get('previous_build') == build:
            raise Refused('a code-change retest requires a different build ID')
        previous_paths = {
            os.path.normcase(evidence_path(root, rel))
            for previous in [node, *node.get('previous_attempts', [])]
            for rel in (*previous.get('evidence', ()), *previous.get('rejection', {}).get('evidence', {}))
        }
        hashes = {}
        for rel in evidence:
            full = evidence_path(root, rel)
            if os.path.normcase(full) in previous_paths:
                raise Refused('evidence path belongs to a previous verdict; capture fresh evidence: %s' % rel)
            stored = os.path.normpath(rel)
            hashes[stored] = evidence_hash(root, stored, manifest)
        archive_attempt(node)
        attempt = {'id': uuid4().hex, 'build': build, 'sha256': hashes}
        node.update(attempt=attempt, evidence=list(hashes),
                    confirmations={'tester': dict(entry, attempt_id=attempt['id'])})
        if st != 'testing':
            _set_state(node, 'testing', t_exec)
        msg = 'node %s: tester verdict recorded for build %s, attempt %s; awaiting developer review' % (
            t_node, build, attempt['id'])
    else:
        if evidence:
            raise Refused('reviewers sign the tester evidence snapshot; start a new tester verdict to replace it')
        conf = node.get('confirmations', {})
        required = ROLES[:ROLES.index(role)]
        for prior in required:
            confirmation = conf.get(prior, {})
            if not (attempt and confirmation.get('verdict') == 'pass'
                    and confirmation.get('attempt_id') == attempt['id']):
                raise Refused('%s requires a current %s pass for this attempt' % (role, prior))
        if not attempt_id:
            raise Refused('review requires --attempt with the ID of the tester evidence you reviewed')
        if build and build != attempt['build']:
            raise Refused('review build does not match the current attempt')
        if not node.get('evidence'):
            raise Refused('the lead cannot announce a pass without evidence from this attempt')
        conf[role] = dict(entry, attempt_id=attempt['id'])
        if role == 'lead':
            _set_state(node, 'passed', t_exec, attempt_id=attempt['id'], build=attempt['build'])
            msg = 'node %s: PASSED (build %s, attempt %s)' % (t_node, attempt['build'], attempt['id'])
        else:
            msg = 'node %s: developer reviewed build %s; awaiting lead confirmation' % (t_node, attempt['build'])

    original.clear()
    original.update(node)
    return True, msg


def reopen(tree, t_node, reason, who, t_exec=None, *, principal=None):
    if reason not in REOPEN_REASONS:
        raise Refused('reason must be one of %s' % '/'.join(REOPEN_REASONS))
    if not isinstance(who, str) or not who.strip():
        raise Refused('--who is required')
    node = find_node(tree, t_node)
    if _cur_state(node) != 'passed':
        raise Refused('node %s is %s, not passed; nothing to reopen' % (t_node, _cur_state(node)))
    t_exec = t_exec or now_iso()
    if not ISO_RE.fullmatch(t_exec):
        raise Refused('t_exec must be ISO-8601: %r' % t_exec)
    previous_build = (node.get('attempt') or {}).get('build')
    actor = {'by': who}
    if principal:
        actor['principal'] = principal
    archive_attempt(node, reopened=dict(actor, reason=reason, t_exec=t_exec))
    _set_state(node, 'testing', t_exec, reopen_reason=reason, previous_build=previous_build, **actor)
    return True, 'node %s reopened for %s; fresh evidence and confirmations are required' % (t_node, reason)


@contextmanager
def tree_lock(path):
    """Serialize whole-file edits across CLI/step-runner processes."""
    with open(path + '.lock', 'a+b') as lock:
        if os.name == 'nt':
            import msvcrt
            lock.seek(0)
            msvcrt.locking(lock.fileno(), msvcrt.LK_LOCK, 1)
        else:
            import fcntl
            fcntl.flock(lock, fcntl.LOCK_EX)
        # Closing the handle releases the lock, including on errors.
        yield


def save_tree(tree, path):
    tmp = None
    try:
        with tempfile.NamedTemporaryFile(mode='w', encoding='utf-8', newline='\n',
                                         dir=os.path.dirname(os.path.abspath(path)), suffix='.tmp', delete=False) as f:
            tmp = f.name
            json.dump(tree, f, ensure_ascii=False, indent=2)
            f.write('\n')
        os.replace(tmp, path)
    finally:
        if tmp and os.path.exists(tmp):
            os.unlink(tmp)


def edit_tree(path, t_node, role, who, edit, *, root=None, manifest_path=None,
              dry_run=False, test_context=None):
    path = os.path.realpath(path)
    base = root or os.path.dirname(path)
    with tree_lock(path):
        tree = load_tree(path)
        principal, roles = authorize(tree, path, role, who)
        if test_context is not None and test_context != (
                find_node(tree, t_node), tree.get('build'), tree.get('role_policy')):
            raise Refused('the node or task-tree configuration changed while testing; rerun the node')
        manifest = load_manifest(manifest_path) if manifest_path else None
        changed, message = edit(tree, base, manifest, principal)
        if roles:
            confirmations = find_node(tree, t_node).get('confirmations', {})
            for confirmed_role, confirmation in confirmations.items():
                if (confirmed_role not in roles or not isinstance(confirmation, dict)
                        or confirmation.get('principal') != roles[confirmed_role]):
                    raise Refused('the %s confirmation predates the current role policy; retest the node'
                                  % confirmed_role)
        problems, summary = validate(tree, base, manifest, evidence_node=t_node)
        errors = [str(p) for p in problems if p.severity == 'ERROR']
        if errors:
            raise Refused('\n'.join(errors))
        if changed and not dry_run:
            save_tree(tree, path)
        return message, summary


def _write_command(a):
    if not a.node:
        print('[task_tree] --node is required for %s' % a.command, file=sys.stderr)
        return 2

    def apply(tree, root, manifest, principal):
        if a.command == 'reopen':
            return reopen(tree, a.node, a.reason, a.who, a.t_exec or None, principal=principal)
        return record(tree, a.node, a.role, a.verdict, a.who, a.evidence,
                      a.source, a.t_exec or None, a.note, build=a.build, attempt_id=a.attempt,
                      root=root, manifest=manifest, principal=principal)

    try:
        message, summary = edit_tree(a.tree, a.node, 'lead' if a.command == 'reopen' else a.role,
                                     a.who, apply, root=a.root, manifest_path=a.manifest, dry_run=a.dry_run)
    except (Refused, PermissionError) as e:
        print('[task_tree] refused: %s' % e, file=sys.stderr)
        return 1
    except (OSError, ValueError) as e:
        print('[task_tree] cannot update: %s' % e, file=sys.stderr)
        return 2
    print('[task_tree] %s%s' % (message, ' (dry-run, nothing written)' if a.dry_run else ''))
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
    ap.add_argument('--build', help='record: build ID for a new tester pass, or expected build for review')
    ap.add_argument('--attempt', help='record: review the specified tester attempt ID')
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
    if failed:
        summary['overall_passed'] = False

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
                if kwargs['role'] in ('developer', 'lead'):
                    kwargs = dict(kwargs, attempt_id=t['nodes'][1].get('attempt', {}).get('id'))
                record(t, 'A1', root=tmp, **kwargs)
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

    tester = dict(role='tester', verdict='pass', who='tester', evidence=['fresh.png'], build='demo-v1')
    with open(os.path.join(tmp, 'fresh.png'), 'wb') as f:
        f.write(b'fresh evidence')
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


    _check_edits(tmp, tree, cases)
    bad = [c for c in cases if not c[1]]
    for name, ok, probs in cases:
        print('%s  %s' % ('PASS ' if ok else 'FAIL ', name))
    probs, summary = validate(tree, tmp, None)
    allpass = summarize({'nodes': [dict(n, state='passed') for n in tree['nodes']], 'lines': tree['lines']})
    print('[task_tree] selfcheck %d/%d, overall=%s, partial=%s'
          % (len(cases) - len(bad), len(cases), allpass['overall_passed'], summary['overall_passed']))
    return 0 if not bad and allpass['overall_passed'] and not summary['overall_passed'] else 1


def _check_edits(tmp, tree, cases):
    from contextlib import redirect_stdout, redirect_stderr
    from io import StringIO
    from pathlib import Path
    from role_policy import current_principal

    path = Path(tmp) / 'edits.json'
    save_tree(tree, str(path))

    def command(action, *args):
        with redirect_stdout(StringIO()), redirect_stderr(StringIO()):
            return main([action, '--tree', str(path), '--node', 'A1', *args])

    def sign(role, *args):
        return command('record', '--role', role, '--who', role, *args)

    def active():
        return find_node(load_tree(path), 'A1')

    def unchanged(name, fn):
        before = path.read_bytes()
        rc = fn()
        cases.append((name, rc != 0 and before == path.read_bytes(), ['rc=%s' % rc]))

    unchanged('missing evidence leaves the tree untouched',
              lambda: sign('tester', '--build', 'one', '--evidence', 'missing.png'))
    rc = sign('tester', '--build', 'one', '--evidence', 'fresh.png')
    attempt = active()['attempt']['id']
    cases.append(('tester seals the active evidence', rc == 0 and bool(attempt), []))
    unchanged('review on another build leaves no confirmation',
              lambda: sign('developer', '--attempt', attempt, '--build', 'two'))
    unchanged('review without an explicit attempt is refused',
              lambda: sign('developer'))
    rc = sign('developer', '--attempt', attempt)
    assert rc == 0

    evidence = Path(tmp) / 'fresh.png'
    original = evidence.read_bytes()
    evidence.write_bytes(b'drift')
    unchanged('changed evidence blocks final approval',
              lambda: sign('lead', '--attempt', attempt))
    evidence.write_bytes(original)
    manifest_path = Path(tmp, 'manifest.json')
    manifest_path.write_text(json.dumps({'entries': [{'path': str(evidence), 'sha256': 'incorrect'}]}))
    unchanged('approval respects the supplied evidence manifest',
              lambda: sign('lead', '--attempt', attempt, '--manifest', str(manifest_path)))
    assert sign('lead', '--attempt', attempt) == 0
    assert command('reopen', '--reason', 'code_change', '--who', 'lead') == 0
    reopened = active()
    cases.append(('reopen archives the old attempt and clears current approvals',
                  reopened['state'] == 'testing' and 'confirmations' not in reopened
                  and 'evidence' not in reopened and reopened['previous_attempts'][-1]['attempt']['id'] == attempt, []))
    unchanged('reopen refuses a lead approval from the previous attempt',
              lambda: sign('lead', '--attempt', attempt))
    unchanged('reopen refuses reuse of the previous evidence path',
              lambda: sign('tester', '--build', 'two', '--evidence', 'fresh.png'))

    Path(tmp, 'retest.png').write_bytes(original)
    unchanged('code-change retest refuses the previous build',
              lambda: sign('tester', '--build', 'one', '--evidence', 'retest.png'))
    context = (reopened, None, None)
    assert sign('tester', '--build', 'two', '--evidence', 'retest.png') == 0
    before = path.read_bytes()
    try:
        edit_tree(path, 'A1', 'tester', 'tester', lambda *args: (True, 'stale'),
                  test_context=context)
        stale_refused = False
    except Refused:
        stale_refused = True
    cases.append(('a step runner cannot publish against a node changed during testing',
                  stale_refused and path.read_bytes() == before, []))
    new_attempt = active()['attempt']['id']
    unchanged('in-flight review of a replaced attempt is refused',
              lambda: sign('developer', '--attempt', attempt))
    assert sign('developer', '--attempt', new_attempt) == 0
    rc = sign('lead', '--attempt', new_attempt)
    cases.append(('fresh retest can complete all three confirmations',
                  rc == 0 and active()['state'] == 'passed' and attempt != new_attempt, []))

    principal = current_principal()
    other = 'uid:2147483647' if os.name != 'nt' else 'S-1-5-21-1-2-3-2147483647'
    third = 'uid:2147483646' if os.name != 'nt' else 'S-1-5-21-1-2-3-2147483646'
    policy_path = Path(tmp) / 'roles.json'
    policy_path.write_text(json.dumps({'lead': principal, 'tester': other, 'developer': third}))
    configured = load_tree(path)
    configured['role_policy'] = policy_path.name
    save_tree(configured, str(path))
    rc = command('reopen', '--reason', 'user_bug', '--who', 'lead')
    cases.append(('host role policy records the assigned lead account',
                  rc == 0 and active()['history'][-1]['principal'] == principal, []))
    unchanged('host role policy refuses a tester verdict from the lead account',
              lambda: sign('tester', '--build', 'two', '--evidence', 'shot.png'))


if __name__ == '__main__':
    sys.exit(main())
