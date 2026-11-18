"""Optional OS-principal checks for role-specific writes."""
import csv
import json
import os
import subprocess


def current_principal():
    if os.name != 'nt':
        return 'uid:%d' % os.geteuid()
    import ctypes
    directory = ctypes.create_unicode_buffer(32768)
    size = ctypes.windll.kernel32.GetSystemDirectoryW(directory, len(directory))
    if not size or size >= len(directory):
        raise PermissionError('could not locate the Windows system directory')
    whoami = os.path.join(directory.value, 'whoami.exe')
    result = subprocess.run([whoami, '/user', '/fo', 'csv', '/nh'], capture_output=True,
                            text=True, errors='replace', check=True)
    for row in csv.reader(result.stdout.splitlines()):
        if len(row) == 2 and row[1].startswith('S-1-'):
            return row[1]
    raise PermissionError('could not determine the current Windows account SID')


def authorize(tree, tree_path, role, who):
    if 'role_policy' not in tree:
        return None, None
    path = tree['role_policy']
    if not isinstance(path, str) or not path.strip():
        raise PermissionError('role_policy must identify the host-managed policy file')
    path = os.path.join(os.path.dirname(tree_path), path)
    try:
        with open(path, encoding='utf-8-sig') as f:
            roles = json.load(f)
    except (OSError, ValueError) as e:
        raise PermissionError('cannot load role policy: %s' % e) from e
    required = {'tester', 'developer', 'lead'}
    if (not isinstance(roles, dict) or roles.keys() != required
            or not all(isinstance(value, str) and value.strip() for value in roles.values())
            or len(set(roles.values())) != len(required)):
        raise PermissionError('role policy requires three distinct OS principals: tester, developer, lead')
    try:
        principal = current_principal()
    except (OSError, subprocess.SubprocessError) as e:
        raise PermissionError('could not determine the process identity: %s' % e) from e
    if roles.get(role) != principal:
        raise PermissionError('this account cannot write verdicts as %s (%s)' % (role, who))
    return principal, roles
