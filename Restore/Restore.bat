@echo off
setlocal

cd /d "%~dp0..\bin"
set "PATH=%~dp0..\bin;%PATH%"

net session >nul 2>&1
if %ERRORLEVEL% NEQ 0 (
    echo Please right-click Restore.bat and select "Run as administrator".
    pause
    exit /b
)

if not exist "backup\lk_a.img" (
    echo.
    echo [!] Error: No backup found in bin\backup folder!
    echo [!] Cannot restore because backup\lk_a.img is missing.
    pause
    exit /b 1
)
if not exist "backup\lk_b.img" (
    echo.
    echo [!] Error: No backup found in bin\backup folder!
    echo [!] Cannot restore because backup\lk_b.img is missing.
    pause
    exit /b 1
)

set "DA_FILE=MTK_AllInOne_DA.bin"
if not exist "%DA_FILE%" if exist "DA.bin" set "DA_FILE=DA.bin"
if not exist "%DA_FILE%" (
    echo.
    echo [!] Error: MTK_AllInOne_DA.bin is missing from the bin folder!
    pause
    exit /b 1
)

set "PL_FILE=preloader_ruby.bin"
if not exist "%PL_FILE%" if exist "preloader.bin" set "PL_FILE=preloader.bin"
if not exist "%PL_FILE%" if exist "preloader_raw.bin" set "PL_FILE=preloader_raw.bin"
if not exist "%PL_FILE%" (
    echo.
    echo [!] Error: preloader_ruby.bin is missing from the bin folder!
    pause
    exit /b 1
)

echo.
echo Installing libusbK driver for BROM bypass...
pnputil /add-driver "%~dp0..\usb_driver\*.inf" /install >nul 2>&1
echo Driver installation finished.

echo.
echo [1/2] Flashing lk_a...
echo If the device rebooted, please power it off again, then reconnect.
antumbra w lk_a backup/lk_a.img --da %DA_FILE% -p %PL_FILE%

echo.
echo [2/2] Flashing lk_b...
echo If the device rebooted, please power it off again, then reconnect.
antumbra w lk_b backup/lk_b.img --da %DA_FILE% -p %PL_FILE%
echo.
echo Uninstalling libusbK...
powershell -NoProfile -Command "$inf = (Get-ChildItem -Path '%~dp0..\usb_driver\*.inf').Name; if ($inf) { Get-WindowsDriver -Online | Where-Object { $_.OriginalFileName -match $inf } | ForEach-Object { & pnputil /delete-driver $_.Driver /uninstall } }"

for /f "tokens=*" %%i in ('powershell -NoProfile -Command "Get-PnpDevice -PresentOnly -ErrorAction SilentlyContinue | Where-Object { $_.InstanceId -match 'USB\\\\VID_0E8D&PID_0003' } | Select-Object -ExpandProperty InstanceId"') do (
    pnputil /remove-device "%%i" >nul 2>&1
)

pnputil /scan-devices >nul 2>&1
echo Driver restore complete.

echo Done...
pause
exit /b 0
