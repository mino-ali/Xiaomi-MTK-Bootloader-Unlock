@echo off
setlocal
set "PYTHONUTF8=1"
cd /d "%~dp0bin"
set "PATH=%~dp0bin;%PATH%"
net session >nul 2>&1
if %ERRORLEVEL% NEQ 0 (
    echo Please right-click Unlock-Windows.bat and select "Run as administrator".
    pause
    exit /b
)

echo WARNING: This process will wipe your data. It is recommended to take a backup of any important partitions.
set /p CONTINUE="Continue? (Y/N): "
if /i "%CONTINUE%" NEQ "Y" (
    echo Operation cancelled by user.
    pause
    exit /b
)

echo.
echo Select cert bypass mode:
echo   1. override (default)
echo   2. wrap
set "WRAP_CHOICE="
set /p WRAP_CHOICE="Choice [1]: "
set "USE_WRAP="
if "%WRAP_CHOICE%"=="2" set "USE_WRAP=--wrap"

echo.
echo Checking for Python...
python --version >nul 2>&1
if %ERRORLEVEL% NEQ 0 (
    echo Error: Python not found. Please install Python and ensure it is in your PATH.
    pause
    exit /b
)

echo.
echo Checking for Fastboot...
fastboot --version >nul 2>&1
if %ERRORLEVEL% NEQ 0 (
    echo Error: fastboot not found. Please install ADB/Fastboot drivers and ensure they are in your PATH.
    pause
    exit /b
)
echo.
echo Checking for required vendor binaries...
set "DA_FILE="
if exist "MTK_AllInOne_DA.bin" set "DA_FILE=MTK_AllInOne_DA.bin"
if not defined DA_FILE for %%F in (MTK_AllInOne_DA*.bin *AllInOne_DA*.bin DA_v6*.bin DA_V6*.bin da_v6*.bin MTK_DA*.bin mtk_da*.bin DA_BR*.bin DA_PL*.bin) do (
    if not defined DA_FILE if exist "%%F" set "DA_FILE=%%F"
)
if not defined DA_FILE if exist "DA.bin" set "DA_FILE=DA.bin"
if not defined DA_FILE if exist "da.bin" set "DA_FILE=da.bin"
if not defined DA_FILE for %%F in (DA_*.bin) do (
    if not defined DA_FILE if exist "%%F" (
        echo %%~nF | findstr /i /b "data metadata userdata" >nul
        if errorlevel 1 set "DA_FILE=%%F"
    )
)

if not defined DA_FILE (
    echo.
    echo [!] Error: Download Agent file is missing from the bin folder!
    echo [!] Please place your DA file inside the "bin" folder.
    pause
    exit /b 1
)

set "PL_FILE="
for %%F in (preloader_*.bin) do (
    if not defined PL_FILE if exist "%%F" set "PL_FILE=%%F"
)
if not defined PL_FILE if exist "preloader.bin" set "PL_FILE=preloader.bin"
if not defined PL_FILE if exist "preloader_raw.img" set "PL_FILE=preloader_raw.img"
if not defined PL_FILE if exist "preloader_raw.bin" set "PL_FILE=preloader_raw.bin"

if not defined PL_FILE (
    echo.
    echo [!] Error: Preloader file is missing from the bin folder!
    echo [!] Please place your preloader file inside the "bin" folder.
    pause
    exit /b 1
)

echo.
echo Checking and installing required Python dependencies...
python -m pip install -q cryptography git+https://github.com/R0rt1z2/liblk >nul 2>&1
if %ERRORLEVEL% NEQ 0 (
    echo Warning: installing cryptography and liblk failed if patching lk fails please run this manually
    echo "python -m pip install -q cryptography git+https://github.com/R0rt1z2/liblk"
)

if exist private.pem del /f /q private.pem
if exist public.pem del /f /q public.pem
if exist signature.bin del /f /q signature.bin
if exist lk_patched.img del /f /q lk_patched.img
if exist .antumbra_state del /f /q .antumbra_state >nul 2>&1
echo.
echo Checking for MediaTek VCOM drivers...
if not exist "%TEMP%\mtk_vcom_backup" mkdir "%TEMP%\mtk_vcom_backup"
powershell -NoProfile -ExecutionPolicy Bypass -Command "$vcom = Get-WindowsDriver -Online | Where-Object { $_.OriginalFileName -like '*cdc-acm*' -or ($_.ProviderName -like '*MediaTek*' -and $_.ClassName -eq 'Ports') }; if ($vcom) { $vcom | ForEach-Object { pnputil /export-driver $_.Driver '%TEMP%\mtk_vcom_backup' ; pnputil /delete-driver $_.Driver /uninstall /force } }" >nul 2>&1

