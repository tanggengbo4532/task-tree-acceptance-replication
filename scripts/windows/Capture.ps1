param(
    [Parameter(Mandatory = $true)][ValidateSet("shot", "hint", "region", "info")][string]$Action,
    [string]$Value = "",
    [string]$Config = "playtest.json",
    [string]$Region = "",
    [int]$TopmostMs = 400,
    [string]$Method = "auto"
)

# game-playtest / Capture.ps1  (ASCII-only: Windows PowerShell 5.1 reads .ps1 as ANSI)
# Anti-artifact client-area capture for black-box playtest evidence:
#   - DPI aware
#   - temporary topmost + foreground, restored afterwards (never leave window on top)
#   - PrintWindow(PW_RENDERFULLCONTENT) first, blank-frame detection -> CopyFromScreen fallback
#   - -Region "x,y,w,h" crop; 'hint' uses config capture.crop_hint / hint_region
#   - always prints ABSOLUTE output path(s)
# Usage:
#   Capture.ps1 -Action shot  -Config playtest.json -Value step01
#   Capture.ps1 -Action hint  -Config playtest.json -Value step01
#   Capture.ps1 -Action region -Value step01 -Region "60,145,1160,100"

$ErrorActionPreference = "Stop"
Add-Type -AssemblyName System.Drawing

