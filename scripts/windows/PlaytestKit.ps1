param(
    [Parameter(Mandatory = $true)][string]$Action,
    [string]$Value = "",
    [string]$Config = "playtest.json"
)

# game-playtest / PlaytestKit.ps1  v4 (Windows backend reference implementation)
# Action contract: scripts/backends/CONTRACT.md
#   launch | close | focus | info | keys | hold | diag | click | type | scroll | shot | hint
#   unsupported here (exit 3): state | read_text | test_fast | failure_snapshot
# Output: optional human line(s), then ONE JSON line as the LAST stdout line:
#   {"ok":true,"action":"shot","path":"C:\\...\\a.png",...}   (exit 0)
#   {"ok":false,"action":"keys","error":"..."}                 (exit 1)
#   {"ok":false,"action":"state","unsupported":true,...}       (exit 3)
# Input method: config input.method = "postmessage" (default, no cursor hijack) | "sendinput"
#   (real global input; target must be foreground). keys.allow_postmessage=false also selects sendinput.
# ASCII-only file: Windows PowerShell 5.1 decodes .ps1 as ANSI/GBK.

$ErrorActionPreference = "Stop"
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $here "Common.ps1")
$CaptureScript = Join-Path $here "Capture.ps1"

function Get-KeyEnv([string]$name) {
    $raw = $name.Trim()
    $n = $raw.Trim("{").Trim("}").ToUpperInvariant()
    $map = @{
        "ENTER" = 0x0D; "RETURN" = 0x0D; "SPACE" = 0x20; "ESC" = 0x1B; "ESCAPE" = 0x1B
        "UP" = 0x26; "DOWN" = 0x28; "LEFT" = 0x25; "RIGHT" = 0x27; "TAB" = 0x09; "BACKSPACE" = 0x08
        "DELETE" = 0x2E; "INSERT" = 0x2D; "HOME" = 0x24; "END" = 0x23; "PGUP" = 0x21; "PGDN" = 0x22
        "SHIFT" = 0x10; "CTRL" = 0x11; "ALT" = 0x12
        "F1" = 0x70; "F2" = 0x71; "F3" = 0x72; "F4" = 0x73; "F5" = 0x74; "F6" = 0x75; "F7" = 0x76
        "F8" = 0x77; "F9" = 0x78; "F10" = 0x79; "F11" = 0x7A; "F12" = 0x7B
    }
    if ($map.ContainsKey($n)) { return [int]$map[$n] }
    if ($raw.Length -eq 1) {
        # layout-aware: 'a' and 'A' both map to VK 0x41; punctuation maps to its OEM key
        $r = [int][GPTWin32]::VkKeyScanW([char]$raw)
        if ($r -ne -1) { return ($r -band 0xFF) }
    }
    throw "unknown key: '$name' (use names like UP/DOWN/SPACE/ENTER/ESC/TAB/F1 or a single character; use the 'type' action for text)"
}

function Get-InputMethod($cfg) {
    if ($cfg.input -and $cfg.input.method) {
        $m = ([string]$cfg.input.method).ToLowerInvariant()
        if ($m -ne "postmessage" -and $m -ne "sendinput") { throw "config input.method must be postmessage or sendinput (got '$m')" }
        return $m
    }
    if ($cfg.keys -and $cfg.keys.allow_postmessage -eq $false) { return "sendinput" }
    return "postmessage"
}

# sendinput goes to whatever is foreground: refuse unless that is the target window.
function Assert-Foreground($p) {
    if ([GPTWin32]::GetForegroundWindow() -ne $p.MainWindowHandle) {
        $fgPid = [GPTWin32]::PidOf([GPTWin32]::GetForegroundWindow())
        if ($fgPid -ne $p.Id) { throw "input gate: target window is not foreground (foreground pid=$fgPid); refusing to send global input" }
    }
}

function Prepare-Input($cfg, $p, [string]$method) {
    if ($method -eq "sendinput" -or $cfg.focus_before_key -ne $false) { Focus-Win $p }
    if ($method -eq "sendinput") { Assert-Foreground $p }
}