echo Registering WinUSB driver for BROM bypass...
for /f "tokens=*" %%i in ('powershell -NoProfile -ExecutionPolicy Bypass -Command "Get-PnpDevice -PresentOnly -ErrorAction SilentlyContinue | Where-Object { $_.InstanceId -match 'USB\\\\VID_0E8D&PID_0003' } | Select-Object -ExpandProperty InstanceId"') do (
    pnputil /remove-device "%%i" >nul 2>&1
)
wdi-simple.exe -n "MediaTek USB Port" -m "MediaTek Inc." -v 0x0E8D -p 0x0003 -t 0 --silent
echo Driver registration complete.
echo.
if defined PL_FILE if exist "%PL_FILE%" (
    if not exist "backup" mkdir "backup" >nul 2>&1
    for %%F in ("%PL_FILE%") do (
        if %%~zF LSS 2097152 (
            copy /y "%PL_FILE%" "backup\%PL_FILE%" >nul 2>&1
            copy /y "%PL_FILE%" "backup\preloader.bin" >nul 2>&1
        )
    )
)
echo Reading lk_a...
echo Please power off the device completely, then connect the USB cable and hold (Volume up + Volume down + Power)
call :read_retry "lk_a" "antumbra -c r lk_a lk_a.img --da %DA_FILE% -p %PL_FILE%"
if errorlevel 1 goto :error_exit
copy /y lk_a.img lk_b.img >nul 2>&1
echo.
echo Patching lk...
python lk-unlock.py patch lk_a.img -o lk_patched.img %USE_WRAP% > patch_log.tmp 2>&1
set "PATCH_ERR=%ERRORLEVEL%"
type patch_log.tmp

findstr /i /c:"Skipping cert bypass" patch_log.tmp >nul 2>&1
if not errorlevel 1 goto :spoofed_bootloader

if "%PATCH_ERR%"=="0" goto :patch_success

findstr /i /c:"modulus not found" patch_log.tmp >nul 2>&1
if not errorlevel 1 goto :already_patched

del /f /q patch_log.tmp >nul 2>&1
echo.
echo [!] Error during patching LK.
echo [!] Run Restore-Windows.bat [in the Restore folder] then try again.
goto :error_exit

:spoofed_bootloader
del /f /q patch_log.tmp >nul 2>&1
echo.
echo [*] Notice: Bootloader is spoofed as locked!

set "SPOOF_RESTORE_LK_A="
set "SPOOF_RESTORE_LK_B="

if exist "backup\lk_a.img" if exist "backup\lk_b.img" (
    set "SPOOF_RESTORE_LK_A=backup\lk_a.img"
    set "SPOOF_RESTORE_LK_B=backup\lk_b.img"
)

if not defined SPOOF_RESTORE_LK_A if exist "backup\lk.img" (
    set "SPOOF_RESTORE_LK_A=backup\lk.img"
    set "SPOOF_RESTORE_LK_B=backup\lk.img"
)

set "BACKUP_PL="
if defined PL_FILE if exist "backup\%PL_FILE%" set "BACKUP_PL=backup\%PL_FILE%"
if not defined BACKUP_PL if exist "backup\preloader.bin" set "BACKUP_PL=backup\preloader.bin"
if not defined BACKUP_PL (
    for %%F in (backup\preloader_*.bin backup\preloader_*.img) do (
        if not defined BACKUP_PL if exist "%%F" set "BACKUP_PL=%%F"
    )
)

if not defined SPOOF_RESTORE_LK_A (
    echo.
    echo [!] Error: No stock LK backup found to restore from!
    echo [!] Please copy your stock lk and preloader into bin\backup,
    echo [!] then run Restore-Windows.bat to restore stock firmware first.
    goto :error_exit
)

if not defined BACKUP_PL (
    echo.
    echo [!] Error: No stock preloader backup found in the backup folder!
    echo [!] Cannot safely restore without stock preloader.
    echo [!] Please copy your stock preloader into bin\backup and try again.
    goto :error_exit
)

echo [*] Stock backups found. Restoring device to stock firmware...
echo.
echo [1/4] Flashing preloader...
echo Please power off the device completely, then connect the USB cable and hold (Volume up + Volume down + Power)
call :flash_retry "preloader" "antumbra -c w preloader %BACKUP_PL% --da %DA_FILE% -p %PL_FILE%"
if errorlevel 1 goto :error_exit

echo.
echo [2/4] Flashing preloader_backup...
echo If the device rebooted, please power it off again, then reconnect.
call :flash_retry "preloader_backup" "antumbra -c w preloader_backup %BACKUP_PL% --da %DA_FILE% -p %PL_FILE%"
if errorlevel 1 goto :error_exit

echo.
echo [3/4] Flashing lk_a...
echo If the device rebooted, please power it off again, then reconnect.
call :flash_retry "lk_a" "antumbra -c w lk_a %SPOOF_RESTORE_LK_A% --da %DA_FILE% -p %PL_FILE%"
if errorlevel 1 goto :error_exit

