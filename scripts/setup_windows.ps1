[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$ProjectRoot = Split-Path -Parent $PSScriptRoot
$Python = Join-Path $ProjectRoot '.venv\Scripts\python.exe'
$MobileRoot = Join-Path $ProjectRoot 'mobile'
$Documents = [Environment]::GetFolderPath('MyDocuments')
$ToolchainRoot = Join-Path $Documents 'Codex\toolchains'
$FlutterBin = Join-Path $ToolchainRoot 'flutter-3.47.1\flutter\bin'
$OriginalLocalAppData = $env:LOCALAPPDATA

if (Test-Path -LiteralPath (Join-Path $FlutterBin 'flutter.bat')) {
    $env:Path = "$FlutterBin;$env:Path"
    $UserPath = [Environment]::GetEnvironmentVariable('Path', 'User')
    if (($UserPath -split ';') -notcontains $FlutterBin) {
        try {
            [Environment]::SetEnvironmentVariable('Path', "$FlutterBin;$UserPath", 'User')
            Write-Host 'Flutter added to the user PATH. New terminals will detect it.'
        }
        catch {
            Write-Warning 'Could not persist the Flutter user PATH; this shell is configured.'
        }
    }
}

$AndroidSdk = if ($env:ANDROID_SDK_ROOT) {
    $env:ANDROID_SDK_ROOT
} elseif ($env:ANDROID_HOME) {
    $env:ANDROID_HOME
} elseif ($OriginalLocalAppData) {
    Join-Path $OriginalLocalAppData 'Android\Sdk'
}
if ($AndroidSdk -and (Test-Path -LiteralPath $AndroidSdk)) {
    $env:ANDROID_HOME = $AndroidSdk
    $env:ANDROID_SDK_ROOT = $AndroidSdk
}

$env:PUB_CACHE = Join-Path $ToolchainRoot 'pub-cache'
$env:APPDATA = Join-Path $ToolchainRoot 'appdata'
$env:LOCALAPPDATA = Join-Path $ToolchainRoot 'localappdata'
New-Item -ItemType Directory -Force -Path $env:PUB_CACHE, $env:APPDATA, $env:LOCALAPPDATA | Out-Null

if (-not (Test-Path -LiteralPath $Python)) {
    $Launcher = Get-Command py -ErrorAction SilentlyContinue
    $SystemPython = Get-Command python -ErrorAction SilentlyContinue
    if ($Launcher) {
        & $Launcher.Source -3 -m venv (Join-Path $ProjectRoot '.venv')
    } elseif ($SystemPython) {
        & $SystemPython.Source -m venv (Join-Path $ProjectRoot '.venv')
    } else {
        throw 'Python 3.11+ is not installed or not on PATH.'
    }
}

& $Python -m pip install --disable-pip-version-check -r (Join-Path $ProjectRoot 'backend\requirements-dev.txt')

$Flutter = Get-Command flutter -ErrorAction SilentlyContinue
if (-not $Flutter) {
    Write-Warning 'Flutter is not installed. Backend setup completed; mobile setup skipped.'
    exit 0
}

if (-not (Test-Path -LiteralPath (Join-Path $MobileRoot 'android\app\build.gradle.kts'))) {
    Push-Location $MobileRoot
    try {
        & $Flutter.Source create --platforms=android --org com.dharani.eggtray --project-name egg_tray_counter .
    } finally {
        Pop-Location
    }
}

Push-Location $MobileRoot
try {
    & $Flutter.Source pub get
    & $Flutter.Source doctor -v
} finally {
    Pop-Location
}

if (-not $AndroidSdk -or -not (Test-Path -LiteralPath $AndroidSdk)) {
    Write-Warning 'Android SDK not found. Install it with Android Studio before building an APK.'
}

Write-Host 'Setup complete.'
