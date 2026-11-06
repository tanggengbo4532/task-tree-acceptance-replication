#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""v3.2 verification backend 抽象（引擎无关）。

Backend 配置（JSON，来自 playtest.json 的 backend 段或独立文件）：
{
  "name": "godot-pal98",
  "state":  {"cmd": ["python","backend_state.py"], "timeout": 20},
  "keys":   {"cmd": ["python","backend_keys.py"]},
  "shot":   {"cmd": ["python","backend_shot.py"], "timeout": 20},
  "failure_snapshot": {"cmd": [...]},      # 可选
  "test_fast": {"cmd": [...]}              # 可选；on/off 由调用方追加
}
所有 cmd 支持占位符 {value}：keys 传 key/ms；shot 传 name；test_fast 传 on/off。
state 必须输出现状 JSON（见 CONTRACT §6.1）；缺失能力显式返回 UNSUPPORTED。
"""
import json
import os
import subprocess
import sys

UNSUPPORTED = 'UNSUPPORTED'


class Backend:
    def __init__(self, config_path):
        self.config = {}
        self.name = 'unknown'
        if config_path and os.path.exists(config_path):
            with open(config_path, encoding='utf-8') as f:
                self.config = json.load(f)
            self.name = self.config.get('name', os.path.basename(config_path))

    def _run(self, action, value=None):
        spec = self.config.get(action)
        if not spec:
            return UNSUPPORTED
        cmd = spec.get('cmd')
        if not cmd:
            return UNSUPPORTED
        if isinstance(cmd, str):
            cmd = [cmd]
        if value is not None:
            cmd = [c.replace('{value}', str(value)) for c in cmd]
        timeout = spec.get('timeout', 30)
        try:
            p = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=timeout)
        except Exception as e:
            return 'ERROR: %s' % e
        out = (p.stdout or b'').decode('utf-8', 'replace').strip()
        err = (p.stderr or b'').decode('utf-8', 'replace').strip()
        return out if p.returncode == 0 else 'ERROR: ' + (err or out)

    def state(self):
        raw = self._run('state')
        if raw == UNSUPPORTED:
            return {'unsupported': True, 'raw': raw}
        try:
            return json.loads(raw)
        except Exception:
            return {'unsupported': True, 'raw': raw}

    def press(self, key, hold_ms=60, gap_ms=120):
        return self._run('keys', '%s,%s,%s' % (key, hold_ms, gap_ms))

    def shot(self, name='shot'):
        return self._run('shot', name)

    def failure_snapshot(self, name='fail'):
        return self._run('failure_snapshot', name)

    def test_fast(self, on=True):
        return self._run('test_fast', 'on' if on else 'off')


def load_backend(arg):
    """arg 可以是 config json 路径；也支持 --backend name 时从 playtest.json 查找。
    为简化：直接必须是 JSON 文件路径；不存在则返回空 Backend（显式 UNSUPPORTED）。"""
    return Backend(arg)
