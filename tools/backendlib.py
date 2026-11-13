#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""One way to call any backend (scripts/backends/CONTRACT.md).

Every tool (probes, step runner, HUD walker, anchor check) goes through `run_action`, so a
backend is selected in exactly one place: the `backend` field of playtest.json.

  backend_path (config)  -> explicit adapter script, relative to the config file or the plugin root
  backend      (config)  -> name looked up in plugin.json "backends" (default: "windows")

The adapter is run as `<runner> <adapter> -Action <a> [-Value <v>] -Config <config>`; the runner
is chosen by file extension (.ps1 -> powershell, .py -> this Python). The adapter's LAST stdout
line is one JSON object; exit code 0 = ok, 3 = unsupported, anything else = error.
"""
import json
import os
import shutil
import subprocess
import sys

PLUGIN_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DEFAULT_BACKEND = "windows"


class BackendError(RuntimeError):
    """The backend ran and reported a failure (or could not be run)."""


class BackendUnsupported(BackendError):
    """The backend explicitly does not implement this action (exit 3 / "unsupported": true)."""


def load_config(path):
    """Load playtest.json, remember where it came from, apply v1 field fallbacks."""
    p = os.path.abspath(path)
    if not os.path.exists(p):
        raise BackendError("config not found: %s" % p)
    with open(p, encoding="utf-8-sig") as f:
        cfg = json.load(f)
    if not isinstance(cfg, dict):
        raise BackendError("config must be a JSON object: %s" % p)
    cfg["__config_path"] = p
    if "hint_region" in cfg and not (cfg.get("capture") or {}).get("crop_hint"):
        cfg.setdefault("capture", {})["crop_hint"] = cfg["hint_region"]
    if "shot_dir" in cfg and not (cfg.get("evidence") or {}).get("dir"):
        cfg.setdefault("evidence", {})["dir"] = cfg["shot_dir"]
    return cfg


def registered_backends(plugin_root=PLUGIN_ROOT):
    try:
        with open(os.path.join(plugin_root, "plugin.json"), encoding="utf-8-sig") as f:
            return {b["name"]: b for b in json.load(f).get("backends", []) if b.get("name") and b.get("path")}
    except (OSError, ValueError):
        return {}


def resolve_backend(cfg, plugin_root=PLUGIN_ROOT):
    """Return the absolute adapter path for this config."""
    explicit = cfg.get("backend_path")
    if explicit:
        bases = [os.path.dirname(cfg.get("__config_path") or ""), plugin_root]
        cands = [explicit] if os.path.isabs(explicit) else [os.path.join(b, explicit) for b in bases if b]
        for c in cands:
            if os.path.isfile(c):
                return os.path.abspath(c)
        raise BackendError("backend_path not found: %s" % explicit)
    name = cfg.get("backend") or DEFAULT_BACKEND
    if not isinstance(name, str):
        raise BackendError("config.backend must be a backend name (string)")
    reg = registered_backends(plugin_root)
    if name not in reg:
        raise BackendError("unknown backend '%s' (registered in plugin.json: %s; or set backend_path)"
                           % (name, ", ".join(sorted(reg)) or "none"))
    path = os.path.join(plugin_root, reg[name]["path"].replace("/", os.sep))
    if not os.path.isfile(path):
        raise BackendError("backend '%s' adapter missing: %s" % (name, path))
    return path


def runner_for(adapter):
    ext = os.path.splitext(adapter)[1].lower()
    if ext == ".ps1":
        exe = shutil.which("powershell") or shutil.which("pwsh")
        if not exe:
            raise BackendError("this backend needs PowerShell, which is not on PATH: %s" % adapter)
        return [exe, "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", adapter]
    if ext == ".py":
        return [sys.executable, "-B", adapter]
    return [adapter]


def parse_result(stdout):
    """The last stdout line that is a JSON object, or None (legacy backends)."""
    for line in reversed((stdout or "").replace("\r", "\n").split("\n")):
        line = line.strip()
        if line.startswith("{") and line.endswith("}"):
            try:
                obj = json.loads(line)
            except ValueError:
                continue
            if isinstance(obj, dict):
                return obj
    return None


def run_action(cfg, action, value="", timeout=120):
    """Run one backend action. Returns the result dict (always has "ok": True and "raw").

    Raises BackendUnsupported when the backend does not implement the action, BackendError otherwise.
    """
    adapter = resolve_backend(cfg)
    cmd = runner_for(adapter) + ["-Action", action]
    if value != "" and value is not None:
        cmd += ["-Value", str(value)]
    if cfg.get("__config_path"):
        cmd += ["-Config", cfg["__config_path"]]
    try:
        proc = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=timeout,
                              cwd=cfg.get("__cwd") or None)
    except subprocess.TimeoutExpired:
        raise BackendError("backend %s timed out after %ss" % (action, timeout))
    except OSError as e:
        raise BackendError("cannot run backend %s: %s" % (adapter, e))
    out = (proc.stdout or b"").decode("utf-8", "replace")
    err = (proc.stderr or b"").decode("utf-8", "replace").strip()
    res = parse_result(out)
    unsupported = proc.returncode == 3 or bool(res and res.get("unsupported")) or \
        (res is None and out.strip().upper().startswith("UNSUPPORTED"))
    if unsupported:
        raise BackendUnsupported("backend does not support '%s'" % action)
    if proc.returncode != 0 or (res is not None and res.get("ok") is False):
        detail = (res or {}).get("error") or err or out.strip()[-400:] or "no output"
        raise BackendError("backend %s failed (rc=%d): %s" % (action, proc.returncode, detail))
    res = dict(res) if res else {}
    res["ok"] = True
    res["raw"] = out
    return res
