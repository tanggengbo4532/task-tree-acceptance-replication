#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Web backend for game-playtest (CONTRACT.md): drives Edge/Chrome over the DevTools protocol.

No third-party dependency: a small stdlib WebSocket client talks CDP directly, so the
browser already on the machine (Edge on Windows, Chrome/Chromium elsewhere) is enough.

Black-box by construction:
  - input goes through CDP `Input.*` (trusted events, same path as a real keyboard/mouse);
  - `click css=...|text=...` only resolves WHERE to click; the click itself is a real mouse
    event at that point and is refused when the element is hidden, disabled or covered;
  - `state` / `read_text` expose only what a user can see (URL, title, visible text, focus).

Usage (same shape as the Windows backend):
  python adapter.py -Action launch -Config playtest.json
  python adapter.py -Action click  -Value "css=#submit" -Config playtest.json
Actions: launch close focus info keys hold diag click type scroll shot hint read_text state
Unsupported (exit 3): test_fast failure_snapshot
Output: the LAST stdout line is one JSON object {"ok":true|false,"action":...}.
Exit code: 0 ok / 1 error / 3 unsupported.
"""
import argparse
import base64
import json
import os
import shutil
import socket
import struct
import subprocess
import sys
import tempfile
import time
import urllib.parse
import urllib.request

STATE_FILE = ".playtest_web.json"
PROFILE_PREFIX = "playtest-web-"
UNSUPPORTED_ACTIONS = ("test_fast", "failure_snapshot")


class BackendError(Exception):
    pass


# ---------------------------------------------------------------- websocket / CDP
class WS(object):
    """Minimal RFC 6455 client (text frames, fragmentation, ping/pong) - enough for CDP."""

    def __init__(self, url, timeout=30):
        u = urllib.parse.urlparse(url)
        self.sock = socket.create_connection((u.hostname, u.port), timeout)
        key = base64.b64encode(os.urandom(16)).decode("ascii")
        path = u.path + (("?" + u.query) if u.query else "")
        req = ("GET %s HTTP/1.1\r\nHost: %s:%d\r\nUpgrade: websocket\r\nConnection: Upgrade\r\n"
               "Sec-WebSocket-Key: %s\r\nSec-WebSocket-Version: 13\r\n\r\n" % (path, u.hostname, u.port, key))
        self.sock.sendall(req.encode("ascii"))
        self.buf = b""
        while b"\r\n\r\n" not in self.buf:
            chunk = self.sock.recv(4096)
            if not chunk:
                raise BackendError("websocket handshake: connection closed")
            self.buf += chunk
        head, self.buf = self.buf.split(b"\r\n\r\n", 1)
        if b" 101 " not in head.split(b"\r\n", 1)[0]:
            raise BackendError("websocket handshake rejected: %r" % head[:120])

    def _frame(self, opcode, payload):
        mask = os.urandom(4)
        n = len(payload)
        if n < 126:
            head = struct.pack("!BB", 0x80 | opcode, 0x80 | n)
        elif n < 65536:
            head = struct.pack("!BBH", 0x80 | opcode, 0x80 | 126, n)
        else:
            head = struct.pack("!BBQ", 0x80 | opcode, 0x80 | 127, n)
        masked = bytes(b ^ mask[i % 4] for i, b in enumerate(payload))
        self.sock.sendall(head + mask + masked)

    def send(self, text):
        self._frame(0x1, text.encode("utf-8"))

    def _read(self, n):
        while len(self.buf) < n:
            chunk = self.sock.recv(max(65536, n - len(self.buf)))
            if not chunk:
                raise BackendError("websocket closed by browser")
            self.buf += chunk
        out, self.buf = self.buf[:n], self.buf[n:]
        return out

    def recv(self):
        parts = []
        while True:
            b1, b2 = struct.unpack("!BB", self._read(2))
            opcode, fin, n = b1 & 0x0F, b1 & 0x80, b2 & 0x7F
            if n == 126:
                (n,) = struct.unpack("!H", self._read(2))
            elif n == 127:
                (n,) = struct.unpack("!Q", self._read(8))
            payload = self._read(n)
            if opcode == 0x9:
                self._frame(0xA, payload)
                continue
            if opcode == 0xA:
                continue
            if opcode == 0x8:
                raise BackendError("websocket closed by browser")
            parts.append(payload)
            if fin:
                return b"".join(parts).decode("utf-8", "replace")

    def close(self):
        try:
            self.sock.close()
        except OSError:
            pass


class CDP(object):
    def __init__(self, ws_url, timeout=30):
        self.ws = WS(ws_url, timeout)
        self.seq = 0

    def call(self, method, params=None):
        self.seq += 1
        mid = self.seq
        self.ws.send(json.dumps({"id": mid, "method": method, "params": params or {}}))
        while True:
            msg = json.loads(self.ws.recv())
            if msg.get("id") == mid:
                if "error" in msg:
                    raise BackendError("%s failed: %s" % (method, msg["error"].get("message")))
                return msg.get("result", {})

    def evaluate(self, expression):
        r = self.call("Runtime.evaluate", {"expression": expression, "returnByValue": True, "awaitPromise": True})
        if r.get("exceptionDetails"):
            d = r["exceptionDetails"]
            raise BackendError("page script error: %s" % (d.get("exception", {}).get("description") or d.get("text")))
        return r.get("result", {}).get("value")

    def close(self):
        self.ws.close()


# ---------------------------------------------------------------- config / state
def load_config(path):
    p = path if os.path.isabs(path) else os.path.join(os.getcwd(), path)
    if not os.path.exists(p):
        raise BackendError("config not found: %s" % p)
    with open(p, encoding="utf-8-sig") as f:
        return json.load(f)


def evidence_dir(cfg):
    d = (cfg.get("evidence") or {}).get("dir") or cfg.get("shot_dir") or "playtest_shots"
    os.makedirs(d, exist_ok=True)
    return os.path.abspath(d)


def free_path(directory, name, ext):
    """Evidence is append-only: an existing name gets a numeric suffix, never overwritten."""
    p = os.path.join(directory, name + ext)
    i = 2
    while os.path.exists(p):
        p = os.path.join(directory, "%s_%d%s" % (name, i, ext))
        i += 1
    return p


def log_input(cfg, action, value):
    try:
        rec = {"ts": time.strftime("%Y-%m-%dT%H:%M:%S"), "backend": "web", "action": action, "value": value, "method": "cdp-input"}
        with open(os.path.join(evidence_dir(cfg), "input-log.jsonl"), "a", encoding="ascii") as f:
            f.write(json.dumps(rec) + "\n")
    except OSError:
        pass


def read_state():
    if not os.path.exists(STATE_FILE):
        return None
    try:
        with open(STATE_FILE, encoding="utf-8") as f:
            return json.load(f)
    except (OSError, ValueError):
        return None


def http_json(port, path, timeout=2.0):
    with urllib.request.urlopen("http://127.0.0.1:%d%s" % (port, path), timeout=timeout) as r:
        return json.loads(r.read().decode("utf-8"))


def browser_alive(st):
    if not st:
        return False
    try:
        http_json(st["port"], "/json/version", 1.0)
        return True
    except Exception:
        return False


INTERNAL_SCHEMES = ("devtools://", "edge://", "chrome://", "chrome-extension://", "about:")


def page_targets(port):
    """App pages only: browser-internal pages (settings, sync prompts, devtools) are never driven."""
    return [t for t in http_json(port, "/json/list")
            if t.get("type") == "page" and not t.get("url", "").startswith(INTERNAL_SCHEMES)]


def connect(cfg):
    """Attach to the page opened by `launch` (falls back to the front app page if it navigated away/closed)."""
    st = read_state()
    if not browser_alive(st):
        raise BackendError("browser is not running (run launch first)")
    pages = page_targets(st["port"])
    if not pages:
        raise BackendError("no app page in the browser")
    page = next((t for t in pages if t.get("id") == st.get("target")), pages[0])
    return CDP(page["webSocketDebuggerUrl"]), len(pages)


def find_browser(cfg):
    want = (cfg.get("web") or {}).get("browser") or ""
    if want and os.path.isfile(want):
        return want
    pf = [os.environ.get("ProgramFiles", ""), os.environ.get("ProgramFiles(x86)", ""), os.environ.get("LOCALAPPDATA", "")]
    edge = [os.path.join(d, "Microsoft", "Edge", "Application", "msedge.exe") for d in pf if d]
    chrome = [os.path.join(d, "Google", "Chrome", "Application", "chrome.exe") for d in pf if d]
    mac = ["/Applications/Google Chrome.app/Contents/MacOS/Google Chrome",
           "/Applications/Microsoft Edge.app/Contents/MacOS/Microsoft Edge"]
    names = {"msedge": ["msedge", "microsoft-edge"], "edge": ["msedge", "microsoft-edge"],
             "chrome": ["chrome", "google-chrome", "chromium", "chromium-browser"]}
    order = edge + chrome if want.lower() in ("", "msedge", "edge") else chrome + edge
    for p in order + mac:
        if os.path.isfile(p):
            return p
    for n in names.get(want.lower(), []) + ["chrome", "google-chrome", "chromium", "chromium-browser", "msedge", "microsoft-edge"]:
        w = shutil.which(n)
        if w:
            return w
    raise BackendError("no Chromium-based browser found; set web.browser to the executable path")


def target_url(cfg):
    url = (cfg.get("web") or {}).get("url") or cfg.get("launch") or ""
    if not url:
        raise BackendError("config.launch (or web.url) must be the URL to open")
    if "://" in url:
        return url
    p = url if os.path.isabs(url) else os.path.join(os.getcwd(), url)
    if not os.path.exists(p):
        raise BackendError("launch is neither a URL nor an existing file: %s" % url)
    return "file:///" + urllib.parse.quote(os.path.abspath(p).replace("\\", "/").lstrip("/"), safe="/:")


# ---------------------------------------------------------------- keys
NAMED = {
    "ENTER": ("Enter", "Enter", 13, "\r"), "RETURN": ("Enter", "Enter", 13, "\r"),
    "SPACE": (" ", "Space", 32, " "), "ESC": ("Escape", "Escape", 27, None), "ESCAPE": ("Escape", "Escape", 27, None),
    "TAB": ("Tab", "Tab", 9, None), "BACKSPACE": ("Backspace", "Backspace", 8, None),
    "DELETE": ("Delete", "Delete", 46, None), "INSERT": ("Insert", "Insert", 45, None),
    "UP": ("ArrowUp", "ArrowUp", 38, None), "DOWN": ("ArrowDown", "ArrowDown", 40, None),
    "LEFT": ("ArrowLeft", "ArrowLeft", 37, None), "RIGHT": ("ArrowRight", "ArrowRight", 39, None),
    "HOME": ("Home", "Home", 36, None), "END": ("End", "End", 35, None),
    "PGUP": ("PageUp", "PageUp", 33, None), "PGDN": ("PageDown", "PageDown", 34, None),
    "SHIFT": ("Shift", "ShiftLeft", 16, None), "CTRL": ("Control", "ControlLeft", 17, None), "ALT": ("Alt", "AltLeft", 18, None),
}
for _i in range(1, 13):
    NAMED["F%d" % _i] = ("F%d" % _i, "F%d" % _i, 111 + _i, None)


def key_spec(name):
    raw = name.strip()
    n = raw.strip("{}").upper()
    if n in NAMED:
        return NAMED[n]
    if len(raw) == 1:
        c = raw
        if c.isalpha() and c.isascii():
            return (c, "Key" + c.upper(), ord(c.upper()), c)
        if c.isdigit():
            return (c, "Digit" + c, ord(c), c)
        return (c, "", 0, c)
    raise BackendError("unknown key: '%s' (use names like UP/DOWN/SPACE/ENTER/ESC/TAB/F1 or a single character; use 'type' for text)" % name)


def key_event(cdp, kind, spec, repeat=False):
    key, code, vk, text = spec
    p = {"type": kind, "key": key, "code": code, "windowsVirtualKeyCode": vk, "nativeVirtualKeyCode": vk}
    if kind == "keyDown":
        if text:
            p["text"] = text
        else:
            p["type"] = "rawKeyDown"
        if repeat:
            p["autoRepeat"] = True
    cdp.call("Input.dispatchKeyEvent", p)


def hold_keys(cdp, specs, ms):
    """Press, auto-repeat like a real keyboard (after 400 ms, every 40 ms), release in reverse order."""
    for s in specs:
        key_event(cdp, "keyDown", s)
    end = time.time() + ms / 1000.0
    first = time.time() + 0.4
    try:
        while time.time() < end:
            time.sleep(min(0.04, max(0.0, end - time.time())))
            if time.time() >= first and time.time() < end:
                key_event(cdp, "keyDown", specs[-1], repeat=True)
    finally:
        for s in reversed(specs):
            key_event(cdp, "keyUp", s)


# ---------------------------------------------------------------- element lookup (where to click)
LOCATE_JS = r"""
(function (kind, q) {
  var el = null;
  if (kind === 'css') {
    try { el = document.querySelector(q); } catch (e) { return {error: 'bad selector: ' + q}; }
  } else {
    var all = document.body ? document.body.querySelectorAll('*') : [], hits = [];
    for (var i = 0; i < all.length; i++) {
      var e = all[i], t = (e.innerText || e.value || '').trim();
      if (t === q) hits.push(e);
    }
    hits = hits.filter(function (e) { return !hits.some(function (o) { return o !== e && e.contains(o); }); });
    if (hits.length > 1) return {error: 'ambiguous: ' + hits.length + ' elements show the text "' + q + '"'};
    el = hits[0] || null;
  }
  if (!el) return {error: 'not found: ' + kind + '=' + q};
  if (el.disabled) return {error: 'element is disabled: ' + kind + '=' + q};
  el.scrollIntoView({block: 'center', inline: 'center', behavior: 'instant'});
  var r = el.getBoundingClientRect();
  if (r.width === 0 || r.height === 0) return {error: 'element is not visible: ' + kind + '=' + q};
  var x = r.left + r.width / 2, y = r.top + r.height / 2;
  var hit = document.elementFromPoint(x, y);
  if (!hit || !(hit === el || el.contains(hit))) {
    return {error: 'element is covered by ' + (hit ? '<' + hit.tagName.toLowerCase() + '>' : 'nothing (off-screen)') + ': ' + kind + '=' + q};
  }
  return {x: x, y: y, tag: el.tagName.toLowerCase()};
})
"""

STATE_JS = r"""
(function (limit) {
  var a = document.activeElement, f = null;
  if (a && a !== document.body) {
    f = {tag: a.tagName.toLowerCase(), id: a.id || '', name: a.getAttribute('name') || '',
         value: (typeof a.value === 'string') ? a.value : ''};
  }
  var text = document.body ? document.body.innerText : '';
  return {location: location.href, title: document.title, busy: document.readyState !== 'complete',
          visible_text: text.slice(0, limit), text_truncated: text.length > limit, focus: f,
          viewport: [window.innerWidth, window.innerHeight], scroll: [Math.round(window.scrollX), Math.round(window.scrollY)]};
})
"""


def locate(cdp, value):
    """Returns (x, y, button, description). VALUE = css=<selector> | text=<visible text> | X,Y[,left|right|double]."""
    v = value.strip()
    for kind in ("css", "text"):
        if v.lower().startswith(kind + "="):
            q = v[len(kind) + 1:]
            r = cdp.evaluate("%s(%s,%s)" % (LOCATE_JS, json.dumps(kind), json.dumps(q)))
            if not r or r.get("error"):
                raise BackendError("input gate: " + ((r or {}).get("error") or "element lookup failed"))
            time.sleep(0.05)
            return r["x"], r["y"], "left", "%s=%s" % (kind, q)
    parts = [p.strip() for p in v.split(",")]
    if len(parts) < 2:
        raise BackendError("click requires VALUE=css=<selector> | text=<visible text> | X,Y[,left|right|double]")
    try:
        x, y = float(parts[0]), float(parts[1])
    except ValueError:
        raise BackendError("click coordinates must be numbers: %s" % value)
    button = parts[2].lower() if len(parts) > 2 else "left"
    if button not in ("left", "right", "double"):
        raise BackendError("click button must be left, right or double (got '%s')" % button)
    vw, vh = cdp.evaluate("[window.innerWidth, window.innerHeight]")
    if not (0 <= x < vw and 0 <= y < vh):
        raise BackendError("point (%s,%s) is outside the viewport %sx%s" % (parts[0], parts[1], vw, vh))
    return x, y, button, "%s,%s" % (parts[0], parts[1])


def mouse_click(cdp, x, y, button):
    btn = "right" if button == "right" else "left"
    cdp.call("Input.dispatchMouseEvent", {"type": "mouseMoved", "x": x, "y": y})
    for n in range(1, (2 if button == "double" else 1) + 1):
        cdp.call("Input.dispatchMouseEvent", {"type": "mousePressed", "x": x, "y": y, "button": btn, "clickCount": n})
        time.sleep(0.04)
        cdp.call("Input.dispatchMouseEvent", {"type": "mouseReleased", "x": x, "y": y, "button": btn, "clickCount": n})
        time.sleep(0.05)


# ---------------------------------------------------------------- actions
def act_launch(cfg, value):
    st = read_state()
    if browser_alive(st):
        raise BackendError("single-instance rule: a browser from a previous launch is still running (run close first)")
    exe = find_browser(cfg)
    url = target_url(cfg)
    web = cfg.get("web") or {}
    vw, vh = (web.get("viewport") or [1280, 800])[:2]
    with socket.socket() as s:
        s.bind(("127.0.0.1", 0))
        port = s.getsockname()[1]
    profile = tempfile.mkdtemp(prefix=PROFILE_PREFIX)
    # Throwaway profile, isolated from the user's own browser data: no account sign-in, no sync.
    cmd = [exe, "--remote-debugging-port=%d" % port, "--user-data-dir=%s" % profile, "--no-first-run",
           "--no-default-browser-check", "--disable-extensions", "--disable-sync", "--disable-default-apps",
           "--disable-features=msImplicitSignin,msEdgeSyncConsent,Translate", "--password-store=basic",
           "--window-size=%d,%d" % (vw, vh)]
    if web.get("headless"):
        cmd += ["--headless=new", "--hide-scrollbars"]
    cmd += [str(a) for a in (cfg.get("args") or [])] + [url]
    flags = 0x00000008 | 0x00000200 if os.name == "nt" else 0  # DETACHED_PROCESS | CREATE_NEW_PROCESS_GROUP
    proc = subprocess.Popen(cmd, stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                            creationflags=flags, close_fds=True)
    st = {"pid": proc.pid, "port": port, "profile": profile, "browser": exe, "started": time.strftime("%Y-%m-%dT%H:%M:%S")}
    with open(STATE_FILE, "w", encoding="utf-8") as f:
        json.dump(st, f)
    deadline = time.time() + int(cfg.get("startup_ms") or 15000) / 1000.0
    last = "browser did not open the debugging port"
    while time.time() < deadline:
        try:
            pages = page_targets(port)
            if pages:
                cdp = CDP(pages[0]["webSocketDebuggerUrl"])
                try:
                    info = cdp.evaluate("({ready: document.readyState, url: location.href, title: document.title})")
                finally:
                    cdp.close()
                if info["ready"] == "complete" and info["url"] not in ("about:blank", ""):
                    st["target"] = pages[0]["id"]
                    with open(STATE_FILE, "w", encoding="utf-8") as f:
                        json.dump(st, f)
                    return {"pid": proc.pid, "port": port, "url": info["url"], "title": info["title"], "browser": exe,
                            "headless": bool(web.get("headless"))}
                last = "page still loading (readyState=%s url=%s)" % (info["ready"], info["url"])
        except BackendError as e:
            last = str(e)
        except Exception as e:  # port not open yet
            last = "%s: %s" % (type(e).__name__, e)
        time.sleep(0.25)
    raise BackendError("launched pid=%d but the page was not ready within startup_ms: %s (run close to clean up)" % (proc.pid, last))


def act_close(cfg, value):
    st = read_state()
    if not st:
        raise BackendError("nothing to close: no launch record (%s)" % STATE_FILE)
    if browser_alive(st):
        try:
            ws_url = http_json(st["port"], "/json/version")["webSocketDebuggerUrl"]
            b = CDP(ws_url, 5)
            try:
                b.call("Browser.close")
            except BackendError:
                pass
            b.close()
        except Exception:
            pass
        for _ in range(20):
            if not browser_alive(st):
                break
            time.sleep(0.25)
    if browser_alive(st):  # only the process we started, never a browser the user opened
        if os.name == "nt":
            subprocess.call(["taskkill", "/PID", str(st["pid"]), "/T", "/F"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        else:
            try:
                os.kill(st["pid"], 15)
            except OSError:
                pass
    profile = st.get("profile") or ""
    if os.path.basename(profile).startswith(PROFILE_PREFIX) and os.path.isdir(profile):
        for _ in range(8):
            shutil.rmtree(profile, ignore_errors=True)
            if not os.path.exists(profile):
                break
            time.sleep(0.4)
    os.remove(STATE_FILE)
    return {"pid": st["pid"]}


def act_focus(cfg, value):
    cdp, _ = connect(cfg)
    try:
        cdp.call("Page.bringToFront")
        return cdp.evaluate("({url: location.href, title: document.title})")
    finally:
        cdp.close()


def act_info(cfg, value):
    cdp, pages = connect(cfg)
    try:
        r = cdp.evaluate("({url: location.href, title: document.title, client: [window.innerWidth, window.innerHeight],"
                         " foreground: document.visibilityState === 'visible', dpr: window.devicePixelRatio})")
    finally:
        cdp.close()
    r["pages"] = pages
    r["pid"] = read_state()["pid"]
    r["input_method"] = "cdp-input"
    return r


def act_keys(cfg, value):
    names = [p.strip() for p in value.split(",") if p.strip()]
    if not names:
        raise BackendError("keys requires VALUE=KEY[,KEY...]")
    specs = [key_spec(n) for n in names]  # validate everything before sending anything
    k = cfg.get("keys") or {}
    hold, gap = int(k.get("default_hold_ms") or 60), int(k.get("gap_ms") or 150)
    cdp, _ = connect(cfg)
    try:
        for s in specs:
            key_event(cdp, "keyDown", s)
            time.sleep(max(0.02, hold / 1000.0))
            key_event(cdp, "keyUp", s)
            time.sleep(gap / 1000.0)
    finally:
        cdp.close()
    log_input(cfg, "keys", ",".join(names))
    return {"keys": names, "hold_ms": hold, "gap_ms": gap}


def act_hold(cfg, value):
    parts = [p.strip() for p in value.split(",")]
    if len(parts) < 2 or not parts[1].isdigit():
        raise BackendError("hold requires VALUE=KEY,MS")
    spec, ms = key_spec(parts[0]), int(parts[1])
    cdp, _ = connect(cfg)
    try:
        hold_keys(cdp, [spec], ms)
    finally:
        cdp.close()
    log_input(cfg, "hold", value)
    return {"key": parts[0], "ms": ms}


def act_diag(cfg, value):
    parts = [p.strip() for p in value.split(",")]
    if len(parts) < 3 or not parts[2].isdigit():
        raise BackendError("diag requires VALUE=KEY1,KEY2,MS")
    specs, ms = [key_spec(parts[0]), key_spec(parts[1])], int(parts[2])
    cdp, _ = connect(cfg)
    try:
        hold_keys(cdp, specs, ms)
    finally:
        cdp.close()
    log_input(cfg, "diag", value)
    return {"keys": parts[:2], "ms": ms}


def act_click(cfg, value):
    cdp, _ = connect(cfg)
    try:
        x, y, button, desc = locate(cdp, value)
        mouse_click(cdp, x, y, button)
    finally:
        cdp.close()
    log_input(cfg, "click", value)
    return {"target": desc, "x": round(x, 1), "y": round(y, 1), "button": button}


def act_type(cfg, value):
    if value == "":
        raise BackendError("type requires VALUE=TEXT (click the field first; text goes to the focused element)")
    cdp, _ = connect(cfg)
    try:
        for ch in value:
            if ch.isascii() and ch.isprintable():
                spec = key_spec(ch) if ch != " " else NAMED["SPACE"]
                key_event(cdp, "keyDown", spec)
                key_event(cdp, "keyUp", spec)
            else:
                cdp.call("Input.insertText", {"text": ch})
            time.sleep(0.02)
    finally:
        cdp.close()
    log_input(cfg, "type", value)
    return {"chars": len(value)}


def act_scroll(cfg, value):
    parts = [p.strip() for p in value.split(",")]
    try:
        x, y, notches = float(parts[0]), float(parts[1]), int(parts[2])
    except (IndexError, ValueError):
        raise BackendError("scroll requires VALUE=X,Y,NOTCHES (viewport pixels; positive = up, negative = down)")
    cdp, _ = connect(cfg)
    try:
        cdp.call("Input.dispatchMouseEvent", {"type": "mouseWheel", "x": x, "y": y, "deltaX": 0, "deltaY": -notches * 100})
        time.sleep(0.15)
    finally:
        cdp.close()
    log_input(cfg, "scroll", value)
    return {"x": x, "y": y, "notches": notches}


def _capture(cdp, cfg, name, clip=None):
    params = {"format": "png"}
    if clip:
        params["clip"] = {"x": clip[0], "y": clip[1], "width": clip[2], "height": clip[3], "scale": 1}
    data = base64.b64decode(cdp.call("Page.captureScreenshot", params)["data"])
    path = free_path(evidence_dir(cfg), name, ".png")
    with open(path, "wb") as f:
        f.write(data)
    return path, len(data)


def act_shot(cfg, value):
    name = value.strip() or ("shot_" + time.strftime("%Y%m%d_%H%M%S"))
    cdp, _ = connect(cfg)
    try:
        path, size = _capture(cdp, cfg, name)
    finally:
        cdp.close()
    return {"path": path, "bytes": size, "method": "cdp-screenshot"}


def act_hint(cfg, value):
    region = (cfg.get("capture") or {}).get("crop_hint") or cfg.get("hint_region")
    if not region or len(region) != 4:
        raise BackendError("hint requires config capture.crop_hint = [x, y, w, h] (viewport pixels)")
    name = value.strip() or ("hint_" + time.strftime("%Y%m%d_%H%M%S"))
    cdp, _ = connect(cfg)
    try:
        full, _n = _capture(cdp, cfg, name)
        crop, _n = _capture(cdp, cfg, os.path.splitext(os.path.basename(full))[0] + "_hint", region)
    finally:
        cdp.close()
    return {"path": full, "crop": crop, "region": list(region)}


def act_read_text(cfg, value):
    v = value.strip()
    cdp, _ = connect(cfg)
    try:
        if v.lower().startswith("css="):
            q = v[4:]
            text = cdp.evaluate("(function(q){var e=document.querySelector(q);return e?(e.innerText||e.value||''):null})(%s)" % json.dumps(q))
            if text is None:
                raise BackendError("not found: css=%s" % q)
        elif v:
            raise BackendError("read_text VALUE must be empty (whole page) or css=<selector>")
        else:
            text = cdp.evaluate("document.body ? document.body.innerText : ''")
    finally:
        cdp.close()
    return {"text": text}


def act_state(cfg, value):
    limit = int((cfg.get("web") or {}).get("state_text_limit") or 4000)
    cdp, _ = connect(cfg)
    try:
        st = cdp.evaluate("%s(%d)" % (STATE_JS, limit))
    finally:
        cdp.close()
    return {"state": st}


ACTIONS = {
    "launch": act_launch, "close": act_close, "focus": act_focus, "info": act_info,
    "keys": act_keys, "hold": act_hold, "diag": act_diag, "click": act_click, "type": act_type,
    "scroll": act_scroll, "shot": act_shot, "screenshot": act_shot, "hint": act_hint,
    "read_text": act_read_text, "state": act_state,
}


def main(argv=None):
    ap = argparse.ArgumentParser(description="game-playtest web backend (CDP)")
    ap.add_argument("-Action", "--action", dest="action", required=True)
    ap.add_argument("-Value", "--value", dest="value", default="")
    ap.add_argument("-Config", "--config", dest="config", default="playtest.json")
    a = ap.parse_args(argv)
    action = a.action.lower()
    if action in UNSUPPORTED_ACTIONS:
        print(json.dumps({"ok": False, "action": action, "unsupported": True,
                          "error": "%s is not implemented by the web backend" % action}))
        sys.stderr.write("%s is not implemented by the web backend\n" % action)
        return 3
    try:
        if action not in ACTIONS:
            raise BackendError("unknown action: %s (supported: %s; unsupported: %s)"
                               % (a.action, "/".join(sorted(set(ACTIONS) - {"screenshot"})), "/".join(UNSUPPORTED_ACTIONS)))
        cfg = load_config(a.config)
        out = {"ok": True, "action": "shot" if action == "screenshot" else action}
        out.update(ACTIONS[action](cfg, a.value) or {})
        print(json.dumps(out))
        return 0
    except BackendError as e:
        print(json.dumps({"ok": False, "action": action, "error": str(e)}))
        sys.stderr.write(str(e) + "\n")
        return 1
    except Exception as e:  # unexpected: still honour the output contract
        msg = "%s: %s" % (type(e).__name__, e)
        print(json.dumps({"ok": False, "action": action, "error": msg}))
        sys.stderr.write(msg + "\n")
        return 1


if __name__ == "__main__":
    sys.exit(main())