if (-not ("GPTCapWin32" -as [type])) {
Add-Type @"
using System;
using System.Text;
using System.Runtime.InteropServices;
public class GPTCapWin32 {
    [StructLayout(LayoutKind.Sequential)] public struct RECT { public int Left, Top, Right, Bottom; }
    [StructLayout(LayoutKind.Sequential)] public struct POINT { public int X, Y; }
    [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
    [DllImport("user32.dll")] public static extern bool GetClientRect(IntPtr h, out RECT r);
    [DllImport("user32.dll")] public static extern bool ClientToScreen(IntPtr h, ref POINT p);
    [DllImport("user32.dll")] public static extern bool IsIconic(IntPtr h);
    [DllImport("user32.dll")] public static extern bool IsZoomed(IntPtr h);
    [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int cmd);
    [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
    [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetWindowTextW(IntPtr h, StringBuilder s, int n);
    [DllImport("user32.dll")] public static extern bool SetWindowPos(IntPtr h, IntPtr after, int x, int y, int cx, int cy, uint flags);
    [DllImport("user32.dll")] public static extern bool PrintWindow(IntPtr h, IntPtr hdc, uint flags);
    [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
}
"@
}
try { [GPTCapWin32]::SetProcessDPIAware() | Out-Null } catch { }

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
    if ($null -eq $p) { throw "target window not found (title_pattern=$pattern)" }
    return $p
}

function Prepare-Win([IntPtr]$hw, [int]$ms) {
    if ([GPTCapWin32]::IsIconic($hw)) { [GPTCapWin32]::ShowWindow($hw, 9) | Out-Null; Start-Sleep -Milliseconds 350 }
    [GPTCapWin32]::SetWindowPos($hw, [IntPtr](-1), 0, 0, 0, 0, 0x0001 -bor 0x0002 -bor 0x0040) | Out-Null
    [GPTCapWin32]::SetForegroundWindow($hw) | Out-Null
    Start-Sleep -Milliseconds ([math]::Max(120, $ms))
}

function Release-Win([IntPtr]$hw) {
    # restore non-topmost; keeps user's other windows usable
    try { [GPTCapWin32]::SetWindowPos($hw, [IntPtr](-2), 0, 0, 0, 0, 0x0001 -bor 0x0002) | Out-Null } catch { }
}

function Measure-Frame($bmp) {
    $w = $bmp.Width; $h = $bmp.Height
    $cols = 32; $rows = 18; $white = 0; $black = 0; $total = 0
    $set = @{}
    for ($r = 0; $r -lt $rows; $r++) {
        for ($c = 0; $c -lt $cols; $c++) {
            $x = [int]($w * ($c + 0.5) / $cols); $y = [int]($h * ($r + 0.5) / $rows)
            if ($x -lt 0) { $x = 0 }; if ($y -lt 0) { $y = 0 }
            if ($x -ge $w) { $x = $w - 1 }; if ($y -ge $h) { $y = $h - 1 }
            $px = $bmp.GetPixel($x, $y); $total++
            if ($px.R -ge 238 -and $px.G -ge 238 -and $px.B -ge 238) { $white++ }
            if ($px.R -le 18 -and $px.G -le 18 -and $px.B -le 18) { $black++ }
            $k = "{0},{1},{2}" -f ([int]($px.R / 16)), ([int]($px.G / 16)), ([int]($px.B / 16))
            if (-not $set.ContainsKey($k)) { $set[$k] = 1 }
        }
    }
    return [pscustomobject]@{
        white = [math]::Round($white / [double]$total, 3)
        black = [math]::Round($black / [double]$total, 3)
        colors = $set.Count
    }
}

function Capture-Frame([IntPtr]$hw, [string]$mode) {
    $cr = New-Object GPTCapWin32+RECT
    [GPTCapWin32]::GetClientRect($hw, [ref]$cr) | Out-Null
    $w = $cr.Right - $cr.Left; $hh = $cr.Bottom - $cr.Top
    if ($w -le 0 -or $hh -le 0) { throw "bad client size ${w}x${hh}" }
    $pt0 = New-Object GPTCapWin32+POINT; $pt0.X = 0; $pt0.Y = 0
    [GPTCapWin32]::ClientToScreen($hw, [ref]$pt0) | Out-Null
    $bmp = New-Object System.Drawing.Bitmap($w, $hh)
    $methodUsed = "printwindow"
    $ok = $false
    if ($mode -ne "screencopy") {
        $g = [System.Drawing.Graphics]::FromImage($bmp)
        $hdc = $g.GetHdc()
        $ok = [GPTCapWin32]::PrintWindow($hw, $hdc, 2)
        $g.ReleaseHdc($hdc); $g.Dispose()
    }
    $m = if ($mode -eq "screencopy") { [pscustomobject]@{ white = 1.0; black = 1.0; colors = 0 } } else { Measure-Frame $bmp }
    if ($mode -eq "screencopy" -or (-not $ok) -or ($m.colors -le 2) -or ($m.white -gt 0.9) -or ($m.black -gt 0.9)) {
        if ($methodUsed -eq "printwindow") { $bmp.Dispose() }
        $bmp = New-Object System.Drawing.Bitmap($w, $hh)
        $g2 = [System.Drawing.Graphics]::FromImage($bmp)
        $g2.CopyFromScreen($pt0.X, $pt0.Y, 0, 0, $bmp.Size)
        $g2.Dispose()
        $m = Measure-Frame $bmp
        $methodUsed = "screencopy"
    }
    return [pscustomobject]@{ bmp = $bmp; w = $w; h = $hh; method = $methodUsed; white = $m.white; black = $m.black; colors = $m.colors }
}

function Get-OutDir($cfg) {
    $d = $null
    if ($cfg -and $cfg.evidence -and $cfg.evidence.dir) { $d = [string]$cfg.evidence.dir }
    elseif ($cfg -and $cfg.shot_dir) { $d = [string]$cfg.shot_dir }
    if ([string]::IsNullOrWhiteSpace($d)) { $d = "playtest_shots" }
    New-Item -ItemType Directory -Force -Path $d | Out-Null
    return (Resolve-Path -LiteralPath $d).Path
}

function Save-Shot($frame, [string]$dir, [string]$name) {
    $p = Join-Path $dir ($name + ".png")
    $frame.bmp.Save($p, [System.Drawing.Imaging.ImageFormat]::Png)
    $frame.bmp.Dispose()
    return (Resolve-Path -LiteralPath $p).Path
}

$cfg = Read-Cfg $Config
if ($cfg.capture -and $cfg.capture.topmost_ms) { $TopmostMs = [int]$cfg.capture.topmost_ms }
if ($Method -eq "auto" -and $cfg.capture -and $cfg.capture.method) { $Method = [string]$cfg.capture.method }

switch ($Action) {
    "info" {
        $p = Find-Win $cfg
        $hw = $p.MainWindowHandle
        $cr = New-Object GPTCapWin32+RECT; [GPTCapWin32]::GetClientRect($hw, [ref]$cr) | Out-Null
        $sb = New-Object System.Text.StringBuilder 512
        [GPTCapWin32]::GetWindowTextW([GPTCapWin32]::GetForegroundWindow(), $sb, 512) | Out-Null
        Write-Output ("pid={0} hwnd={1} title='{2}' iconic={3} zoomed={4} client={5}x{6} fgIsGame={7} fgTitle='{8}' capture_method={9}" -f `
            $p.Id, $hw, $p.MainWindowTitle, [bool][GPTCapWin32]::IsIconic($hw), [bool][GPTCapWin32]::IsZoomed($hw),
            ($cr.Right - $cr.Left), ($cr.Bottom - $cr.Top), ([GPTCapWin32]::GetForegroundWindow() -eq $hw), $sb.ToString(), $Method)
    }
    "shot" {
        $p = Find-Win $cfg; $hw = $p.MainWindowHandle
        Prepare-Win $hw $TopmostMs
        try { $f = Capture-Frame $hw $Method } finally { Release-Win $hw }
        $dir = Get-OutDir $cfg
        $name = if ([string]::IsNullOrWhiteSpace($Value)) { "shot_" + (Get-Date -Format "yyyyMMdd_HHmmss_fff") } else { $Value }
        $path = Save-Shot $f $dir $name
        Write-Output ("SHOT {0} method={1} size={2}x{3} white={4} black={5} colors={6}" -f `
            $path, $f.method, $f.w, $f.h, $f.white, $f.black, $f.colors)
    }
    "hint" {
        $p = Find-Win $cfg; $hw = $p.MainWindowHandle
        Prepare-Win $hw $TopmostMs
        try { $f = Capture-Frame $hw $Method } finally { Release-Win $hw }
        $dir = Get-OutDir $cfg
        $name = if ([string]::IsNullOrWhiteSpace($Value)) { "hint_" + (Get-Date -Format "yyyyMMdd_HHmmss_fff") } else { $Value }
        $full = Save-Shot $f $dir $name
        $region = @(60, 145, 1160, 100)
        if ($cfg.capture -and $cfg.capture.crop_hint) { $region = @($cfg.capture.crop_hint) }
        elseif ($cfg.hint_region) { $region = @($cfg.hint_region) }
        $cx = [int]$region[0]; $cy = [int]$region[1]; $cw = [int]$region[2]; $ch = [int]$region[3]
        $bmp = [System.Drawing.Image]::FromFile($full)
        try {
            if ($cx -lt 0) { $cx = 0 }; if ($cy -lt 0) { $cy = 0 }
            if ($cx + $cw -gt $bmp.Width) { $cw = [math]::Max(1, $bmp.Width - $cx) }
            if ($cy + $ch -gt $bmp.Height) { $ch = [math]::Max(1, $bmp.Height - $cy) }
            $rect = New-Object System.Drawing.Rectangle($cx, $cy, $cw, $ch)
            $crop = $bmp.Clone($rect, [System.Drawing.Imaging.PixelFormat]::Format24bppRgb)
            $cropPath = Join-Path $dir ($name + "_hint.png")
            $crop.Save($cropPath, [System.Drawing.Imaging.ImageFormat]::Png); $crop.Dispose()
        } finally { $bmp.Dispose() }
        Write-Output ("HINT full={0} crop={1} region={2},{3},{4},{5}" -f $full, (Resolve-Path -LiteralPath $cropPath).Path, $cx, $cy, $cw, $ch)
    }
    "region" {
        if ($Region -match '^\s*(-?\d+)\s*,\s*(-?\d+)\s*,\s*(\d+)\s*,\s*(\d+)\s*$') {
            $cx = [int]$Matches[1]; $cy = [int]$Matches[2]; $cw = [int]$Matches[3]; $ch = [int]$Matches[4]
        } else { throw "region must be x,y,w,h" }
        if ([string]::IsNullOrWhiteSpace($Value)) { throw "region action requires -Value <source.png>" }
        $src = $Value
        if (-not [System.IO.Path]::IsPathRooted($src)) { $src = Join-Path (Get-Location) $src }
        if (-not (Test-Path -LiteralPath $src)) { throw "source not found: $src" }
        $bmp = [System.Drawing.Image]::FromFile($src)
        try {
            $rect = New-Object System.Drawing.Rectangle($cx, $cy, $cw, $ch)
            $crop = $bmp.Clone($rect, [System.Drawing.Imaging.PixelFormat]::Format24bppRgb)
            $dir = Get-OutDir $cfg
            $out = Join-Path $dir ("region_" + (Get-Date -Format "yyyyMMdd_HHmmss_fff") + ".png")
            $crop.Save($out, [System.Drawing.Imaging.ImageFormat]::Png); $crop.Dispose()
        } finally { $bmp.Dispose() }
        Write-Output ("REGION {0} crop={1} rect={2},{3},{4},{5}" -f $src, (Resolve-Path -LiteralPath $out).Path, $cx, $cy, $cw, $ch)
    }
    default { throw "unknown action: $Action" }
}
