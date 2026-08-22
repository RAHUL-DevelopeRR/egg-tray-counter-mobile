[CmdletBinding()]
param(
    [string]$HostAddress = '0.0.0.0',
    [int]$Port = 8000
)

$ErrorActionPreference = 'Stop'
$ProjectRoot = Split-Path -Parent $PSScriptRoot

if (-not $env:ROBOFLOW_API_KEY) {
    throw 'Set ROBOFLOW_API_KEY in this PowerShell session or in a private .env file first.'
}

$env:INFERENCE_PROVIDER = 'roboflow'
$env:ROBOFLOW_WORKSPACE = 'rahuls-workspace-l9ylz'
$env:ROBOFLOW_PROJECT = 'projec-mutta'
$env:ROBOFLOW_MODEL_ID = 'projec-mutta/2'
$env:ROBOFLOW_VERSION = '2'
$env:ROBOFLOW_INFERENCE_URL = 'https://serverless.roboflow.com'
$env:ALLOW_EXPERIMENTAL_TRAY_BOX_BASELINE = 'true'

Write-Warning 'V2 is an experimental SINGLE-STACK egg_tray detection baseline, not production counting.'
& (Join-Path $PSScriptRoot 'run_backend.ps1') -HostAddress $HostAddress -Port $Port
