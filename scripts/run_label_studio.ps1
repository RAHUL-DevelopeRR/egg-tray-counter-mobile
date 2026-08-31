[CmdletBinding()]
param(
    [ValidateSet('stack_face_review', 'stack_face_review_dense', 'review')]
    [string]$ReviewSet = 'stack_face_review',
    [ValidateRange(1, 65535)]
    [int]$Port = 8080,
    [string]$InternalHost = '127.0.0.1',
    [switch]$NoBrowser
)

$ErrorActionPreference = 'Stop'
$ProjectRoot = Split-Path -Parent $PSScriptRoot
$ToolRoot = Join-Path $ProjectRoot 'tools\labelstudio'
$Executable = Join-Path $ToolRoot '.venv\Scripts\label-studio.exe'
$DataRoot = Join-Path $ToolRoot 'data'
$DatasetRoot = Join-Path $ProjectRoot 'datasets'
$ReviewRoot = Join-Path $DatasetRoot $ReviewSet
$Tasks = Join-Path $ReviewRoot 'tasks.json'
$LabelConfig = Join-Path $ReviewRoot 'label_config.xml'

if (-not (Test-Path -LiteralPath $Executable)) {
    throw "Label Studio is not installed at $Executable"
}
if (-not (Test-Path -LiteralPath $Tasks)) {
    throw "Review tasks not found at $Tasks"
}
if (-not (Test-Path -LiteralPath $LabelConfig)) {
    throw "Label configuration not found at $LabelConfig"
}

New-Item -ItemType Directory -Force -Path $DataRoot | Out-Null

# stack_face_review tasks reference datasets/canonical_clean; the legacy review
# tasks reference files relative to datasets/review.
$LocalFilesRoot = if ($ReviewSet -like 'stack_face_review*') {
    $DatasetRoot
}
else {
    $ReviewRoot
}

$env:BASE_DATA_DIR = $DataRoot
$env:LABEL_STUDIO_LOCAL_FILES_SERVING_ENABLED = 'true'
$env:LABEL_STUDIO_LOCAL_FILES_DOCUMENT_ROOT = $LocalFilesRoot
$env:LABEL_STUDIO_LATEST_VERSION_CHECK = 'false'

Write-Host "Label Studio: http://${InternalHost}:$Port"
Write-Host "Review set: $ReviewSet"
Write-Host "Label config: $LabelConfig"
Write-Host "Tasks to import once: $Tasks"
Write-Host 'The launcher does not import tasks automatically, so reruns cannot duplicate them.'

$Arguments = @(
    'start', '.',
    '--internal-host', $InternalHost,
    '--port', $Port,
    '--data-dir', $DataRoot
)
if ($NoBrowser) {
    $Arguments += '--no-browser'
}

& $Executable @Arguments
