param(
    [string]$Adb = 'adb',
    [string]$Device = 'emulator-5556',
    [string]$OutputDirectory = 'startup-check'
)
$ErrorActionPreference = 'Stop'
$package = 'com.dharani.eggtray.egg_tray_counter'
New-Item -ItemType Directory -Force -Path $OutputDirectory | Out-Null
for ($attempt = 1; $attempt -le 3; $attempt++) {
    & $Adb -s $Device shell am force-stop $package
    & $Adb -s $Device shell am start -W -n "$package/.MainActivity"
    if ($LASTEXITCODE -ne 0) { throw "Launch $attempt failed" }
    Start-Sleep -Seconds 5
    & $Adb -s $Device shell uiautomator dump /sdcard/egg-pilot-startup.xml
    $dump = Join-Path $OutputDirectory "startup-$attempt.xml"
    & $Adb -s $Device pull /sdcard/egg-pilot-startup.xml $dump
    if ($LASTEXITCODE -ne 0) { throw 'UI dump failed' }
    $ui = Get-Content -Raw -LiteralPath $dump
    if ($ui -notmatch 'GRID \+ HEIGHT PILOT' -or $ui -notmatch 'THREE-PHOTO SCAN') {
        throw "Home screen not ready on launch $attempt"
    }
    $appProcess = (& $Adb -s $Device shell pidof $package).Trim()
    if ($appProcess -notmatch '^\d+$') { throw 'App process is not running' }
    $crashes = & $Adb -s $Device logcat -b crash -d
    $crashes | Out-File -LiteralPath (Join-Path $OutputDirectory "crashes-$attempt.log") -Encoding utf8
    if (($crashes -join "`n") -match "Process: $([regex]::Escape($package)), PID: $appProcess\b") {
        throw "App crash recorded for launch $attempt"
    }
    Write-Output "PASS: home ready, process $appProcess alive, launch $attempt/3"
}
