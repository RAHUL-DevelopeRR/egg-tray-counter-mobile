[CmdletBinding()]
param(
    [string]$DatasetPath = 'C:\Users\dharani\Downloads\Egg-Tray-Counter.yolov8 (1)'
)

$ErrorActionPreference = 'Stop'
$ProjectRoot = Split-Path -Parent $PSScriptRoot
$Python = Join-Path $ProjectRoot '.venv\Scripts\python.exe'
if (-not (Test-Path -LiteralPath $Python)) {
    throw 'Virtual environment missing. Run .\scripts\setup_windows.ps1 first.'
}

& $Python (Join-Path $ProjectRoot 'ml\audit_dataset.py') $DatasetPath `
    --json-output (Join-Path $ProjectRoot 'reports\local_dataset_audit.json') `
    --markdown-output (Join-Path $ProjectRoot 'reports\local_dataset_audit.md') `
    --title 'Local Manual Dataset Audit'
if ($LASTEXITCODE -ne 0) { throw 'Dataset audit failed.' }
