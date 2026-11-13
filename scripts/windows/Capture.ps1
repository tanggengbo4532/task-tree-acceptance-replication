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
#   - always prints ABSOLUTE output path(s); last stdout line is one JSON object (CONTRACT section 1)
#   - append-only evidence: an existing name gets a _2/_3 suffix, never overwritten
# Usage:
#   Capture.ps1 -Action shot  -Config playtest.json -Value step01
#   Capture.ps1 -Action hint  -Config playtest.json -Value step01
#   Capture.ps1 -Action region -Value step01 -Region "60,145,1160,100"

$ErrorActionPreference = "Stop"
. (Join-Path (Split-Path -Parent $MyInvocation.MyCommand.Path) "Common.ps1")

function Prepare-Win([IntPtr]$hw, [int]$ms) {
    if ([GPTWin32]::IsIconic($hw)) { [GPTWin32]::ShowWindow($hw, 9) | Out-Null; Start-Sleep -Milliseconds 350 }
    [GPTWin32]::SetWindowPos($hw, [IntPtr](-1), 0, 0, 0, 0, 0x0001 -bor 0x0002 -bor 0x0040) | Out-Null
    [GPTWin32]::SetForegroundWindow($hw) | Out-Null
    Start-Sleep -Milliseconds ([math]::Max(120, $ms))
}

function Release-Win([IntPtr]$hw) {
    # restore non-topmost; keeps user's other windows usable
    try { [GPTWin32]::SetWindowPos($hw, [IntPtr](-2), 0, 0, 0, 0, 0x0001 -bor 0x0002) | Out-Null } catch { }
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
    $cr = New-Object GPTWin32+RECT
    [GPTWin32]::GetClientRect($hw, [ref]$cr) | Out-Null
    $w = $cr.Right - $cr.Left; $hh = $cr.Bottom - $cr.Top
    if ($w -le 0 -or $hh -le 0) { throw "bad client size ${w}x${hh}" }
    $pt0 = New-Object GPTWin32+POINT; $pt0.X = 0; $pt0.Y = 0
    [GPTWin32]::ClientToScreen($hw, [ref]$pt0) | Out-Null
    $bmp = New-Object System.Drawing.Bitmap($w, $hh)
    $methodUsed = "printwindow"
    $ok = $false
    if ($mode -ne "screencopy") {
        $g = [System.Drawing.Graphics]::FromImage($bmp)
        $hdc = $g.GetHdc()
        $ok = [GPTWin32]::PrintWindow($hw, $hdc, 2)
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

function Save-Shot($frame, [string]$dir, [string]$name) {
    $p = Get-FreePath $dir $name ".png"   # append-only: never overwrite existing evidence
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
        $cr = New-Object GPTWin32+RECT; [GPTWin32]::GetClientRect($hw, [ref]$cr) | Out-Null
        $sb = New-Object System.Text.StringBuilder 512
        [GPTWin32]::GetWindowTextW([GPTWin32]::GetForegroundWindow(), $sb, 512) | Out-Null
        Write-Output ("pid={0} hwnd={1} title='{2}' iconic={3} zoomed={4} client={5}x{6} fgIsGame={7} fgTitle='{8}' capture_method={9}" -f `
            $p.Id, $hw, $p.MainWindowTitle, [bool][GPTWin32]::IsIconic($hw), [bool][GPTWin32]::IsZoomed($hw),
            ($cr.Right - $cr.Left), ($cr.Bottom - $cr.Top), ([GPTWin32]::GetForegroundWindow() -eq $hw), $sb.ToString(), $Method)
    }
    "shot" {
        $p = Find-Win $cfg; $hw = $p.MainWindowHandle
        Prepare-Win $hw $TopmostMs
        try { $f = Capture-Frame $hw $Method } finally { Release-Win $hw }
        $dir = Get-EvidenceDir $cfg
        $name = if ([string]::IsNullOrWhiteSpace($Value)) { "shot_" + (Get-Date -Format "yyyyMMdd_HHmmss_fff") } else { $Value }
        $path = Save-Shot $f $dir $name
        Write-Output ("SHOT {0} method={1} size={2}x{3} white={4} black={5} colors={6}" -f `
            $path, $f.method, $f.w, $f.h, $f.white, $f.black, $f.colors)
        Write-Result ([ordered]@{ ok = $true; action = "shot"; path = $path; method = $f.method; size = @($f.w, $f.h); white = $f.white; black = $f.black; colors = $f.colors })
    }
    "hint" {
        $p = Find-Win $cfg; $hw = $p.MainWindowHandle
        $region = $null
        if ($cfg.capture -and $cfg.capture.crop_hint) { $region = @($cfg.capture.crop_hint) }
        elseif ($cfg.hint_region) { $region = @($cfg.hint_region) }
        if ($null -eq $region -or $region.Count -ne 4) { throw "hint requires config capture.crop_hint = [x, y, w, h] (client-area pixels)" }
        Prepare-Win $hw $TopmostMs
        try { $f = Capture-Frame $hw $Method } finally { Release-Win $hw }
        $dir = Get-EvidenceDir $cfg
        $name = if ([string]::IsNullOrWhiteSpace($Value)) { "hint_" + (Get-Date -Format "yyyyMMdd_HHmmss_fff") } else { $Value }
        $full = Save-Shot $f $dir $name
        $cx = [int]$region[0]; $cy = [int]$region[1]; $cw = [int]$region[2]; $ch = [int]$region[3]
        $bmp = [System.Drawing.Image]::FromFile($full)
        try {
            if ($cx -lt 0) { $cx = 0 }; if ($cy -lt 0) { $cy = 0 }
            if ($cx + $cw -gt $bmp.Width) { $cw = [math]::Max(1, $bmp.Width - $cx) }
            if ($cy + $ch -gt $bmp.Height) { $ch = [math]::Max(1, $bmp.Height - $cy) }
            $rect = New-Object System.Drawing.Rectangle($cx, $cy, $cw, $ch)
            $crop = $bmp.Clone($rect, [System.Drawing.Imaging.PixelFormat]::Format24bppRgb)
            $cropPath = Get-FreePath $dir ([System.IO.Path]::GetFileNameWithoutExtension($full) + "_hint") ".png"
            $crop.Save($cropPath, [System.Drawing.Imaging.ImageFormat]::Png); $crop.Dispose()
        } finally { $bmp.Dispose() }
        $cropFull = (Resolve-Path -LiteralPath $cropPath).Path
        Write-Output ("HINT full={0} crop={1} region={2},{3},{4},{5}" -f $full, $cropFull, $cx, $cy, $cw, $ch)
        Write-Result ([ordered]@{ ok = $true; action = "hint"; path = $full; crop = $cropFull; region = @($cx, $cy, $cw, $ch) })
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
            $dir = Get-EvidenceDir $cfg
            $out = Get-FreePath $dir ("region_" + (Get-Date -Format "yyyyMMdd_HHmmss_fff")) ".png"
            $crop.Save($out, [System.Drawing.Imaging.ImageFormat]::Png); $crop.Dispose()
        } finally { $bmp.Dispose() }
        Write-Output ("REGION {0} crop={1} rect={2},{3},{4},{5}" -f $src, (Resolve-Path -LiteralPath $out).Path, $cx, $cy, $cw, $ch)
    }
    default { throw "unknown action: $Action" }
}
