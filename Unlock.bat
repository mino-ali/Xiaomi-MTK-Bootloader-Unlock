@echo off
setlocal
cd /d "%~dp0bin"
set "PATH=%~dp0bin;%PATH%"

net session >nul 2>&1
if %ERRORLEVEL% NEQ 0 (
    echo Please right-click Unlock.bat and select "Run as administrator".
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
set "DA_FILE=MTK_AllInOne_DA.bin"
if not exist "%DA_FILE%" if exist "DA.bin" set "DA_FILE=DA.bin"
if not exist "%DA_FILE%" (
    echo.
    echo [!] Error: MTK_AllInOne_DA.bin is missing from the bin folder!
    echo [!] Please extract MTK_AllInOne_DA.bin from the root of your stock Fastboot ROM
    echo [!] and place it directly inside the "bin" folder.
    pause
    exit /b 1
)

set "PL_FILE=preloader_ruby.bin"
if not exist "%PL_FILE%" if exist "preloader.bin" set "PL_FILE=preloader.bin"
if not exist "%PL_FILE%" if exist "preloader_raw.bin" set "PL_FILE=preloader_raw.bin"
if not exist "%PL_FILE%" (
    echo.
    echo [!] Error: preloader_ruby.bin is missing from the bin folder!
    echo [!] Please extract preloader_ruby.bin from the "images" folder of your
    echo [!] stock Fastboot ROM and place it directly inside the "bin" folder.
    pause
    exit /b 1
)

echo.
echo Checking and installing required Python dependencies...
python -m pip install cryptography git+https://github.com/R0rt1z2/liblk
if %ERRORLEVEL% NEQ 0 (
    echo.
    echo An error occurred while installing dependencies. Please check the output above.
    pause
    exit /b
)

if exist private.pem del /f /q private.pem
if exist public.pem del /f /q public.pem
if exist signature.bin del /f /q signature.bin
if exist lk_patched.img del /f /q lk_patched.img
echo.
echo Installing libusbK driver for BROM bypass...
pnputil /add-driver "%~dp0usb_driver\*.inf" /install >nul 2>&1
echo Driver installation finished.

echo.
echo [1/3] Reading preloader...
echo Please power off the device completely, then connect the USB cable and hold (Volume up + Volume down + Power)
antumbra r preloader %PL_FILE% --da %DA_FILE% -p %PL_FILE%

echo.
echo [2/3] Reading lk_a...
echo If the device rebooted, please power it off again, then reconnect.
antumbra r lk_a lk_a.img --da %DA_FILE% -p %PL_FILE%

echo.
echo [3/3] Reading lk_b...
echo If the device rebooted, please power it off again, then reconnect.
antumbra r lk_b lk_b.img --da %DA_FILE% -p %PL_FILE%

echo.
echo Patching lk...
python lk-unlock.py patch lk_a.img -o lk_patched.img
if %ERRORLEVEL% NEQ 0 (
    echo.
    echo [!] Error during patching LK.
    echo [!] If "Xiaomi's public key modulus not found", the image is likely already patched.
    echo [!] Run Restore.bat then try again.
    pause
    exit /b 1
)

echo.
if not exist "backup" mkdir "backup"
del /q /f "backup\lk_a.img" "backup\lk_b.img" >nul 2>&1
copy /y lk_a.img "backup\lk_a.img" >nul
copy /y lk_b.img "backup\lk_b.img" >nul

echo.
echo [1/2] Flashing lk_a...
echo If the device rebooted, please power it off again, then reconnect.
antumbra w lk_a lk_patched.img --da %DA_FILE% -p %PL_FILE%

echo.
echo [2/2] Flashing lk_b...
echo If the device rebooted, please power it off again, then reconnect.
antumbra w lk_b lk_patched.img --da %DA_FILE% -p %PL_FILE%

echo.
echo Uninstalling libusbK...
powershell -NoProfile -Command "$inf = (Get-ChildItem -Path '%~dp0usb_driver\*.inf').Name; if ($inf) { Get-WindowsDriver -Online | Where-Object { $_.OriginalFileName -match $inf } | ForEach-Object { & pnputil /delete-driver $_.Driver /uninstall } }"

for /f "tokens=*" %%i in ('powershell -NoProfile -Command "Get-PnpDevice -PresentOnly -ErrorAction SilentlyContinue | Where-Object { $_.InstanceId -match 'USB\\\\VID_0E8D&PID_0003' } | Select-Object -ExpandProperty InstanceId"') do (
    pnputil /remove-device "%%i" >nul 2>&1
)

pnputil /scan-devices >nul 2>&1
echo Driver restore complete.
echo.
echo.
echo =================================================================
echo                 [!] ACTION REQUIRED [!]
echo =================================================================
echo  1. Disconnect the USB cable from the PC.
echo  2. Wait 10s with the cable disconnected."
echo  3. Power on into Fastboot mode:
echo     -^> Press and hold (Volume Down + Power) until fastboot shows.
echo  4. Reconnect the USB cable.
echo =================================================================
echo.

echo Waiting for fastboot device...
fastboot wait-for-device

echo.
echo Device detected! Starting unlock...
python lk-unlock.py unlock
if %ERRORLEVEL% NEQ 0 (
    echo.
    echo Error during fastboot unlock. Please check the output above.
    pause
    exit /b
)

echo.
echo Unlock success!
pause
exit /b 0
