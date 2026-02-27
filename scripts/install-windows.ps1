[CmdletBinding()]
param(
    [Parameter()]
    [string[]]$Skill,

    [Parameter()]
    [switch]$All,

    [Parameter()]
    [string]$Target,

    [Parameter()]
    [switch]$DryRun,

    [Parameter()]
    [switch]$Yes
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

if ($env:OS -ne "Windows_NT") {
    throw "install-windows.ps1 is for Windows only."
}

if ($PSVersionTable.PSVersion.Major -lt 7) {
    throw "PowerShell 7+ is required."
}

if (-not (Get-Command node -ErrorAction SilentlyContinue)) {
    throw "Node.js is required. Install Node.js 20+ and retry."
}

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$cliScript = Join-Path $scriptDir "node/skillpack-cli.mjs"
if (-not (Test-Path -LiteralPath $cliScript)) {
    throw "Node CLI not found: $cliScript"
}

$forwardArgs = @()
if ($Skill) {
    foreach ($name in $Skill) {
        $forwardArgs += @("--skill", $name)
    }
}
if ($All -or -not $Skill) {
    $forwardArgs += "--all"
}
if (-not [string]::IsNullOrWhiteSpace($Target)) {
    $forwardArgs += @("--target", $Target)
}
if ($DryRun) {
    $forwardArgs += "--dry-run"
}
if ($Yes) {
    $forwardArgs += "--yes"
}
$forwardArgs += @("--platform-hint", "windows")

& node $cliScript install @forwardArgs
if ($LASTEXITCODE -ne 0) {
    exit $LASTEXITCODE
}
