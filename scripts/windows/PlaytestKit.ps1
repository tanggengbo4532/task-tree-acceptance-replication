param(
    [Parameter(Mandatory = $true)][string]$Action,
    [string]$Value = "",
    [string]$Config = "playtest.json"
)

# game-playtest / PlaytestKit.ps1  v3 (Windows backend reference implementation)
# Engine-agnostic action contract: scripts/backends/CONTRACT.md
#   launch | close | focus | info | keys | hold | diag | shot | hint | read_text(UNSUPPORTED)
# Screenshot/crop is delegated to Capture.ps1 (DPI-aware, PrintWindow -> CopyFromScreen fallback,
# temporary topmost + restore, absolute output paths).
# ASCII-only file: Windows PowerShell 5.1 decodes .ps1 as ANSI/GBK.

$ErrorActionPreference = "Stop"
Add-Type -AssemblyName System.Drawing
$RootDir = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$CaptureScript = Join-Path $RootDir "windows\Capture.ps1"
if (-not (Test-Path -LiteralPath $CaptureScript)) { $CaptureScript = Join-Path $RootDir "Capture.ps1" }

if (-not ("GPTKitWin32" -as [type])) {
Add-Type @"
using System;
using System.Runtime.InteropServices;
public class GPTKitWin32 {
    [StructLayout(LayoutKind.Sequential)] public struct RECT { public int Left, Top, Right, Bottom; }
    [StructLayout(LayoutKind.Sequential)] public struct POINT { public int X, Y; }
    [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
    [DllImport("user32.dll")] public static extern bool GetClientRect(IntPtr h, out RECT r);
    [DllImport("user32.dll")] public static extern bool ClientToScreen(IntPtr h, ref POINT p);
    [DllImport("user32.dll")] public static extern bool IsIconic(IntPtr h);
    [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int cmd);
    [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
    [DllImport("user32.dll")] public static extern bool PostMessage(IntPtr h, uint m, IntPtr w, IntPtr l);
    [DllImport("user32.dll")] public static extern bool SetWindowPos(IntPtr h, IntPtr after, int x, int y, int cx, int cy, uint flags);
    [DllImport("user32.dll")] public static extern uint MapVirtualKey(uint code, uint mapType);
    [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
}
"@
}
try { [GPTKitWin32]::SetProcessDPIAware() | Out-Null } catch { }

function Read-Cfg([string]$path) {
    $p = $path
    if (-not [System.IO.Path]::IsPathRooted($p)) { $p = Join-Path (Get-Location) $p }
    if (-not (Test-Path -LiteralPath $p)) { throw "config not found: $p" }
    return Get-Content -LiteralPath $p -Raw -Encoding UTF8 | ConvertFrom-Json
}

function Find-Win($cfg) {
    $pattern = if ($cfg.title_pattern) { [string]$cfg.title_pattern } else { "*" }
    $exe = if ($cfg.process_name) { [string]$cfg.process_name } else { "" }
    $procs = Get-Process | Where-Object {
        $_.MainWindowHandle -ne 0 -and ($_.MainWindowTitle -like $pattern) -and ($exe -eq "" -or $_.ProcessName -like $exe)
    }
    $p = $procs | Select-Object -First 1
    if ($null -eq $p) { throw "target window not found (title_pattern=$pattern process_name=$exe)" }
    return $p
}

function Focus-Win($p) {
    $hw = $p.MainWindowHandle
    if ([GPTKitWin32]::IsIconic($hw)) { [GPTKitWin32]::ShowWindow($hw, 9) | Out-Null; Start-Sleep -Milliseconds 300 }
    [GPTKitWin32]::ShowWindow($hw, 9) | Out-Null
    [GPTKitWin32]::SetForegroundWindow($hw) | Out-Null
    Start-Sleep -Milliseconds 200
}

function Get-KeyEnv($name) {
    $n = $name.Trim().Trim("{").Trim("}").ToUpperInvariant()
    $map = @{
        "ENTER" = 0x0D; "RETURN" = 0x0D; "SPACE" = 0x20; "ESC" = 0x1B; "ESCAPE" = 0x1B
        "UP" = 0x26; "DOWN" = 0x28; "LEFT" = 0x25; "RIGHT" = 0x27; "TAB" = 0x09; "BACKSPACE" = 0x08
        "DELETE" = 0x2E; "HOME" = 0x24; "END" = 0x23; "PGUP" = 0x21; "PGDN" = 0x22
        "F1" = 0x70; "F2" = 0x71; "F3" = 0x72; "F4" = 0x73; "F5" = 0x74; "F6" = 0x75; "F7" = 0x76
        "F8" = 0x77; "F9" = 0x78; "F10" = 0x79; "F11" = 0x7A; "F12" = 0x7B
    }
    if ($map.ContainsKey($n)) { return [int]$map[$n] }
    if ($name.Length -eq 1) { return [int][char]$name }
    throw "unknown key: $name (use KEY names like UP/DOWN/SPACE/ENTER/ESC/F1 or a single char)"
}

function Send-Down([IntPtr]$hw, [int]$vk) {
    $scan = [int][GPTKitWin32]::MapVirtualKey([uint32]$vk, 0)
    [GPTKitWin32]::PostMessage($hw, 0x0100, [IntPtr]$vk, [IntPtr](1 -bor ($scan -shl 16))) | Out-Null
}
function Send-Up([IntPtr]$hw, [int]$vk) {
    $scan = [int][GPTKitWin32]::MapVirtualKey([uint32]$vk, 0)
    [GPTKitWin32]::PostMessage($hw, 0x0101, [IntPtr]$vk, [IntPtr](0xC0000001 -bor ($scan -shl 16))) | Out-Null
}

function Send-Tap([IntPtr]$hw, [int]$vk, [int]$holdMs) {
    Send-Down $hw $vk
    Start-Sleep -Milliseconds ([math]::Max(20, $holdMs))
    Send-Up $hw $vk
}

function Get-HoldMs($cfg) {
    if ($cfg.keys -and $cfg.keys.default_hold_ms) { return [int]$cfg.keys.default_hold_ms }
    return 60
}
function Get-GapMs($cfg) {
    if ($cfg.keys -and $cfg.keys.gap_ms) { return [int]$cfg.keys.gap_ms }
    return 550
}

$cfg = Read-Cfg $Config
$pidFile = Join-Path (Get-Location) ".playtest_pid"

switch ($Action.ToLowerInvariant()) {
    "launch" {
        $exe = [string]$cfg.launch
        if ([string]::IsNullOrWhiteSpace($exe)) { throw "config.launch is required" }
        if (Test-Path -LiteralPath $pidFile) {
            $old = (Get-Content -LiteralPath $pidFile -Raw).Trim()
            if ($old -match '^\d+$') {
                $alive = Get-Process -Id ([int]$old) -ErrorAction SilentlyContinue
                if ($alive) { throw "single-instance rule: previous pid=$old is still running (run close first)" }
            }
            Remove-Item -LiteralPath $pidFile -Force -ErrorAction SilentlyContinue
        }
        $argv = @()
        if ($cfg.args) { $argv = @($cfg.args | ForEach-Object { [string]$_ }) }
        $p = Start-Process -FilePath $exe -ArgumentList $argv -PassThru
        Set-Content -LiteralPath $pidFile -Value $p.Id -Encoding ASCII
        $waitMs = if ($cfg.startup_ms) { [int]$cfg.startup_ms } else { 8000 }
        Start-Sleep -Milliseconds $waitMs
        try {
            $win = Find-Win $cfg
            Write-Output ("launched pid={0} hwnd={1} title='{2}'" -f $win.Id, $win.MainWindowHandle, $win.MainWindowTitle)
        } catch {
            Write-Output ("launched pid={0} (window not found yet; startup_ms={1})" -f $p.Id, $waitMs)
        }
    }

    "close" {
        $closed = $false
        if (Test-Path -LiteralPath $pidFile) {
            $text = (Get-Content -LiteralPath $pidFile -Raw).Trim()
            if ($text -match '^\d+$') {
                Stop-Process -Id ([int]$text) -Force -ErrorAction SilentlyContinue
                Write-Output ("closed pid=" + $text)
                Remove-Item -LiteralPath $pidFile -Force -ErrorAction SilentlyContinue
                $closed = $true
            }
        }
        if (-not $closed) {
            $p = Find-Win $cfg
            Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue
            Write-Output ("closed pid=" + $p.Id)
        }
    }

    "focus" {
        $p = Find-Win $cfg
        Focus-Win $p
        Write-Output ("focused pid={0} hwnd={1} title='{2}'" -f $p.Id, $p.MainWindowHandle, $p.MainWindowTitle)
    }

    "info" {
        $p = Find-Win $cfg
        $hw = $p.MainWindowHandle
        $wr = New-Object GPTKitWin32+RECT; [GPTKitWin32]::GetWindowRect($hw, [ref]$wr) | Out-Null
        $cr = New-Object GPTKitWin32+RECT; [GPTKitWin32]::GetClientRect($hw, [ref]$cr) | Out-Null
        $pt = New-Object GPTKitWin32+POINT; $pt.X = 0; $pt.Y = 0
        [GPTKitWin32]::ClientToScreen($hw, [ref]$pt) | Out-Null
        Write-Output ("pid={0} hwnd={1} title='{2}' iconic={3} rect=({4},{5})-({6},{7}) client={8}x{9} clientOrigin=({10},{11})" -f `
            $p.Id, $hw, $p.MainWindowTitle, [bool][GPTKitWin32]::IsIconic($hw),
            $wr.Left, $wr.Top, $wr.Right, $wr.Bottom, ($cr.Right - $cr.Left), ($cr.Bottom - $cr.Top), $pt.X, $pt.Y)
    }

    "keys" {
        $p = Find-Win $cfg
        if ($cfg.focus_before_key -ne $false) { Focus-Win $p }
        $hw = $p.MainWindowHandle
        $hold = Get-HoldMs $cfg; $gap = Get-GapMs $cfg
        $sent = @()
        foreach ($part in $Value.Split(",")) {
            if ([string]::IsNullOrWhiteSpace($part)) { continue }
            $vk = Get-KeyEnv $part
            Send-Tap $hw $vk $hold
            $sent += $part.Trim()
            Start-Sleep -Milliseconds $gap
        }
        Write-Output ("keys: " + ($sent -join ","))
    }

    "hold" {
        $parts = $Value.Split(",")
        if ($parts.Count -lt 2) { throw "hold requires VALUE=KEY,MS" }
        $p = Find-Win $cfg
        if ($cfg.focus_before_key -ne $false) { Focus-Win $p }
        $vk = Get-KeyEnv $parts[0]
        $ms = [int]$parts[1]
        Send-Down $p.MainWindowHandle $vk
        Start-Sleep -Milliseconds $ms
        Send-Up $p.MainWindowHandle $vk
        Write-Output ("hold {0} {1}ms" -f $parts[0].Trim(), $ms)
    }

    "diag" {
        $parts = $Value.Split(",")
        if ($parts.Count -lt 3) { throw "diag requires VALUE=KEY1,KEY2,MS" }
        $p = Find-Win $cfg
        if ($cfg.focus_before_key -ne $false) { Focus-Win $p }
        $hw = $p.MainWindowHandle
        $vk1 = Get-KeyEnv $parts[0]; $vk2 = Get-KeyEnv $parts[1]; $ms = [int]$parts[2]
        Send-Down $hw $vk1; Send-Down $hw $vk2
        Start-Sleep -Milliseconds $ms
        Send-Up $hw $vk2; Send-Up $hw $vk1
        Write-Output ("diag {0}+{1} {2}ms" -f $parts[0].Trim(), $parts[1].Trim(), $ms)
    }

    "shot" {
        if (-not (Test-Path -LiteralPath $CaptureScript)) { throw "Capture.ps1 not found: $CaptureScript" }
        & $CaptureScript -Action shot -Value $Value -Config $Config
        if ($LASTEXITCODE -ne 0 -and $LASTEXITCODE -ne $null) { exit $LASTEXITCODE }
    }

    "hint" {
        if (-not (Test-Path -LiteralPath $CaptureScript)) { throw "Capture.ps1 not found: $CaptureScript" }
        & $CaptureScript -Action hint -Value $Value -Config $Config
        if ($LASTEXITCODE -ne 0 -and $LASTEXITCODE -ne $null) { exit $LASTEXITCODE }
    }

    "read_text" {
        Write-Output "UNSUPPORTED read_text: this backend captures pixels only; wire an engine hook (see scripts/backends/CONTRACT.md 4.x)"
        Write-Error "read_text is not implemented by the windows backend"
        exit 3
    }

    default {
        throw "unknown action: $Action (supported: launch/close/focus/info/keys/hold/diag/shot/hint/read_text)"
    }
}
