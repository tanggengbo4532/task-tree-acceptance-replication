"""Check single-node reopen, three-role sign-off, and checkpoint evidence."""
import argparse
import json
from pathlib import Path
import subprocess
import sys
import tempfile


ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'tools'))
sys.path.insert(0, str(ROOT / 'tools' / 'verify'))
import backendlib
import step_runner


def write(path, data):
    path.write_text(json.dumps(data, ensure_ascii=False), encoding='utf-8')
    return path


def read(path):
    return json.loads(path.read_text(encoding='utf-8'))


def tool(work, name, *args, rc=0):
    command = [sys.executable, '-B', str(ROOT / 'tools' / 'verify' / name), *map(str, args)]
    result = subprocess.run(command, cwd=work, capture_output=True, encoding='utf-8', errors='replace')
    assert result.returncode == rc, (command, result.returncode, result.stdout, result.stderr)
    return result.stdout, result.stderr


def make_tree(work, *nodes):
    work.mkdir()
    return write(work / 'task-tree.json', {
        'schema': 1, 'project': 'acceptance-fixture', 'version': '1', 'build': 'notes-v1',
        'lines': [{'id': 'A', 'type': 'main'}],
        'nodes': [dict(line='A', who='user', where='start', action='reach the notes list',
                       state='not_started', **node) for node in nodes],
    })


def node(tree, node_id='A1'):
    return next(item for item in read(tree)['nodes'] if item['t_node'] == node_id)


def sign(tree, role, *args, node_id='A1', rc=0):
    return tool(tree.parent, 'task_tree.py', 'record', '--tree', tree, '--node', node_id,
                '--who', role, '--role', role, *args, rc=rc)


def check_review_and_reopen(work):
    tree = make_tree(work, {'t_node': 'A1'}, {'t_node': 'A2', 'requires': ['A1']},
                     {'t_node': 'A3', 'requires': ['A2']}, {'t_node': 'B1'})
    for node_id in ('A1', 'A2', 'A3', 'B1'):
        evidence = work / (node_id + '.txt')
        evidence.write_text(node_id, encoding='utf-8')
        sign(tree, 'tester', '--evidence', evidence, node_id=node_id)
        pending = node(tree, node_id)
        assert pending['state'] == 'testing' and set(pending['confirmations']) == {'tester'}
        review = ('--attempt', pending['attempt']['id'])
        _, error = sign(tree, 'lead', *review, node_id=node_id, rc=1)
        assert 'requires a current developer pass' in error
        _, error = sign(tree, 'developer', *review, '--source', 'tool', node_id=node_id, rc=1)
        assert 'a tool may only record the tester verdict' in error
        assert node(tree, node_id) == pending
        sign(tree, 'developer', *review, node_id=node_id)
        assert node(tree, node_id)['state'] == 'testing'
        sign(tree, 'lead', *review, node_id=node_id)
        assert node(tree, node_id)['state'] == 'passed'

    previous = read(tree)['nodes']
    tool(work, 'task_tree.py', 'reopen', '--tree', tree, '--node', 'A1',
         '--reason', 'user_bug', '--who', 'lead')
    reopened = read(tree)['nodes']
    assert reopened[0]['state'] == 'testing'
    assert reopened[0]['previous_attempts'][-1]['attempt'] == previous[0]['attempt']
    assert reopened[1:] == previous[1:]


def check_missing_evidence(work):
    tree = make_tree(work, {'t_node': 'A1', 'checkpoints': [1]})
    screenshot = work / 'final.png'
    screenshot.write_bytes(b'final')
    initial_tree = tree.read_bytes()
    _, error = sign(tree, 'tester', '--evidence', screenshot, rc=1)
    assert 'required checkpoint evidence' in error and tree.read_bytes() == initial_tree
    _, error = sign(tree, 'tester', '--evidence', screenshot, '--source', 'tool', rc=1)
    assert 'required checkpoint evidence' in error and tree.read_bytes() == initial_tree

    class MissingCheckpointShot(step_runner.MockApp):
        def shot(self, name):
            if name.endswith('_s01'):
                return 'ERROR: checkpoint capture unavailable'
            return str(screenshot)

    mock = MissingCheckpointShot()
    code, result = step_runner.run(mock, step_runner.SELFCHECK_STEPS, out_dir=str(work), checkpoints=[2])
    assert code == 2 and 'must precede the final step' in result['error'] and mock.typed == ''
    code, result = step_runner.run(mock, step_runner.SELFCHECK_STEPS, out_dir=str(work), checkpoints=[1])
    assert code == 1 and result['failed_step'] == 1
    assert 'missing required screenshot' in result['reasons'][0]


def check_web_checkpoint(work):
    tree = make_tree(work, {'t_node': 'A1', 'checkpoints': [2]})
    steps = ROOT / 'examples' / 'steps' / 'notes-A1.json'
    fixture = ROOT / 'tests' / 'fixtures' / 'webapp' / 'index.html'
    config = write(work / 'playtest.json', {'backend': 'web', 'launch': str(fixture),
                                           'web': {'headless': True},
                                           'evidence': {'dir': str(work / 'evidence')}})
    cfg = backendlib.load_config(config)
    cfg['__cwd'] = str(work)
    try:
        backendlib.run_action(cfg, 'launch')
        output, _ = tool(work, 'step_runner.py', '--backend', config, '--steps', steps, '--tree', tree)
        assert json.JSONDecoder().raw_decode(output)[0]['tester_recorded']
    finally:
        if (work / '.playtest_web.json').exists():
            backendlib.run_action(cfg, 'close')

    pending = node(tree)
    attempt = pending['attempt']
    assert pending['state'] == 'testing' and set(pending['confirmations']) == {'tester'}
    frames = attempt['checkpoint_evidence']
    assert [frame['step'] for frame in frames] == [0, 2, 5]
    assert all(Path(frame['path']).is_file() and frame['path'] in attempt['sha256'] for frame in frames)
    checkpoint = Path(frames[1]['path'])
    image = checkpoint.read_bytes()
    checkpoint.write_bytes(image + b'changed')
    _, error = sign(tree, 'developer', '--attempt', attempt['id'], rc=1)
    assert 'evidence changed' in error and node(tree) == pending
    checkpoint.write_bytes(image)
    sign(tree, 'developer', '--attempt', attempt['id'])
    sign(tree, 'lead', '--attempt', attempt['id'])
    assert node(tree)['state'] == 'passed'
    tool(work, 'task_tree.py', 'status', '--tree', tree, '--strict')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--offline', action='store_true', help='run only checks that do not require a browser')
    args = parser.parse_args()
    with tempfile.TemporaryDirectory(prefix='playtest-acceptance-') as temp:
        work = Path(temp)
        check_review_and_reopen(work / 'review')
        print('PASS  three-role sign-off and single-node reopen')
        check_missing_evidence(work / 'missing')
        print('PASS  missing checkpoint evidence prevents a tester verdict')
        if not args.offline:
            check_web_checkpoint(work / 'web')
            print('PASS  real Web checkpoints, evidence hashes, and three-role sign-off')


if __name__ == '__main__':
    main()
