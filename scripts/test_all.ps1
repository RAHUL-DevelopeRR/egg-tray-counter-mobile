[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$ProjectRoot = Split-Path -Parent $PSScriptRoot
$Python = Join-Path $ProjectRoot '.venv\Scripts\python.exe'
$Documents = [Environment]::GetFolderPath('MyDocuments')
$FlutterBin = Join-Path $Documents 'Codex\toolchains\flutter-3.47.1\flutter\bin'

if (-not (Test-Path -LiteralPath $Python)) {
    throw 'Virtual environment missing. Run .\scripts\setup_windows.ps1 first.'
}

Push-Location (Join-Path $ProjectRoot 'backend')
try {
    & $Python -m ruff check .
    if ($LASTEXITCODE -ne 0) { throw 'Backend lint failed.' }
    & $Python -m pytest
    if ($LASTEXITCODE -ne 0) { throw 'Backend tests failed.' }
} finally {
    Pop-Location
}

$env:PYTHONPATH = $ProjectRoot
& $Python -m pytest (Join-Path $ProjectRoot 'ml\tests')
if ($LASTEXITCODE -ne 0) { throw 'ML tests failed.' }

if (Test-Path -LiteralPath (Join-Path $FlutterBin 'flutter.bat')) {
    $env:Path = "$FlutterBin;$env:Path"
}
$Flutter = Get-Command flutter -ErrorAction SilentlyContinue
if (-not $Flutter) {
    Write-Warning 'Flutter is not installed. Flutter analyze/tests skipped.'
    exit 0
}

$ToolchainRoot = Join-Path $Documents 'Codex\toolchains'
$env:PUB_CACHE = Join-Path $ToolchainRoot 'pub-cache'
$env:APPDATA = Join-Path $ToolchainRoot 'appdata'
$env:LOCALAPPDATA = Join-Path $ToolchainRoot 'localappdata'
New-Item -ItemType Directory -Force -Path $env:PUB_CACHE, $env:APPDATA, $env:LOCALAPPDATA | Out-Null

Push-Location (Join-Path $ProjectRoot 'mobile')
try {
    & $Flutter.Source analyze
    if ($LASTEXITCODE -ne 0) { throw 'Flutter analyze failed.' }
    & $Flutter.Source test
    if ($LASTEXITCODE -ne 0) { throw 'Flutter tests failed.' }
} finally {
    Pop-Location
}
