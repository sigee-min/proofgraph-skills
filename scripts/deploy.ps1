[CmdletBinding()]
param(
    [Parameter()]
    [string[]]$Skill,

    [Parameter()]
    [switch]$All,

    [Parameter()]
    [string]$Target,

    [Parameter()]
    [switch]$DryRun
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

if (-not (Get-Command node -ErrorAction SilentlyContinue)) {
    throw "Node.js is required. Install Node.js 20+ and retry."
}

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$cliScript = Join-Path $scriptDir "node/skillpack-cli.mjs"
if (-not (Test-Path -LiteralPath $cliScript)) {
    throw "Node CLI not found: $cliScript"
}

$forwardArgs = @("deploy")
if ($Skill) {
    foreach ($name in $Skill) {
        $forwardArgs += @("--skill", $name)
    }
}
if ($All) {
    $forwardArgs += "--all"
}
if (-not [string]::IsNullOrWhiteSpace($Target)) {
    $forwardArgs += @("--target", $Target)
}
if ($DryRun) {
    $forwardArgs += "--dry-run"
}

& node $cliScript @forwardArgs
if ($LASTEXITCODE -ne 0) {
    exit $LASTEXITCODE
}