echo.
echo [4/4] Flashing lk_b...
echo If the device rebooted, please power it off again, then reconnect.
call :flash_retry "lk_b" "antumbra -c w lk_b %SPOOF_RESTORE_LK_B% --da %DA_FILE% -p %PL_FILE%"
if errorlevel 1 goto :error_exit
echo.
echo Formatting para partition...
echo If the device rebooted, please power it off again, then reconnect.
call :flash_retry "para format" "antumbra -c ft para --da %DA_FILE% -p %PL_FILE%"
if errorlevel 1 goto :error_exit

call :cleanup_drivers

echo.
echo [*] Device successfully restored to stock!
echo [*] Please reboot then run Unlock-Windows.bat again to unlock your bootloader.
pause
exit /b 0

:already_patched
del /f /q patch_log.tmp >nul 2>&1
echo.
echo [*] Notice: The LK image on your device is already patched.

set "STOCK_LK_SOURCE="
if exist "backup\lk_a.img" set "STOCK_LK_SOURCE=backup\lk_a.img"
if not defined STOCK_LK_SOURCE if exist "backup\lk.img" set "STOCK_LK_SOURCE=backup\lk.img"

if not defined STOCK_LK_SOURCE (
    echo.
    echo [!] Error: No stock backup was found in the backup folder!
    echo [!] Cannot re-patch without a clean stock backup.
    echo [!] Please place your stock lk.img [or lk_a.img] into the backup folder or restore stock firmware, then try again.
    goto :error_exit
)

echo [*] Found stock backup in backup folder. Using it to re-patch and synchronize keys...
copy /y "%STOCK_LK_SOURCE%" lk_a.img >nul
python lk-unlock.py patch lk_a.img -o lk_patched.img %USE_WRAP%
if %ERRORLEVEL% NEQ 0 (
    echo.
    echo [!] Error during re-patching backup LK.
    goto :error_exit
)
goto :do_flash

:patch_success
del /f /q patch_log.tmp >nul 2>&1
echo.
if not exist "backup" mkdir "backup"
if not exist "backup\lk_a.img" (
    copy /y lk_a.img "backup\lk_a.img" >nul
    copy /y lk_b.img "backup\lk_b.img" >nul
)

:do_flash
echo.
echo [1/2] Flashing lk_a...
echo If the device rebooted, please power it off again, then reconnect.
call :flash_retry "lk_a" "antumbra -c w lk_a lk_patched.img --da %DA_FILE% -p %PL_FILE%"
if errorlevel 1 goto :error_exit

echo.
echo [2/2] Flashing lk_b...
echo If the device rebooted, please power it off again, then reconnect.
call :flash_retry "lk_b" "antumbra -c w lk_b lk_patched.img --da %DA_FILE% -p %PL_FILE%"
if errorlevel 1 goto :error_exit

call :cleanup_drivers
echo.
echo.
echo =================================================================
echo                 [!] ACTION REQUIRED [!]
echo =================================================================
echo  1. Disconnect the USB cable from the PC.
echo  2. Wait 10s with the cable disconnected.
echo  3. Power on into Fastboot mode:
echo     -^> Press and hold (Volume Down + Power) until fastboot shows.
echo  4. Reconnect the USB cable.
echo.
echo  Unable to reboot? Run Restore-Windows.bat and try again!
echo =================================================================
echo.

echo Waiting for fastboot device...
:wait_fastboot
for /f "tokens=1" %%d in ('fastboot devices 2^>nul') do (
    goto :fastboot_found
)
timeout /t 1 /nobreak >nul
goto :wait_fastboot
:fastboot_found

echo.
echo Device detected! Starting unlock...
python lk-unlock.py unlock
if %ERRORLEVEL% NEQ 0 (
    echo.
    echo Error during fastboot unlock. Please check the output above.
    pause
    exit /b 1
)

echo.
echo Unlock success!
pause
exit /b 0

:read_retry
set "RETRY_DESC=%~1"
set "RETRY_CMD=%~2"
set "ATTEMPT=1"
:read_retry_loop
if %ATTEMPT% EQU 1 (
    echo   [Attempt 1/5] Connecting to %RETRY_DESC%...
) else (
    echo   [Attempt %ATTEMPT%/5] Retrying %RETRY_DESC%...
)
if exist .antumbra_state del /f /q .antumbra_state >nul 2>&1
%RETRY_CMD%
if not errorlevel 1 exit /b 0

set /a ATTEMPT+=1
if %ATTEMPT% LEQ 5 (
    timeout /t 1 /nobreak >nul
    goto :read_retry_loop
)

echo.
echo Error reading %RETRY_DESC% after 5 attempts. Please check the output above.
(call)
exit /b 1

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
(call)
exit /b 1

:cleanup_drivers
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
exit /b 0

:error_exit
call :cleanup_drivers
pause
exit /b 1


