#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Backend access for the verify tools (step runner, HUD walker, anchor check).

`load_backend(path)` accepts either kind of config and returns one object API:

1. playtest.json (recommended) - has `backend` / `backend_path` / `launch`. Every action is
   dispatched through tools/backendlib.py to the backend registered in plugin.json, i.e. the
   same adapter the tester drives by hand (scripts/backends/CONTRACT.md).

2. legacy per-action command config (v3.2):
   {
     "name": "my-engine",
     "state": {"cmd": ["python", "backend_state.py"], "timeout": 20},
     "keys":  {"cmd": ["python", "backend_keys.py", "{value}"]},
     "shot":  {"cmd": ["python", "backend_shot.py", "{value}"]}
   }
   `{value}` is replaced by the action value. A missing action is UNSUPPORTED.
"""
import json
import os
import subprocess
import sys

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
import backendlib  # noqa: E402
from backendlib import BackendError, BackendUnsupported  # noqa: E402,F401

UNSUPPORTED = 'UNSUPPORTED'
LEGACY_ACTIONS = ('state', 'keys', 'shot', 'failure_snapshot', 'test_fast', 'read_text',
                  'click', 'type', 'scroll', 'hold')


class ConfigError(Exception):
    """The backend config is missing or unusable (tools exit with code 2)."""


class Backend(object):
    def __init__(self, config_path):
        if not config_path or not os.path.exists(config_path):
            raise ConfigError('backend config not found: %s' % config_path)
        try:
            with open(config_path, encoding='utf-8-sig') as f:
                self.config = json.load(f)
        except ValueError as e:
            raise ConfigError('backend config is not valid JSON: %s (%s)' % (config_path, e))
        if not isinstance(self.config, dict):
            raise ConfigError('backend config must be a JSON object: %s' % config_path)
        self.name = self.config.get('name', os.path.basename(config_path))
        legacy = any(isinstance(self.config.get(a), dict) and self.config[a].get('cmd') for a in LEGACY_ACTIONS)
        if legacy:
            self.mode = 'cmd'
        elif any(k in self.config for k in ('backend', 'backend_path', 'launch')):
            self.mode = 'contract'
            try:
                self.cfg = backendlib.load_config(config_path)
                backendlib.resolve_backend(self.cfg)
            except BackendError as e:
                raise ConfigError(str(e))
        else:
            raise ConfigError('not a backend config (expected playtest.json with "backend"/"launch", '
                              'or per-action {"cmd": [...]} entries): %s' % config_path)

    # ---- generic: run one action, return a result dict, raise BackendError / BackendUnsupported
    def act(self, action, value=''):
        if self.mode == 'contract':
            return backendlib.run_action(self.cfg, action, value)
        spec = self.config.get(action)
        if not isinstance(spec, dict) or not spec.get('cmd'):
            raise BackendUnsupported("backend does not support '%s'" % action)
        cmd = spec['cmd']
        if isinstance(cmd, str):
            cmd = [cmd]
        cmd = [c.replace('{value}', str(value)) for c in cmd]
        try:
            p = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=spec.get('timeout', 30))
        except Exception as e:
            raise BackendError('backend %s could not run: %s' % (action, e))
        out = (p.stdout or b'').decode('utf-8', 'replace').strip()
        err = (p.stderr or b'').decode('utf-8', 'replace').strip()
        if p.returncode == 3 or out.upper().startswith(UNSUPPORTED):
            raise BackendUnsupported("backend does not support '%s'" % action)
        if p.returncode != 0:
            raise BackendError('backend %s failed (rc=%d): %s' % (action, p.returncode, err or out))
        res = backendlib.parse_result(out) or {}
        res['raw'] = out
        return res

    def evidence_dir(self):
        cfg = self.config
        d = (cfg.get('evidence') or {}).get('dir') or cfg.get('shot_dir') or ''
        return os.path.abspath(d) if d else ''

    # ---- observation
    def state(self):
        """Current state dict. {'unsupported': True} when the backend cannot export state,
        {'error': msg} when the export failed."""
        try:
            res = self.act('state')
        except BackendUnsupported as e:
            return {'unsupported': True, 'raw': str(e)}
        except BackendError as e:
            return {'error': str(e)}
        if isinstance(res.get('state'), dict):
            return res['state']
        if self.mode == 'cmd':  # legacy: stdout IS the state JSON
            try:
                st = json.loads(res.get('raw') or '')
                if isinstance(st, dict):
                    return st
            except ValueError:
                pass
        return {'error': 'state output is not a JSON object: %s' % (res.get('raw') or '')[:200]}

    def read_text(self, value=''):
        """Visible text, or None when unsupported."""
        try:
            res = self.act('read_text', value)
        except BackendUnsupported:
            return None
        return res.get('text', res.get('raw', ''))

    # ---- string-returning helpers used by the HUD walker ('ok' / path / 'ERROR: ...' / UNSUPPORTED)
    def _text(self, action, value):
        try:
            res = self.act(action, value)
        except BackendUnsupported:
            return UNSUPPORTED
        except BackendError as e:
            return 'ERROR: %s' % e
        return str(res.get('path') or res.get('raw') or 'ok')

    def press(self, key, hold_ms=60, gap_ms=120):
        if self.mode == 'cmd':  # legacy value convention
            return self._text('keys', '%s,%s,%s' % (key, hold_ms, gap_ms))
        return self._text('keys', key)

    def shot(self, name='shot'):
        return self._text('shot', name)

    def failure_snapshot(self, name='fail'):
        return self._text('failure_snapshot', name)

    def test_fast(self, on=True):
        return self._text('test_fast', 'on' if on else 'off')


def load_backend(path):
    """Backend for a config file. Raises ConfigError when the file is missing or unusable."""
    return Backend(path)
