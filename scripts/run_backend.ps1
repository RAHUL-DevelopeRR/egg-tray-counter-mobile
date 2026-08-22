[CmdletBinding()]
param(
    [string]$HostAddress = '0.0.0.0',
    [int]$Port = 8000
)

$ErrorActionPreference = 'Stop'
$ProjectRoot = Split-Path -Parent $PSScriptRoot
$Python = Join-Path $ProjectRoot '.venv\Scripts\python.exe'
$BackendRoot = Join-Path $ProjectRoot 'backend'
$EnvFile = Join-Path $ProjectRoot '.env'

if (-not (Test-Path -LiteralPath $Python)) {
    throw 'Virtual environment missing. Run .\scripts\setup_windows.ps1 first.'
}

Push-Location $BackendRoot
try {
    $Arguments = @('-m', 'uvicorn', 'app.main:app', '--host', $HostAddress, '--port', $Port, '--reload')
    if (Test-Path -LiteralPath $EnvFile) {
        $Arguments += @('--env-file', $EnvFile)
    }
    & $Python @Arguments
}
finally {
    Pop-Location
}

