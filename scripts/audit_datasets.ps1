[CmdletBinding()]
param(
    [string]$LocalDataset = 'C:\Users\dharani\Downloads\Egg-Tray-Counter.yolov8 (1)',
    [string]$CloudDataset,
    [switch]$SkipReconciliation
)

$ErrorActionPreference = 'Stop'
$ProjectRoot = Split-Path -Parent $PSScriptRoot
$Python = Join-Path $ProjectRoot '.venv\Scripts\python.exe'
$Reports = Join-Path $ProjectRoot 'reports'
if (-not $CloudDataset) { $CloudDataset = Join-Path $ProjectRoot 'datasets\roboflow_auto_original' }
if (-not (Test-Path -LiteralPath $Python)) {
    throw 'Virtual environment missing. Run .\scripts\setup_windows.ps1 first.'
}

& $Python (Join-Path $ProjectRoot 'ml\audit_dataset.py') $LocalDataset `
    --json-output (Join-Path $Reports 'local_dataset_audit.json') `
    --markdown-output (Join-Path $Reports 'local_dataset_audit.md') `
    --title 'Local Manual Dataset Audit'
if ($LASTEXITCODE -ne 0) { throw 'Local dataset audit failed.' }

& $Python (Join-Path $ProjectRoot 'ml\audit_dataset.py') $CloudDataset `
    --json-output (Join-Path $Reports 'roboflow_dataset_audit.json') `
    --markdown-output (Join-Path $Reports 'roboflow_dataset_audit.md') `
    --title 'Roboflow Dataset Audit'
if ($LASTEXITCODE -ne 0) { throw 'Roboflow dataset audit failed.' }

if (-not $SkipReconciliation) {
    & $Python (Join-Path $ProjectRoot 'ml\reconcile_datasets.py') `
        --local-root $LocalDataset `
        --cloud-root $CloudDataset `
        --local-audit (Join-Path $Reports 'local_dataset_audit.json') `
        --cloud-audit (Join-Path $Reports 'roboflow_dataset_audit.json') `
        --output-root $ProjectRoot
    if ($LASTEXITCODE -ne 0) { throw 'Dataset reconciliation failed.' }
}
