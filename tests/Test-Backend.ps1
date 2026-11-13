param(
    [ValidateSet("postmessage", "sendinput")][string]$Method = "postmessage",
    [switch]$KeepTemp
)

# tests/Test-Backend.ps1 - LIVE end-to-end check of the Windows reference backend.
# Opens a small fixture window (tests/fixtures/EchoWindow.ps1), drives it through
# PlaytestKit.ps1 and asserts on what the window actually received.
# Not part of the default self-check: it opens a real window and takes foreground.
#   powershell -NoProfile -ExecutionPolicy Bypass -File tests\Test-Backend.ps1
#   powershell -NoProfile -ExecutionPolicy Bypass -File tests\Test-Backend.ps1 -Method sendinput
# ASCII-only file.

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$kit = Join-Path $root "scripts\windows\PlaytestKit.ps1"
$fixture = Join-Path $root "tests\fixtures\EchoWindow.ps1"
$tmp = Join-Path ([System.IO.Path]::GetTempPath()) ("gptkit-backend-" + [Guid]::NewGuid().ToString("N").Substring(0, 8))
New-Item -ItemType Directory -Force -Path $tmp | Out-Null
$log = Join-Path $tmp "echo.log"
$title = "GPTKit-Echo-" + [Guid]::NewGuid().ToString("N").Substring(0, 6)
$cfgPath = Join-Path $tmp "playtest.json"
$cfg = [ordered]@{
    name = "echo-window"; backend = "windows"
    launch = (Get-Command powershell).Source
    args = @("-NoProfile", "-ExecutionPolicy", "Bypass", "-WindowStyle", "Hidden", "-File", ('"' + $fixture + '"'), "-Log", ('"' + $log + '"'), "-Title", $title)
    title_pattern = $title; startup_ms = 3500; focus_before_key = $true
    input = @{ method = $Method }
    keys = @{ default_hold_ms = 40; gap_ms = 120 }
    evidence = @{ dir = (Join-Path $tmp "evidence") }
}
($cfg | ConvertTo-Json -Depth 5) | Set-Content -LiteralPath $cfgPath -Encoding UTF8

$script:fails = @()
function Invoke-Kit([string[]]$kitArgs) {
    # native stderr must not become a terminating error (PS 5.1 wraps it in ErrorRecords)
    $prev = $ErrorActionPreference; $ErrorActionPreference = "Continue"
    try {
        $all = & powershell -NoProfile -ExecutionPolicy Bypass -File $kit @kitArgs 2>&1
        $rc = $LASTEXITCODE
    } finally { $ErrorActionPreference = $prev }
    $out = @($all | Where-Object { $_ -isnot [System.Management.Automation.ErrorRecord] } | ForEach-Object { [string]$_ })
    $last = @($out | Where-Object { $_ -and $_.Trim().StartsWith("{") }) | Select-Object -Last 1
    $obj = $null
    if ($last) { $obj = $last | ConvertFrom-Json }
    return [pscustomobject]@{ rc = $rc; json = $obj; raw = ($all | Out-String) }
}
function Kit([string]$action, [string]$value = "", [string]$config = $cfgPath) {
    $a = @("-Action", $action, "-Config", $config)
    if ($value -ne "") { $a += @("-Value", $value) }
    return Invoke-Kit $a
}
function Check([string]$name, [scriptblock]$body) {
    try { & $body; Write-Output ("PASS  " + $name) }
    catch { $script:fails += $name; Write-Output ("FAIL  " + $name + " : " + $_.Exception.Message) }
}
function LogText { if (Test-Path -LiteralPath $log) { return [string](Get-Content -LiteralPath $log -Raw) } return "" }

