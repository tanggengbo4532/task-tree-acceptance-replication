param(
    [string]$Target = "",
    [switch]$Force,
    [switch]$DryRun,
    [switch]$Backup
)

# game-playtest installer v4
# - copies the whole skill (SKILL/README/plugin.json/scripts/tools/templates/examples/references/tests)
# - validates required files before touching the target
# - -DryRun prints the plan and changes nothing
# - -Force replaces target; -Backup saves existing target to <target>.bak-<timestamp> first
# ASCII-only file: Windows PowerShell 5.1 decodes .ps1 as ANSI/GBK.

$ErrorActionPreference = "Stop"
$src = Split-Path -Parent $MyInvocation.MyCommand.Path
if ([string]::IsNullOrWhiteSpace($Target)) {
    $Target = Join-Path $env:USERPROFILE ".dsh\skills\game-playtest"
}
$Target = [System.IO.Path]::GetFullPath($Target)

$required = @(
    "SKILL.md",
    "plugin.json",
    "scripts\windows\Common.ps1",
    "scripts\windows\PlaytestKit.ps1",
    "scripts\windows\Capture.ps1",
    "scripts\backends\web\adapter.py",
    "scripts\backends\CONTRACT.md",
    "tools\probes\walkprobe.py",
    "tools\probes\holdprobe.py",
    "tools\probes\fps_probe.py",
    "tools\evidence\manifest.py",
    "tools\metrics\dsh_metrics.py",
    "tools\tests\selftest.py",
    "tools\verify\common.py",
    "tools\verify\hud_walker.py",
    "tools\verify\anchor_check.py",
    "tools\verify\run_verify.py",
    "tools\verify\step_runner.py",
    "tools\verify\task_tree.py",
    "tools\verify\role_policy.py",
    "tools\verify\selftest.py",
    "templates\playtest.json",
    "templates\node-metrics.csv",
    "templates\design-experience.md",
    "references\roles\lead.md",
    "references\standards\no-cheat.md",
    "references\standards\role-permissions.md",
    "examples\quickstart.py",
    "examples\steps\notes-A1.json",
    "tests\fixtures\webapp\index.html",
    "CHANGELOG.md",
    "install.ps1"
)

$missing = @()
foreach ($rel in $required) {
    if (-not (Test-Path -LiteralPath (Join-Path $src $rel))) { $missing += $rel }
}
if ($missing.Count -gt 0) {
    throw ("install aborted, missing required files:`n  " + ($missing -join "`n  "))
}

$dirs = @("scripts", "templates", "examples")
$extraDirs = @("tools", "references", "tests")
$optionalFiles = @("README.md", "plugin.json", "SKILL.md", ".gitignore", "CHANGELOG.md")

Write-Output ("source: {0}" -f $src)
Write-Output ("target: {0}" -f $Target)
if ($DryRun) {
    $seen = New-Object 'System.Collections.Generic.HashSet[string]'
    foreach ($rel in $required) { [void]$seen.Add([System.IO.Path]::GetFullPath((Join-Path $src $rel))) }
    foreach ($f in $optionalFiles) {
        $p = Join-Path $src $f
        if (Test-Path -LiteralPath $p) { [void]$seen.Add([System.IO.Path]::GetFullPath($p)) }
    }
    foreach ($d in ($dirs + $extraDirs)) {
        $p = Join-Path $src $d
        if (Test-Path -LiteralPath $p) {
            foreach ($file in Get-ChildItem -LiteralPath $p -Recurse -File) { [void]$seen.Add([System.IO.Path]::GetFullPath($file.FullName)) }
        }
    }
    Write-Output ("[dry-run] would copy {0} unique files to {1}" -f $seen.Count, $Target)
    Write-Output "[dry-run] no changes made"
    return
}

if (Test-Path -LiteralPath $Target) {
    # -Force deletes the target recursively: refuse anything that is not a previous install of
    # this plugin, and refuse a target that contains the source (it would delete the source too).
    $srcFull = [System.IO.Path]::GetFullPath($src).TrimEnd("\")
    $tgtFull = $Target.TrimEnd("\")
    if ($tgtFull -eq $srcFull -or $srcFull.StartsWith($tgtFull + "\", [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "refusing to replace target: it is the source directory or contains it ($Target)"
    }
    $isPluginDir = (Test-Path -LiteralPath (Join-Path $Target "plugin.json")) -and (Test-Path -LiteralPath (Join-Path $Target "SKILL.md"))
    $isEmpty = -not (Get-ChildItem -LiteralPath $Target -Force | Select-Object -First 1)
    if (-not $isPluginDir -and -not $isEmpty) {
        throw "refusing to replace target: $Target does not look like a game-playtest install (no plugin.json + SKILL.md). Remove it yourself or pick another -Target."
    }
    if ($Backup) {
        $stamp = Get-Date -Format "yyyyMMdd_HHmmss"
        $bak = $Target + ".bak-" + $stamp
        Copy-Item -LiteralPath $Target -Destination $bak -Recurse -Force
        Write-Output ("backup: {0}" -f $bak)
    }
    if (-not $Force) {
        throw "target exists: $Target (use -Force to replace, or -Backup -Force)"
    }
    Remove-Item -LiteralPath $Target -Recurse -Force
}

New-Item -ItemType Directory -Force -Path $Target | Out-Null
foreach ($f in $optionalFiles) {
    $s = Join-Path $src $f
    if (Test-Path -LiteralPath $s) { Copy-Item -LiteralPath $s -Destination $Target -Force }
}
foreach ($d in $dirs) {
    $s = Join-Path $src $d
    if (Test-Path -LiteralPath $s) { Copy-Item -LiteralPath $s -Destination $Target -Recurse -Force }
}
Copy-Item -LiteralPath (Join-Path $src "install.ps1") -Destination $Target -Force
# defensive: never ship local caches / temp artifacts
Get-ChildItem -LiteralPath $Target -Recurse -Force -Directory -Filter "__pycache__" -ErrorAction SilentlyContinue | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
Get-ChildItem -LiteralPath $Target -Recurse -Force -File -ErrorAction SilentlyContinue | Where-Object { $_.Name -like ".tmp*" -or $_.Extension -eq ".pyc" } | Remove-Item -Force -ErrorAction SilentlyContinue
foreach ($d in $extraDirs) {
    $s = Join-Path $src $d
    if (Test-Path -LiteralPath $s) { Copy-Item -LiteralPath $s -Destination $Target -Recurse -Force }
}

$verify = @()
foreach ($rel in $required) {
    if (-not (Test-Path -LiteralPath (Join-Path $Target $rel))) { $verify += $rel }
}
if ($verify.Count -gt 0) {
    throw ("install verification failed, missing in target:`n  " + ($verify -join "`n  "))
}

Write-Output ("installed game-playtest v4 -> {0}" -f $Target)
Write-Output "self-check:"
Write-Output ("  python `"{0}`"" -f (Join-Path $Target "tools\tests\selftest.py"))
Write-Output ("  powershell -NoProfile -File `"{0}`" -DryRun" -f (Join-Path $Target "install.ps1"))
Write-Output "next: copy templates/playtest.json into your project and set launch/title_pattern/shot_dir (see examples/)."
