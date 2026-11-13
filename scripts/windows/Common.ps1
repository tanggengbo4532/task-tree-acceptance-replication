# game-playtest / Common.ps1 - shared helpers for the Windows reference backend.
# Dot-sourced by PlaytestKit.ps1 and Capture.ps1 (do not run directly).
# ASCII-only file: Windows PowerShell 5.1 decodes .ps1 as ANSI/GBK.

Add-Type -AssemblyName System.Drawing

if (-not ("GPTWin32" -as [type])) {
Add-Type @"
using System;
using System.Text;
using System.Runtime.InteropServices;
public class GPTWin32 {
    [StructLayout(LayoutKind.Sequential)] public struct RECT { public int Left, Top, Right, Bottom; }
    [StructLayout(LayoutKind.Sequential)] public struct POINT { public int X, Y; }
    [StructLayout(LayoutKind.Sequential)] public struct MOUSEINPUT { public int dx, dy; public uint mouseData, dwFlags, time; public IntPtr dwExtraInfo; }
    [StructLayout(LayoutKind.Sequential)] public struct KEYBDINPUT { public ushort wVk, wScan; public uint dwFlags, time; public IntPtr dwExtraInfo; }
    [StructLayout(LayoutKind.Explicit)] public struct INPUTUNION { [FieldOffset(0)] public MOUSEINPUT mi; [FieldOffset(0)] public KEYBDINPUT ki; }
    [StructLayout(LayoutKind.Sequential)] public struct INPUT { public uint type; public INPUTUNION u; }
    [StructLayout(LayoutKind.Sequential)] public struct GUITHREADINFO {
        public int cbSize; public int flags;
        public IntPtr hwndActive, hwndFocus, hwndCapture, hwndMenuOwner, hwndMoveSize, hwndCaret;
        public RECT rcCaret;
    }

    [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
    [DllImport("user32.dll")] public static extern bool GetClientRect(IntPtr h, out RECT r);
    [DllImport("user32.dll")] public static extern bool ClientToScreen(IntPtr h, ref POINT p);
    [DllImport("user32.dll")] public static extern bool ScreenToClient(IntPtr h, ref POINT p);
    [DllImport("user32.dll")] public static extern bool IsIconic(IntPtr h);
    [DllImport("user32.dll")] public static extern bool IsZoomed(IntPtr h);
    [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int cmd);
    [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
    [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetWindowTextW(IntPtr h, StringBuilder s, int n);
    [DllImport("user32.dll")] public static extern bool PostMessage(IntPtr h, uint m, IntPtr w, IntPtr l);
    [DllImport("user32.dll")] public static extern bool SetWindowPos(IntPtr h, IntPtr after, int x, int y, int cx, int cy, uint flags);
    [DllImport("user32.dll")] public static extern uint MapVirtualKey(uint code, uint mapType);
    [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern short VkKeyScanW(char ch);
    [DllImport("user32.dll")] public static extern bool PrintWindow(IntPtr h, IntPtr hdc, uint flags);
    [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
    [DllImport("user32.dll")] public static extern IntPtr WindowFromPoint(POINT p);
    [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
    [DllImport("user32.dll")] public static extern bool GetGUIThreadInfo(uint tid, ref GUITHREADINFO g);
    [DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
    [DllImport("user32.dll", SetLastError=true)] public static extern uint SendInput(uint n, INPUT[] inputs, int size);
    [DllImport("user32.dll")] public static extern bool AttachThreadInput(uint a, uint b, bool attach);
    [DllImport("user32.dll")] public static extern bool BringWindowToTop(IntPtr h);
    [DllImport("kernel32.dll")] public static extern uint GetCurrentThreadId();

    // Windows refuses foreground changes from background processes; sharing the input queue
    // with the current foreground thread lifts that lock without injecting any key.
    public static bool ForceForeground(IntPtr h) {
        uint pid; uint fgThread = GetWindowThreadProcessId(GetForegroundWindow(), out pid);
        uint cur = GetCurrentThreadId();
        bool attached = fgThread != 0 && fgThread != cur && AttachThreadInput(cur, fgThread, true);
        BringWindowToTop(h);
        bool ok = SetForegroundWindow(h);
        if (attached) AttachThreadInput(cur, fgThread, false);
        return ok;
    }

    public static bool IsExtended(uint vk) {
        return (vk >= 0x21 && vk <= 0x28) || vk == 0x2D || vk == 0x2E;
    }
    public static uint PidOf(IntPtr h) { uint pid; GetWindowThreadProcessId(h, out pid); return pid; }
    // Focused child of the window's GUI thread (falls back to the window itself).
    public static IntPtr FocusOf(IntPtr top) {
        uint pid; uint tid = GetWindowThreadProcessId(top, out pid);
        GUITHREADINFO g = new GUITHREADINFO();
        g.cbSize = Marshal.SizeOf(typeof(GUITHREADINFO));
        if (GetGUIThreadInfo(tid, ref g) && g.hwndFocus != IntPtr.Zero) return g.hwndFocus;
        return top;
    }
    public static bool Key(ushort vk, bool up) {
        INPUT[] a = new INPUT[1];
        a[0].type = 1; a[0].u.ki.wVk = vk; a[0].u.ki.wScan = (ushort)MapVirtualKey(vk, 0);
        uint f = up ? 2u : 0u; if (IsExtended(vk)) f |= 1u;
        a[0].u.ki.dwFlags = f;
        return SendInput(1, a, Marshal.SizeOf(typeof(INPUT))) == 1;
    }
    public static bool UnicodeChar(char c, bool up) {
        INPUT[] a = new INPUT[1];
        a[0].type = 1; a[0].u.ki.wVk = 0; a[0].u.ki.wScan = (ushort)c;
        a[0].u.ki.dwFlags = 4u | (up ? 2u : 0u);
        return SendInput(1, a, Marshal.SizeOf(typeof(INPUT))) == 1;
    }
    public static bool Mouse(uint flags, int data) {
        INPUT[] a = new INPUT[1];
        a[0].type = 0; a[0].u.mi.dwFlags = flags; a[0].u.mi.mouseData = unchecked((uint)data);
        return SendInput(1, a, Marshal.SizeOf(typeof(INPUT))) == 1;
    }
}
"@
}
try { [GPTWin32]::SetProcessDPIAware() | Out-Null } catch { }

function Read-Cfg([string]$path) {
    $p = $path
    if (-not [System.IO.Path]::IsPathRooted($p)) { $p = Join-Path (Get-Location) $p }
    if (-not (Test-Path -LiteralPath $p)) { throw "config not found: $p" }
    return Get-Content -LiteralPath $p -Raw -Encoding UTF8 | ConvertFrom-Json
}

# ---- pid file: line1 = launched pid, line2 = start time ticks, line3 = window-owner pid (optional)
function Get-PidFile { return (Join-Path (Get-Location) ".playtest_pid") }

function Read-PidInfo {
    $f = Get-PidFile
    if (-not (Test-Path -LiteralPath $f)) { return $null }
    $lines = @(Get-Content -LiteralPath $f | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne "" })
    if ($lines.Count -eq 0 -or $lines[0] -notmatch '^\d+$') { return $null }
    $info = [pscustomobject]@{ pid = [int]$lines[0]; start = ""; winpid = 0 }
    if ($lines.Count -ge 2 -and $lines[1] -match '^\d+$') { $info.start = $lines[1] }
    if ($lines.Count -ge 3 -and $lines[2] -match '^\d+$') { $info.winpid = [int]$lines[2] }
    return $info
}

function Write-PidInfo([int]$procId, [string]$start, [int]$winPid) {
    Set-Content -LiteralPath (Get-PidFile) -Value @([string]$procId, $start, [string]$winPid) -Encoding ASCII
}

# Returns the launched process only if it is the SAME process we started (guards against pid reuse).
function Get-LaunchedProcess($info) {
    if ($null -eq $info) { return $null }
    $p = Get-Process -Id $info.pid -ErrorAction SilentlyContinue
    if ($null -eq $p) { return $null }
    if ($info.start -ne "") {
        $ticks = ""
        try { $ticks = [string]$p.StartTime.Ticks } catch { }
        if ($ticks -ne $info.start) { return $null }
    }
    return $p
}

function Test-WinMatch($p, [string]$pattern, [string]$exe) {
    if ($p.MainWindowHandle -eq 0) { return $false }
    if ($pattern -ne "" -and -not ($p.MainWindowTitle -like $pattern)) { return $false }
    if ($exe -ne "" -and -not ($p.ProcessName -like $exe)) { return $false }
    return $true
}

# Window lookup order: process recorded by `launch` -> unique title/process match.
# Never matches arbitrary windows: without a recorded pid, a locator is mandatory.
function Find-Win($cfg) {
    $pattern = if ($cfg.title_pattern) { [string]$cfg.title_pattern } else { "" }
    $exe = if ($cfg.process_name) { [string]$cfg.process_name } else { "" }
    $info = Read-PidInfo
    $launched = Get-LaunchedProcess $info
    if ($launched) {
        $launched.Refresh()
        if (Test-WinMatch $launched $pattern $exe) { return $launched }
        if ($info.winpid -gt 0) {
            $w = Get-Process -Id $info.winpid -ErrorAction SilentlyContinue
            if ($w -and (Test-WinMatch $w $pattern $exe)) { return $w }
        }
    }
    if ($pattern -eq "" -and $exe -eq "") {
        throw "no window locator: set title_pattern or process_name in the config (refusing to match arbitrary windows)"
    }
    $procs = @(Get-Process | Where-Object { Test-WinMatch $_ $pattern $exe })
    if ($procs.Count -eq 0) { throw "target window not found (title_pattern=$pattern process_name=$exe)" }
    if ($procs.Count -gt 1) {
        $list = ($procs | ForEach-Object { "pid={0} title='{1}'" -f $_.Id, $_.MainWindowTitle }) -join "; "
        throw "single-instance rule: $($procs.Count) windows match (title_pattern=$pattern process_name=$exe): $list. Close the extras or make the locator more specific."
    }
    return $procs[0]
}

function Focus-Win($p) {
    $hw = $p.MainWindowHandle
    if ([GPTWin32]::IsIconic($hw)) { [GPTWin32]::ShowWindow($hw, 9) | Out-Null; Start-Sleep -Milliseconds 300 }
    [GPTWin32]::SetForegroundWindow($hw) | Out-Null
    Start-Sleep -Milliseconds 200
    if ([GPTWin32]::PidOf([GPTWin32]::GetForegroundWindow()) -ne $p.Id) {
        [GPTWin32]::ForceForeground($hw) | Out-Null
        Start-Sleep -Milliseconds 250
    }
}

function Get-EvidenceDir($cfg) {
    $d = $null
    if ($cfg -and $cfg.evidence -and $cfg.evidence.dir) { $d = [string]$cfg.evidence.dir }
    elseif ($cfg -and $cfg.shot_dir) { $d = [string]$cfg.shot_dir }
    if ([string]::IsNullOrWhiteSpace($d)) { $d = "playtest_shots" }
    New-Item -ItemType Directory -Force -Path $d | Out-Null
    return (Resolve-Path -LiteralPath $d).Path
}

# Evidence is append-only: an existing name gets a numeric suffix instead of being overwritten.
function Get-FreePath([string]$dir, [string]$name, [string]$ext) {
    $p = Join-Path $dir ($name + $ext)
    $i = 2
    while (Test-Path -LiteralPath $p) { $p = Join-Path $dir ("{0}_{1}{2}" -f $name, $i, $ext); $i++ }
    return $p
}

# One machine-readable JSON line (pure ASCII, non-ASCII escaped) - CONTRACT section 1.
function ConvertTo-AsciiJson($obj) {
    $j = $obj | ConvertTo-Json -Compress -Depth 6
    return [regex]::Replace($j, '[^\x00-\x7F]', { param($m) '\u{0:x4}' -f [int][char]$m.Value })
}
function Write-Result($obj) { Write-Output (ConvertTo-AsciiJson $obj) }

# Append-only audit trail of every injected input (real-input evidence).
function Write-InputLog($cfg, [string]$action, [string]$value, [string]$method) {
    try {
        $dir = Get-EvidenceDir $cfg
        $rec = [ordered]@{ ts = (Get-Date -Format "yyyy-MM-ddTHH:mm:ss.fff"); backend = "windows"; action = $action; value = $value; method = $method }
        Add-Content -LiteralPath (Join-Path $dir "input-log.jsonl") -Value (ConvertTo-AsciiJson $rec) -Encoding ASCII
    } catch { }
}
