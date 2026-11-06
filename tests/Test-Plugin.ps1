param(
    [switch]$SkipPython,
    [switch]$KeepTemp
)

# tests/Test-Plugin.ps1 - packaging self-check (no game window, no user input)
#  1) parse every .ps1
#  2) parse plugin.json / examples / templates/playtest.json
#  3) install -DryRun must succeed and create nothing
#  4) install to a temp dir (no -Force needed) then verify required files
#  5) optional: run python tools/tests/selftest.py
# ASCII-only file: Windows PowerShell 5.1 reads .ps1 as ANSI/GBK.

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$script:fails = @()
function Check([string]$name, [scriptblock]$body) {
    try { & $body; Write-Output ("PASS  " + $name) }
    catch { $script:fails += $name; Write-Output ("FAIL  " + $name + " : " + $_.Exception.Message) }
}

Write-Output ("plugin root: " + $root)

Check "parse .ps1" {
    $scripts = Get-ChildItem -LiteralPath $root -Recurse -Filter *.ps1 -File
    if ($scripts.Count -eq 0) { throw "no .ps1 found" }
    foreach ($f in $scripts) {
        $errs = $null
        [System.Management.Automation.Language.Parser]::ParseFile($f.FullName, [ref]$null, [ref]$errs) | Out-Null
        if ($errs -and $errs.Count -gt 0) { throw ($f.Name + ": " + ($errs[0].Message)) }
    }
    Write-Output ("      parsed " + $scripts.Count + " files")
}

Check "parse json" {
    $files = @((Join-Path $root "plugin.json"),
               (Join-Path $root "templates\playtest.json"),
               (Join-Path $root "examples\pal98-godot.json"),
               (Join-Path $root "examples\generic-desktop.json"))
    foreach ($f in $files) {
        if (-not (Test-Path -LiteralPath $f)) { throw "missing " + $f }
        Get-Content -LiteralPath $f -Raw -Encoding UTF8 | ConvertFrom-Json | Out-Null
    }
    Write-Output ("      parsed " + $files.Count + " json files")
}

Check "no packaging pollution" {
    $bad = Get-ChildItem -LiteralPath $root -Recurse -Force -File -ErrorAction SilentlyContinue | Where-Object {
        $_.Directory.Name -eq "__pycache__" -or $_.Extension -eq ".pyc" -or $_.Name -like ".tmp*"
    }
    if ($bad.Count -gt 0) { throw ("found " + $bad.Count + " temp/cache files: " + (($bad | Select-Object -First 3 | ForEach-Object { $_.FullName }) -join ", ")) }
    Write-Output "      no __pycache__/.pyc/.tmp* in package"
}

Check "install -DryRun" {
    $before = $null
    $out = & (Join-Path $root "install.ps1") -DryRun 2>&1
    if ($LASTEXITCODE -ne $null -and $LASTEXITCODE -ne 0) { throw ("dry-run exit " + $LASTEXITCODE) }
    $text = ($out | Out-String)
    if ($text -notmatch "dry-run") { throw "missing dry-run marker" }
    if (Test-Path -LiteralPath (Join-Path $env:USERPROFILE ".dsh\skills\game-playtest-test-must-not-exist")) {
        throw "unexpected target created"
    }
    Write-Output "      dry-run ok (no changes)"
}

Check "install to temp dir + verify" {
    $tmp = Join-Path ([System.IO.Path]::GetTempPath()) ("game-playtest-selftest-" + [Guid]::NewGuid().ToString("N").Substring(0, 8))
    try {
        & (Join-Path $root "install.ps1") -Target $tmp 2>&1 | Out-Null
        if ($LASTEXITCODE -ne $null -and $LASTEXITCODE -ne 0) { throw ("install exit " + $LASTEXITCODE) }
        $must = @("SKILL.md", "plugin.json", "install.ps1",
                  "scripts\windows\PlaytestKit.ps1", "scripts\windows\Capture.ps1",
                  "scripts\backends\CONTRACT.md",
                  "tools\probes\walkprobe.py", "tools\probes\holdprobe.py", "tools\probes\fps_probe.py",
                  "tools\evidence\manifest.py", "tools\metrics\dsh_metrics.py", "tools\tests\selftest.py",
                  "templates\playtest.json", "templates\node-metrics.csv", "templates\evidence-index.md",
                  "references\roles\lead.md", "references\standards\no-cheat.md",
                  "references\testing\playbook.md", "CHANGELOG.md", "examples\generic-desktop.json")
        foreach ($rel in $must) {
            if (-not (Test-Path -LiteralPath (Join-Path $tmp $rel))) { throw ("missing in install: " + $rel) }
        }
        $count = (Get-ChildItem -LiteralPath $tmp -Recurse -File | Measure-Object).Count
        Write-Output ("      installed " + $count + " files -> " + $tmp)
    } finally {
        if (-not $KeepTemp -and (Test-Path -LiteralPath $tmp)) { Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue }
    }
}

if (-not $SkipPython) {
    Check "python selftest" {
        $py = (Get-Command python -ErrorAction SilentlyContinue)
        if (-not $py) { throw "python not found in PATH" }
        $env:PYTHONDONTWRITEBYTECODE = "1"
        & python -B (Join-Path $root "tools\tests\selftest.py") 2>&1 | Out-Null
        if ($LASTEXITCODE -ne 0) { throw ("selftest exit " + $LASTEXITCODE) }
        Remove-Item Env:\PYTHONDONTWRITEBYTECODE -ErrorAction SilentlyContinue
        Write-Output "      python tools/tests/selftest.py PASS"
    }
}

Write-Output ""
if ($fails.Count -gt 0) {
    Write-Output ("== Test-Plugin: " + $fails.Count + " failed: " + ($fails -join ", "))
    exit 1
}
Write-Output "== Test-Plugin: ALL PASS =="