function Send-Down($p, [int]$vk, [string]$method) {
    if ($method -eq "sendinput") {
        if (-not [GPTWin32]::Key([uint16]$vk, $false)) { throw "SendInput keydown failed (vk=$vk)" }
        return
    }
    $hw = [GPTWin32]::FocusOf($p.MainWindowHandle)
    $scan = [int][GPTWin32]::MapVirtualKey([uint32]$vk, 0)
    $l = 1 -bor ($scan -shl 16)
    if ([GPTWin32]::IsExtended([uint32]$vk)) { $l = $l -bor 0x01000000 }
    [GPTWin32]::PostMessage($hw, 0x0100, [IntPtr]$vk, [IntPtr]$l) | Out-Null
}
function Send-Up($p, [int]$vk, [string]$method) {
    if ($method -eq "sendinput") {
        if (-not [GPTWin32]::Key([uint16]$vk, $true)) { throw "SendInput keyup failed (vk=$vk)" }
        return
    }
    $hw = [GPTWin32]::FocusOf($p.MainWindowHandle)
    $scan = [int][GPTWin32]::MapVirtualKey([uint32]$vk, 0)
    $l = 0xC0000001 -bor ($scan -shl 16)
    if ([GPTWin32]::IsExtended([uint32]$vk)) { $l = $l -bor 0x01000000 }
    [GPTWin32]::PostMessage($hw, 0x0101, [IntPtr]$vk, [IntPtr]$l) | Out-Null
}

function Get-HoldMs($cfg) {
    if ($cfg.keys -and $cfg.keys.default_hold_ms) { return [int]$cfg.keys.default_hold_ms }
    return 60
}
function Get-GapMs($cfg) {
    if ($cfg.keys -and $cfg.keys.gap_ms) { return [int]$cfg.keys.gap_ms }
    return 550
}

# Client (x,y) -> screen point + the window actually under that point (must belong to the target).
function Resolve-Point($p, [int]$x, [int]$y) {
    $hw = $p.MainWindowHandle
    $cr = New-Object GPTWin32+RECT; [GPTWin32]::GetClientRect($hw, [ref]$cr) | Out-Null
    if ($x -lt 0 -or $y -lt 0 -or $x -ge ($cr.Right - $cr.Left) -or $y -ge ($cr.Bottom - $cr.Top)) {
        throw ("point ({0},{1}) is outside the client area {2}x{3}" -f $x, $y, ($cr.Right - $cr.Left), ($cr.Bottom - $cr.Top))
    }
    $pt = New-Object GPTWin32+POINT; $pt.X = $x; $pt.Y = $y
    [GPTWin32]::ClientToScreen($hw, [ref]$pt) | Out-Null
    $under = [GPTWin32]::WindowFromPoint($pt)
    if ([GPTWin32]::PidOf($under) -ne $p.Id) {
        throw ("input gate: point ({0},{1}) is covered by another window (pid={2}); refusing to click" -f $x, $y, [GPTWin32]::PidOf($under))
    }
    return [pscustomobject]@{ screen = $pt; hwnd = $under }
}

function Split-Ints([string]$text, [int]$min, [string]$usage) {
    $parts = @($text.Split(",") | ForEach-Object { $_.Trim() })
    if ($parts.Count -lt $min) { throw $usage }
    return $parts
}

function Invoke-Capture([string]$act) {
    if (-not (Test-Path -LiteralPath $CaptureScript)) { throw "Capture.ps1 not found: $CaptureScript" }
    & $CaptureScript -Action $act -Value $Value -Config $Config
}

$act = $Action.ToLowerInvariant()
if ($act -eq "screenshot") { $act = "shot" }

