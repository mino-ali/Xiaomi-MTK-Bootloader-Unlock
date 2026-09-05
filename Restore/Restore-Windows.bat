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
echo Checking MediaTek VCOM drivers...
if not exist "%TEMP%\mtk_vcom_backup" mkdir "%TEMP%\mtk_vcom_backup"
powershell -NoProfile -ExecutionPolicy Bypass -Command "$vcom = Get-WindowsDriver -Online | Where-Object { $_.OriginalFileName -like '*cdc-acm*' -or ($_.ProviderName -like '*MediaTek*' -and $_.ClassName -eq 'Ports') }; if ($vcom) { $vcom | ForEach-Object { pnputil /export-driver $_.Driver '%TEMP%\mtk_vcom_backup' ; pnputil /delete-driver $_.Driver /uninstall /force } }" >nul 2>&1

echo Registering WinUSB driver for BROM bypass...
for /f "tokens=*" %%i in ('powershell -NoProfile -ExecutionPolicy Bypass -Command "Get-PnpDevice -PresentOnly -ErrorAction SilentlyContinue | Where-Object { $_.InstanceId -match 'USB\\\\VID_0E8D&PID_0003' } | Select-Object -ExpandProperty InstanceId"') do (
    pnputil /remove-device "%%i" >nul 2>&1
)
wdi-simple.exe -n "MediaTek USB Port" -m "MediaTek Inc." -v 0x0E8D -p 0x0003 -t 0 --silent
echo Driver registration complete.

echo.
echo [1/2] Flashing lk_a...
echo Please power off the device completely, then connect the USB cable and hold (Volume up + Volume down + Power)
antumbra -c w lk_a backup/lk_a.img --da %DA_FILE% -p %PL_FILE%

echo.
echo [2/2] Flashing lk_b...
echo If the device rebooted, please power it off again, then reconnect.
antumbra -c w lk_b backup/lk_b.img --da %DA_FILE% -p %PL_FILE%

echo.
echo Cleaning up temporary BROM driver assignment...
for /f "tokens=*" %%i in ('powershell -NoProfile -ExecutionPolicy Bypass -Command "Get-PnpDevice -PresentOnly -ErrorAction SilentlyContinue | Where-Object { $_.InstanceId -match 'USB\\\\VID_0E8D&PID_0003' } | Select-Object -ExpandProperty InstanceId"') do (
    pnputil /remove-device "%%i" >nul 2>&1
)

if exist "%TEMP%\mtk_vcom_backup\*.inf" (
    echo Restoring original MediaTek VCOM driver...
    pnputil /add-driver "%TEMP%\mtk_vcom_backup\*.inf" /install >nul 2>&1
    rmdir /s /q "%TEMP%\mtk_vcom_backup" >nul 2>&1
)

pnputil /scan-devices >nul 2>&1
echo Driver cleanup complete.

echo Done...
pause
exit /b 0
