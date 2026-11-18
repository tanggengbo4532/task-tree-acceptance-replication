"""Run a failed Web acceptance attempt, then retest and record three confirmations."""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import sys
import tempfile


ROOT = Path(__file__).resolve().parents[1]
VERIFY = ROOT / 'tools' / 'verify'
sys.path.insert(0, str(ROOT / 'tools'))
import backendlib


def write_json(path, data):
    path.write_text(json.dumps(data, indent=2) + '\n', encoding='utf-8')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--browser', default='', help='Edge, Chrome, or an executable path')
    args = parser.parse_args()
    work = Path(tempfile.mkdtemp(prefix='game-playtest-demo-'))
    print('Demo artifacts: %s' % work, flush=True)
    fixture = ROOT / 'tests' / 'fixtures' / 'webapp' / 'index.html'
    build = 'notes-' + hashlib.sha256(fixture.read_bytes()).hexdigest()
    tree = work / 'task-tree.json'
    node_id = 'A1'
    write_json(tree, {'schema': 1, 'project': 'notes-quickstart', 'version': '1',
                      'build': build, 'lines': [{'id': 'A', 'type': 'main'}],
                      'nodes': [{'t_node': node_id, 'line': 'A', 'who': 'user',
                                 'where': 'Sign-in page', 'action': 'Sign in and see the notes list',
                                 'requires': [], 'state': 'not_started'}]})
    config_path = work / 'playtest.json'
    evidence = work / 'evidence'
    write_json(config_path, {'backend': 'web', 'launch': str(fixture),
                             'web': {'headless': True, 'browser': args.browser},
                             'evidence': {'dir': str(evidence)}})
    config = backendlib.load_config(config_path)
    config['__cwd'] = str(work)

    def tool(script, *arguments, expect=0):
        result = subprocess.run([sys.executable, '-B', str(VERIFY / script), *map(str, arguments)],
                                cwd=work, capture_output=True, encoding='utf-8', errors='replace')
        if result.returncode != expect:
            raise RuntimeError('%s: expected exit %d, got %d\n%s%s' %
                               (script, expect, result.returncode, result.stdout, result.stderr))
        return result.stdout

    def run_signin(password, expected_exit):
        spec = json.loads((ROOT / 'examples' / 'steps' / 'notes-A1.json').read_text(encoding='utf-8'))
        spec['steps'][3]['value'] = password
        spec_path = work / ('steps-retry.json' if expected_exit == 0 else 'steps-first.json')
        write_json(spec_path, spec)
        try:
            backendlib.run_action(config, 'launch')
            output = tool('step_runner.py', '--backend', config_path, '--steps', spec_path, '--tree', tree,
                          '--who', 'demo-tester', '--jsonl', work / 'input.jsonl', expect=expected_exit)
            return json.JSONDecoder().raw_decode(output)[0]
        finally:
            if (work / '.playtest_web.json').exists():
                backendlib.run_action(config, 'close')

    def record(role, *arguments, expect=0):
        return tool('task_tree.py', 'record', '--tree', tree, '--node', node_id,
                    '--role', role, '--who', 'demo-' + role, *arguments, expect=expect)

    first = run_signin('wrong', expected_exit=1)
    snapshot = Path(first.get('snapshot') or '') / 'manifest.json'
    if first.get('failed_step') != 5 or not snapshot.is_file():
        raise RuntimeError('the demo must fail at sign-in and retain its failure snapshot')
    record('tester', '--verdict', 'reject', '--build', build, '--evidence', snapshot,
           '--note', 'The sample invalid password kept the user on the sign-in page.')
    print('1. Sign-in failed. Inspect the failure snapshot in %s' % snapshot.parent)

    second = run_signin('secret', expected_exit=0)
    node = json.loads(tree.read_text(encoding='utf-8'))['nodes'][0]
    if node['state'] != 'testing' or set(node['confirmations']) != {'tester'}:
        raise RuntimeError('a successful test must leave the node waiting for review')
    attempt = node['attempt']['id']
    print('2. Retest succeeded. Tester evidence: %s' % second['final_evidence'])
    record('lead', '--attempt', attempt, expect=1)
    record('developer', '--attempt', attempt)
    record('lead', '--attempt', attempt)
    print('3. Demo Developer and Lead confirmed the tester attempt in order.')
    print(tool('task_tree.py', 'status', '--tree', tree, '--strict').strip())
    return 0


if __name__ == '__main__':
    try:
        sys.exit(main())
    except (OSError, RuntimeError, ValueError) as error:
        print('Demo failed: %s' % error, file=sys.stderr)
        sys.exit(1)
