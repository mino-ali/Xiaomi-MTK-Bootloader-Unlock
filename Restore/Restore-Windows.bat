@echo off
setlocal

cd /d "%~dp0..\bin"
set "PATH=%~dp0..\bin;%PATH%"

net session >nul 2>&1
if %ERRORLEVEL% NEQ 0 (
    echo Please right-click Restore-Windows.bat and select "Run as administrator".
    pause
    exit /b
)

set "LK_A_TARGET="
set "LK_B_TARGET="

if exist "backup\lk_a.img" if exist "backup\lk_b.img" (
    set "LK_A_TARGET=backup\lk_a.img"
    set "LK_B_TARGET=backup\lk_b.img"
)

if not defined LK_A_TARGET if exist "backup\lk.img" (
    set "LK_A_TARGET=backup\lk.img"
    set "LK_B_TARGET=backup\lk.img"
)

if not defined LK_A_TARGET (
    echo.
    echo [!] Error: No valid LK backup found in bin\backup folder!
    echo [!] Cannot restore because backup is missing [need lk_a.img and lk_b.img, or lk.img].
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

set "BACKUP_PL="
if exist "backup\preloader_ruby.bin" set "BACKUP_PL=backup\preloader_ruby.bin"

if exist .antumbra_state del /f /q .antumbra_state >nul 2>&1

if defined BACKUP_PL (
    echo.
    echo [1/4] Flashing preloader...
    echo Please power off the device completely, then connect the USB cable and hold (Volume up + Volume down + Power)
    call :flash_retry "preloader" "antumbra -c w preloader %BACKUP_PL% --da %DA_FILE% -p %PL_FILE%"
    if errorlevel 1 ( pause & exit /b 1 )

    echo.
    echo [2/4] Flashing preloader_backup...
    echo If the device rebooted, please power it off again, then reconnect.
    call :flash_retry "preloader_backup" "antumbra -c w preloader_backup %BACKUP_PL% --da %DA_FILE% -p %PL_FILE%"
    if errorlevel 1 ( pause & exit /b 1 )

    echo.
    echo [3/4] Flashing lk_a...
    echo If the device rebooted, please power it off again, then reconnect.
    call :flash_retry "lk_a" "antumbra -c w lk_a %LK_A_TARGET% --da %DA_FILE% -p %PL_FILE%"
    if errorlevel 1 ( pause & exit /b 1 )

    echo.
    echo [4/4] Flashing lk_b...
    echo If the device rebooted, please power it off again, then reconnect.
    call :flash_retry "lk_b" "antumbra -c w lk_b %LK_B_TARGET% --da %DA_FILE% -p %PL_FILE%"
    if errorlevel 1 ( pause & exit /b 1 )
) else (
    echo.
    echo [1/2] Flashing lk_a...
    echo Please power off the device completely, then connect the USB cable and hold (Volume up + Volume down + Power)
    call :flash_retry "lk_a" "antumbra -c w lk_a %LK_A_TARGET% --da %DA_FILE% -p %PL_FILE%"
    if errorlevel 1 ( pause & exit /b 1 )

    echo.
    echo [2/2] Flashing lk_b...
    echo If the device rebooted, please power it off again, then reconnect.
    call :flash_retry "lk_b" "antumbra -c w lk_b %LK_B_TARGET% --da %DA_FILE% -p %PL_FILE%"
    if errorlevel 1 ( pause & exit /b 1 )
)

echo.
echo Formatting para partition...
echo If the device rebooted, please power it off again, then reconnect.
call :flash_retry "para format" "antumbra -c ft para --da %DA_FILE% -p %PL_FILE%"
if errorlevel 1 ( pause & exit /b 1 )
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

:flash_retry
set "RETRY_DESC=%~1"
set "RETRY_CMD=%~2"
set "ATTEMPT=1"
:flash_retry_loop
if %ATTEMPT% EQU 1 (
    echo   [Attempt 1/5] Connecting to %RETRY_DESC%...
) else (
    echo   [Attempt %ATTEMPT%/5] Retrying %RETRY_DESC%...
    if exist .antumbra_state del /f /q .antumbra_state >nul 2>&1
)
%RETRY_CMD%
if not errorlevel 1 exit /b 0

set /a ATTEMPT+=1
if %ATTEMPT% LEQ 5 (
    timeout /t 1 /nobreak >nul
    goto :flash_retry_loop
)

echo.
echo Error flashing %RETRY_DESC% after 5 attempts. Please check the output above.
pause
exit /b 1