try {
    $cfg = Read-Cfg $Config

    switch ($act) {
        "launch" {
            $exe = [string]$cfg.launch
            if ([string]::IsNullOrWhiteSpace($exe)) { throw "config.launch is required" }
            $old = Read-PidInfo
            if ($old) {
                if (Get-LaunchedProcess $old) { throw "single-instance rule: previous pid=$($old.pid) is still running (run close first)" }
                Remove-Item -LiteralPath (Get-PidFile) -Force -ErrorAction SilentlyContinue
            }
            $argv = @()
            if ($cfg.args) { $argv = @($cfg.args | ForEach-Object { [string]$_ }) }
            if ($argv.Count -gt 0) { $p = Start-Process -FilePath $exe -ArgumentList $argv -PassThru }
            else { $p = Start-Process -FilePath $exe -PassThru }
            $start = ""
            try { $start = [string]$p.StartTime.Ticks } catch { }
            Write-PidInfo $p.Id $start 0
            $waitMs = if ($cfg.startup_ms) { [int]$cfg.startup_ms } else { 8000 }
            Start-Sleep -Milliseconds $waitMs
            try { $win = Find-Win $cfg }
            catch { throw ("launched pid={0} but no target window after startup_ms={1}: {2} (run close to clean up)" -f $p.Id, $waitMs, $_.Exception.Message) }
            if ($win.Id -ne $p.Id) { Write-PidInfo $p.Id $start $win.Id }
            Write-Output ("launched pid={0} hwnd={1} title='{2}'" -f $win.Id, $win.MainWindowHandle, $win.MainWindowTitle)
            Write-Result ([ordered]@{ ok = $true; action = "launch"; pid = $win.Id; launched_pid = $p.Id; hwnd = [int64]$win.MainWindowHandle; title = $win.MainWindowTitle })
        }

        "close" {
            $closed = @()
            $info = Read-PidInfo
            if ($info) {
                $lp = Get-LaunchedProcess $info
                if ($lp) { Stop-Process -Id $lp.Id -Force -ErrorAction SilentlyContinue; $closed += $lp.Id }
                if ($info.winpid -gt 0 -and $info.winpid -ne $info.pid) {
                    # the window owner is only trusted while it still matches the configured locator
                    $pattern = if ($cfg.title_pattern) { [string]$cfg.title_pattern } else { "" }
                    $exe = if ($cfg.process_name) { [string]$cfg.process_name } else { "" }
                    $wp = Get-Process -Id $info.winpid -ErrorAction SilentlyContinue
                    if ($wp -and ($pattern -ne "" -or $exe -ne "") -and (Test-WinMatch $wp $pattern $exe)) {
                        Stop-Process -Id $wp.Id -Force -ErrorAction SilentlyContinue; $closed += $wp.Id
                    }
                }
                Remove-Item -LiteralPath (Get-PidFile) -Force -ErrorAction SilentlyContinue
            }
            if ($closed.Count -eq 0 -and -not $info) {
                # no launch record: only a unique, explicitly located window may be closed
                $p = Find-Win $cfg
                Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue
                $closed += $p.Id
            }
            if ($closed.Count -eq 0) { Write-Output "closed: launched process had already exited" }
            else { Write-Output ("closed pid=" + ($closed -join ",")) }
            Write-Result ([ordered]@{ ok = $true; action = "close"; pids = @($closed) })
        }

        "focus" {
            $p = Find-Win $cfg
            Focus-Win $p
            Write-Output ("focused pid={0} hwnd={1} title='{2}'" -f $p.Id, $p.MainWindowHandle, $p.MainWindowTitle)
            Write-Result ([ordered]@{ ok = $true; action = "focus"; pid = $p.Id; hwnd = [int64]$p.MainWindowHandle; title = $p.MainWindowTitle })
        }

        "info" {
            $p = Find-Win $cfg
            $hw = $p.MainWindowHandle
            $wr = New-Object GPTWin32+RECT; [GPTWin32]::GetWindowRect($hw, [ref]$wr) | Out-Null
            $cr = New-Object GPTWin32+RECT; [GPTWin32]::GetClientRect($hw, [ref]$cr) | Out-Null
            $pt = New-Object GPTWin32+POINT; $pt.X = 0; $pt.Y = 0
            [GPTWin32]::ClientToScreen($hw, [ref]$pt) | Out-Null
            $fg = [GPTWin32]::GetForegroundWindow()
            $sb = New-Object System.Text.StringBuilder 512
            [GPTWin32]::GetWindowTextW($fg, $sb, 512) | Out-Null
            $iconic = [bool][GPTWin32]::IsIconic($hw); $zoomed = [bool][GPTWin32]::IsZoomed($hw)
            $fgIsTarget = ($fg -eq $hw)
            Write-Output ("pid={0} hwnd={1} title='{2}' iconic={3} zoomed={4} rect=({5},{6})-({7},{8}) client={9}x{10} clientOrigin=({11},{12}) fgIsGame={13} fgTitle='{14}'" -f `
                $p.Id, $hw, $p.MainWindowTitle, $iconic, $zoomed,
                $wr.Left, $wr.Top, $wr.Right, $wr.Bottom, ($cr.Right - $cr.Left), ($cr.Bottom - $cr.Top), $pt.X, $pt.Y, $fgIsTarget, $sb.ToString())
            Write-Result ([ordered]@{
                ok = $true; action = "info"; pid = $p.Id; hwnd = [int64]$hw; title = $p.MainWindowTitle
                iconic = $iconic; zoomed = $zoomed
                rect = @($wr.Left, $wr.Top, $wr.Right, $wr.Bottom)
                client = @(($cr.Right - $cr.Left), ($cr.Bottom - $cr.Top)); client_origin = @($pt.X, $pt.Y)
                foreground = $fgIsTarget; foreground_title = $sb.ToString(); input_method = (Get-InputMethod $cfg)
            })
        }

        "keys" {
            $names = @($Value.Split(",") | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | ForEach-Object { $_.Trim() })
            if ($names.Count -eq 0) { throw "keys requires VALUE=KEY[,KEY...]" }
            $vks = @($names | ForEach-Object { Get-KeyEnv $_ })   # validate everything before sending anything
            $p = Find-Win $cfg
            $method = Get-InputMethod $cfg
            Prepare-Input $cfg $p $method
            $hold = Get-HoldMs $cfg; $gap = Get-GapMs $cfg
            foreach ($vk in $vks) {
                Send-Down $p $vk $method
                Start-Sleep -Milliseconds ([math]::Max(20, $hold))
                Send-Up $p $vk $method
                Start-Sleep -Milliseconds $gap
            }
            Write-InputLog $cfg "keys" ($names -join ",") $method
            Write-Output ("keys: " + ($names -join ","))
            Write-Result ([ordered]@{ ok = $true; action = "keys"; keys = @($names); method = $method; hold_ms = $hold; gap_ms = $gap })
        }

        "hold" {
            $parts = Split-Ints $Value 2 "hold requires VALUE=KEY,MS"
            $vk = Get-KeyEnv $parts[0]; $ms = [int]$parts[1]
            $p = Find-Win $cfg
            $method = Get-InputMethod $cfg
            Prepare-Input $cfg $p $method
            Send-Down $p $vk $method
            try { Start-Sleep -Milliseconds $ms } finally { Send-Up $p $vk $method }
            Write-InputLog $cfg "hold" $Value $method
            Write-Output ("hold {0} {1}ms" -f $parts[0], $ms)
            Write-Result ([ordered]@{ ok = $true; action = "hold"; key = $parts[0]; ms = $ms; method = $method })
        }

        "diag" {
            $parts = Split-Ints $Value 3 "diag requires VALUE=KEY1,KEY2,MS"
            $vk1 = Get-KeyEnv $parts[0]; $vk2 = Get-KeyEnv $parts[1]; $ms = [int]$parts[2]
            $p = Find-Win $cfg
            $method = Get-InputMethod $cfg
            Prepare-Input $cfg $p $method
            Send-Down $p $vk1 $method; Send-Down $p $vk2 $method
            try { Start-Sleep -Milliseconds $ms } finally { Send-Up $p $vk2 $method; Send-Up $p $vk1 $method }
            Write-InputLog $cfg "diag" $Value $method
            Write-Output ("diag {0}+{1} {2}ms" -f $parts[0], $parts[1], $ms)
            Write-Result ([ordered]@{ ok = $true; action = "diag"; keys = @($parts[0], $parts[1]); ms = $ms; method = $method })
        }

        "click" {
            $parts = Split-Ints $Value 2 "click requires VALUE=X,Y[,left|right|double] (client-area pixels)"
            $x = [int]$parts[0]; $y = [int]$parts[1]
            $button = if ($parts.Count -ge 3) { $parts[2].ToLowerInvariant() } else { "left" }
            if (@("left", "right", "double") -notcontains $button) { throw "click button must be left, right or double (got '$button')" }
            $p = Find-Win $cfg
            $method = Get-InputMethod $cfg
            Prepare-Input $cfg $p $method
            $t = Resolve-Point $p $x $y
            $times = if ($button -eq "double") { 2 } else { 1 }
            if ($method -eq "sendinput") {
                [GPTWin32]::SetCursorPos($t.screen.X, $t.screen.Y) | Out-Null
                Start-Sleep -Milliseconds 60
                $down = if ($button -eq "right") { 0x0008 } else { 0x0002 }
                $up = if ($button -eq "right") { 0x0010 } else { 0x0004 }
                for ($i = 0; $i -lt $times; $i++) {
                    [GPTWin32]::Mouse([uint32]$down, 0) | Out-Null; Start-Sleep -Milliseconds 40
                    [GPTWin32]::Mouse([uint32]$up, 0) | Out-Null; Start-Sleep -Milliseconds 60
                }
            } else {
                $cp = New-Object GPTWin32+POINT; $cp.X = $t.screen.X; $cp.Y = $t.screen.Y
                [GPTWin32]::ScreenToClient($t.hwnd, [ref]$cp) | Out-Null
                $l = [IntPtr](($cp.Y -shl 16) -bor ($cp.X -band 0xFFFF))
                $down = if ($button -eq "right") { 0x0204 } else { 0x0201 }
                $up = if ($button -eq "right") { 0x0205 } else { 0x0202 }
                $w = if ($button -eq "right") { 2 } else { 1 }
                for ($i = 0; $i -lt $times; $i++) {
                    [GPTWin32]::PostMessage($t.hwnd, [uint32]$down, [IntPtr]$w, $l) | Out-Null; Start-Sleep -Milliseconds 40
                    [GPTWin32]::PostMessage($t.hwnd, [uint32]$up, [IntPtr]0, $l) | Out-Null; Start-Sleep -Milliseconds 60
                }
            }
            Write-InputLog $cfg "click" $Value $method
            Write-Output ("click {0},{1} {2}" -f $x, $y, $button)
            Write-Result ([ordered]@{ ok = $true; action = "click"; x = $x; y = $y; button = $button; method = $method })
        }

        "type" {
            if ($Value.Length -eq 0) { throw "type requires VALUE=TEXT" }
            $p = Find-Win $cfg
            $method = Get-InputMethod $cfg
            Prepare-Input $cfg $p $method
            foreach ($ch in $Value.ToCharArray()) {
                if ($method -eq "sendinput") {
                    [GPTWin32]::UnicodeChar($ch, $false) | Out-Null
                    [GPTWin32]::UnicodeChar($ch, $true) | Out-Null
                } else {
                    [GPTWin32]::PostMessage([GPTWin32]::FocusOf($p.MainWindowHandle), 0x0102, [IntPtr][int]$ch, [IntPtr]1) | Out-Null
                }
                Start-Sleep -Milliseconds 25
            }
            Write-InputLog $cfg "type" $Value $method
            Write-Output ("type: {0} chars" -f $Value.Length)
            Write-Result ([ordered]@{ ok = $true; action = "type"; chars = $Value.Length; method = $method })
        }

        "scroll" {
            $parts = Split-Ints $Value 3 "scroll requires VALUE=X,Y,NOTCHES (client-area pixels; positive = up, negative = down)"
            $x = [int]$parts[0]; $y = [int]$parts[1]; $notches = [int]$parts[2]
            $p = Find-Win $cfg
            $method = Get-InputMethod $cfg
            Prepare-Input $cfg $p $method
            $t = Resolve-Point $p $x $y
            if ($method -eq "sendinput") {
                [GPTWin32]::SetCursorPos($t.screen.X, $t.screen.Y) | Out-Null
                Start-Sleep -Milliseconds 60
                [GPTWin32]::Mouse([uint32]0x0800, ($notches * 120)) | Out-Null
            } else {
                $w = [IntPtr](($notches * 120) -shl 16)
                $l = [IntPtr](($t.screen.Y -shl 16) -bor ($t.screen.X -band 0xFFFF))
                [GPTWin32]::PostMessage($t.hwnd, 0x020A, $w, $l) | Out-Null
            }
            Write-InputLog $cfg "scroll" $Value $method
            Write-Output ("scroll {0},{1} {2}" -f $x, $y, $notches)
            Write-Result ([ordered]@{ ok = $true; action = "scroll"; x = $x; y = $y; notches = $notches; method = $method })
        }

        "shot" { Invoke-Capture "shot" }
        "hint" { Invoke-Capture "hint" }

        { @("state", "read_text", "test_fast", "failure_snapshot") -contains $_ } {
            Write-Output ("UNSUPPORTED {0}: the windows backend injects input and captures pixels only; expose app state through an engine/app adapter (see scripts/backends/CONTRACT.md)" -f $act)
            Write-Result ([ordered]@{ ok = $false; action = $act; unsupported = $true; error = "$act is not implemented by the windows backend" })
            [Console]::Error.WriteLine("$act is not implemented by the windows backend")
            exit 3
        }

        default {
            throw "unknown action: $Action (supported: launch/close/focus/info/keys/hold/diag/click/type/scroll/shot/hint; unsupported: state/read_text/test_fast/failure_snapshot)"
        }
    }
    exit 0
} catch {
    $msg = $_.Exception.Message
    Write-Result ([ordered]@{ ok = $false; action = $act; error = $msg })
    [Console]::Error.WriteLine($msg)
    exit 1
}
