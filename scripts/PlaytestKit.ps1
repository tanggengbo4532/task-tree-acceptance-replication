param(
    [Parameter(Mandatory = $true)][string]$Action,
    [string]$Value = "",
    [string]$Config = "playtest.json"
)

# Backward-compatibility shim (v1/v2 path). New code should call:
#   scripts/windows/PlaytestKit.ps1
# This file forwards every action and keeps old installs working.

$ErrorActionPreference = "Stop"
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$impl = Join-Path $here "windows\PlaytestKit.ps1"
if (-not (Test-Path -LiteralPath $impl)) { throw "backend implementation not found: $impl" }

& $impl -Action $Action -Value $Value -Config $Config
exit $LASTEXITCODE