Push-Location $tmp
try {
    Check "launch returns pid + json" {
        $r = Kit "launch"
        if ($r.rc -ne 0 -or -not $r.json.ok) { throw ("rc=" + $r.rc + " " + $r.raw) }
        if ((LogText) -notmatch "READY") { throw "fixture did not report READY" }
    }
    Check "second launch refused (single instance)" {
        $r = Kit "launch"
        if ($r.rc -eq 0) { throw "second launch must fail" }
        if ($r.json.error -notmatch "single-instance") { throw ("unexpected error: " + $r.json.error) }
    }
    Check "info reports client size" {
        $r = Kit "info"
        if ($r.rc -ne 0) { throw $r.raw }
        if ($r.json.client[0] -ne 480 -or $r.json.client[1] -ne 320) { throw ("client=" + ($r.json.client -join "x")) }
    }
    Check "keys: lowercase letter maps to its own VK (a -> 65), named keys work" {
        $r = Kit "keys" "a,F2"
        if ($r.rc -ne 0) { throw $r.raw }
        Start-Sleep -Milliseconds 300
        $t = LogText
        if ($t -notmatch "KEYDOWN 65\b") { throw "expected KEYDOWN 65, log: $t" }
        if ($t -notmatch "KEYDOWN 113\b") { throw "expected KEYDOWN 113 (F2), log: $t" }
        if ($t -match "KEYDOWN 97\b") { throw "got NUMPAD1 (97): lowercase mapping bug" }
    }
    Check "keys: unknown key fails before sending anything" {
        $before = LogText
        $r = Kit "keys" "DOWN,NOPE"
        if ($r.rc -eq 0) { throw "must fail" }
        Start-Sleep -Milliseconds 200
        if ((LogText) -ne $before) { throw "partial input was sent" }
    }
    Check "type: text arrives in the focused control" {
        $r = Kit "type" "hello 42"
        if ($r.rc -ne 0) { throw $r.raw }
        Start-Sleep -Milliseconds 400
        if ((LogText) -notmatch "TEXT .*hello 42") { throw ("log: " + (LogText)) }
    }
    Check "click: button receives a real click" {
        $r = Kit "click" "100,130"
        if ($r.rc -ne 0) { throw $r.raw }
        Start-Sleep -Milliseconds 400
        if ((LogText) -notmatch "CLICK button") { throw ("log: " + (LogText)) }
    }
    Check "click: outside client area is rejected" {
        $r = Kit "click" "9000,9000"
        if ($r.rc -eq 0) { throw "must fail" }
    }
    Check "shot: absolute path, real frame, never overwrites" {
        $a = Kit "shot" "same"
        $b = Kit "shot" "same"
        if ($a.rc -ne 0 -or $b.rc -ne 0) { throw ($a.raw + $b.raw) }
        if ($a.json.path -eq $b.json.path) { throw "second shot overwrote the first" }
        if (-not (Test-Path -LiteralPath $a.json.path) -or -not (Test-Path -LiteralPath $b.json.path)) { throw "shot file missing" }
        if ($a.json.colors -le 2) { throw "blank frame" }
    }
    Check "hint without crop_hint is an error, not a guessed region" {
        $r = Kit "hint" "h"
        if ($r.rc -eq 0) { throw "must fail" }
    }
    Check "state is UNSUPPORTED (exit 3), not a fake success" {
        $r = Kit "state"
        if ($r.rc -ne 3 -or -not $r.json.unsupported) { throw ("rc=" + $r.rc + " " + $r.raw) }
    }
    Check "input log records injected input" {
        $il = Join-Path $tmp "evidence\input-log.jsonl"
        if (-not (Test-Path -LiteralPath $il)) { throw "input-log.jsonl missing" }
        $n = @(Get-Content -LiteralPath $il).Count
        if ($n -lt 3) { throw "expected >=3 entries, got $n" }
    }
    Check "close kills only the launched process" {
        $r = Kit "close"
        if ($r.rc -ne 0) { throw $r.raw }
        Start-Sleep -Milliseconds 500
        $left = @(Get-Process | Where-Object { $_.MainWindowTitle -eq $title })
        if ($left.Count -ne 0) { throw "window still alive" }
    }
    Check "no locator + no launch record: refuses to pick a window" {
        $bare = Join-Path $tmp "bare.json"
        '{"name":"x","launch":"x.exe"}' | Set-Content -LiteralPath $bare -Encoding UTF8
        $r = Kit "close" "" $bare
        if ($r.rc -eq 0) { throw "close without locator must fail" }
        if ($r.json.error -notmatch "no window locator") { throw $r.raw }
    }
} finally {
    if (Test-Path -LiteralPath (Join-Path $tmp ".playtest_pid")) { try { Kit "close" | Out-Null } catch { } }
    Pop-Location
    if (-not $KeepTemp) { Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue }
}

Write-Output ""
if ($script:fails.Count -gt 0) { Write-Output ("== Test-Backend ($Method): " + $script:fails.Count + " failed: " + ($script:fails -join ", ")); exit 1 }
Write-Output "== Test-Backend ($Method): ALL PASS =="
