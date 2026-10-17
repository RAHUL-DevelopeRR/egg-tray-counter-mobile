@echo off
:: =======================================================
:: Automatic Elevation Check
:: =======================================================
net session >nul 2>&1
if %errorlevel% neq 0 (
    echo Elevating privileges to Administrator...
    powershell -NoProfile -ExecutionPolicy Bypass -Command "Start-Process cmd -ArgumentList '/c `\"%~f0`\"' -Verb RunAs"
    exit /b
)

title USB Hub Fix Tool
color 0A
cls
echo ========================================================
echo          FIXING USB HUB / CONTROLLER ERROR 43
echo ========================================================
echo.

echo [1/6] Disabling Windows Fast Startup (prevents cached USB freezes)...
reg add "HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\Power" /v HiberbootEnabled /t REG_DWORD /d 0 /f >nul

echo [2/6] Disabling USB Selective Suspend...
powercfg /SETACVALUEINDEX SCHEME_CURRENT 2a737441-1930-4402-8d77-b2bebba308a3 48e6b7a6-50f5-4782-a5d4-53bb8f07e226 0
powercfg /SETDCVALUEINDEX SCHEME_CURRENT 2a737441-1930-4402-8d77-b2bebba308a3 48e6b7a6-50f5-4782-a5d4-53bb8f07e226 0
powercfg /SETACTIVE SCHEME_CURRENT

echo [3/6] Removing glitched USB device nodes from ports...
pnputil /remove-device "USB\VID_0000&PID_0002\5&225FCA56&0&1" >nul 2>&1
pnputil /remove-device "USB\VID_0000&PID_0002\5&225FCA56&0&2" >nul 2>&1
pnputil /remove-device /deviceid "USB\DEVICE_DESCRIPTOR_FAILURE" >nul 2>&1

echo [4/6] Restarting USB Root Hub 3.0...
pnputil /restart-device "USB\ROOT_HUB30\4&3B55E75&0&0"

timeout /t 2 /nobreak >nul

echo [5/6] Restarting Intel USB 3.0 eXtensible Host Controller...
pnputil /restart-device "PCI\VEN_8086&DEV_9D2F&SUBSYS_08391028&REV_21\3&11583659&0&A0"

timeout /t 3 /nobreak >nul

echo [6/6] Triggering Full Hardware Bus Rescan...
pnputil /scan-devices

echo.
echo ========================================================
echo                   USB RE-ENUMERATION COMPLETE
echo ========================================================
echo.
echo If the hub is plugged in, it should now initialize cleanly.
echo.
pause
