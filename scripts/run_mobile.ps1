[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$ProjectRoot = Split-Path -Parent $PSScriptRoot
$MobileRoot = Join-Path $ProjectRoot 'mobile'
$Flutter = Get-Command flutter -ErrorAction SilentlyContinue

if (-not $Flutter) {
    throw 'ENVIRONMENT NOT INSTALLED: Flutter is not on PATH.'
}
if (-not (Test-Path -LiteralPath (Join-Path $MobileRoot 'android\app\build.gradle.kts'))) {
    throw 'Flutter platform files are missing. Run .\scripts\setup_windows.ps1 first.'
}

Push-Location $MobileRoot
try {
    & $Flutter.Source run
}
finally {
    Pop-Location
}

