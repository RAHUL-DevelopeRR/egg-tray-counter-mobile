[CmdletBinding()]
param(
    # Run only the Python suites (backend, ml, scripts).
    [switch]$SkipFlutter
)

$ErrorActionPreference = 'Stop'
$ProjectRoot = Split-Path -Parent $PSScriptRoot
$VenvPython = Join-Path $ProjectRoot '.venv\Scripts\python.exe'
$BundledPython = if ($env:USERPROFILE) {
    Join-Path $env:USERPROFILE '.cache\codex-runtimes\codex-primary-runtime\dependencies\python\python.exe'
}
$VisionDeps = Join-Path $ProjectRoot 'work\vision-deps'
$FlutterBin = Join-Path $ProjectRoot 'work\toolchains\flutter\bin'

# Python: $env:EGG_PYTHON, then the project .venv, then the bundled Python 3.12 this checkout uses with the
# packages installed in work\vision-deps, then python on PATH.
$Python = @($env:EGG_PYTHON, $VenvPython, $BundledPython) |
    Where-Object { $_ -and (Test-Path -LiteralPath $_) } | Select-Object -First 1
if (-not $Python) {
    $Found = Get-Command python -ErrorAction SilentlyContinue
    if ($Found) { $Python = $Found.Source }
}
if (-not $Python) {
    throw 'No Python found. Set EGG_PYTHON, or run .\scripts\setup_windows.ps1 to create .venv.'
}
# A .venv has its own packages; any other Python takes them from work\vision-deps.
$PackagePath = @()
if (($Python -ne $VenvPython) -and (Test-Path -LiteralPath $VisionDeps)) { $PackagePath = @($VisionDeps) }
# faulthandler is disabled: it reports cv2's intermittent native exceptions as crashes on this machine.
$PytestArgs = @('-m', 'pytest', '-p', 'no:faulthandler')

$SavedPythonPath = $env:PYTHONPATH
$SavedPath = $env:Path
try {
    $env:PYTHONPATH = ($PackagePath -join ';')
    Push-Location (Join-Path $ProjectRoot 'backend')
    try {
        & $Python -m ruff check .
        if ($LASTEXITCODE -ne 0) { throw 'Backend lint failed.' }
        & $Python @PytestArgs
        if ($LASTEXITCODE -ne 0) { throw 'Backend tests failed.' }
    } finally {
        Pop-Location
    }

    $env:PYTHONPATH = ((@($ProjectRoot) + $PackagePath) -join ';')
    & $Python @PytestArgs (Join-Path $ProjectRoot 'ml\tests')
    if ($LASTEXITCODE -ne 0) { throw 'ML tests failed.' }

    # Offline tests of the field-scan scripts (replay, scoring, export); no network, no wrangler.
    $env:PYTHONPATH = ($PackagePath -join ';')
    & $Python @PytestArgs (Join-Path $ProjectRoot 'scripts\tests')
    if ($LASTEXITCODE -ne 0) { throw 'Script tests failed.' }

    if ($SkipFlutter) {
        Write-Host 'Flutter analyze/tests skipped (-SkipFlutter).'
        return
    }
    $FlutterBat = Join-Path $FlutterBin 'flutter.bat'
    if (Test-Path -LiteralPath $FlutterBat) {
        $env:Path = "$FlutterBin;$env:Path"
        $Flutter = $FlutterBat
    } else {
        $Found = Get-Command flutter -ErrorAction SilentlyContinue
        $Flutter = if ($Found) { $Found.Source } else { $null }
    }
    if (-not $Flutter) {
        Write-Warning 'Flutter is not installed (work\toolchains\flutter or PATH). Flutter analyze/tests skipped.'
        return
    }

    # Packages resolve from the default pub cache (or $env:PUB_CACHE when it is set).
    Push-Location (Join-Path $ProjectRoot 'mobile')
    try {
        & $Flutter analyze
        if ($LASTEXITCODE -ne 0) { throw 'Flutter analyze failed.' }
        & $Flutter test
        if ($LASTEXITCODE -ne 0) { throw 'Flutter tests failed.' }
    } finally {
        Pop-Location
    }
} finally {
    $env:PYTHONPATH = $SavedPythonPath
    $env:Path = $SavedPath
}
