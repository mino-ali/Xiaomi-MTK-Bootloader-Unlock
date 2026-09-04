#!/usr/bin/env bash

cd "$(dirname "$0")/bin" || exit

if [ -f "./antumbra" ]; then
    chmod +x ./antumbra
fi

echo "WARNING: This process will wipe your data. It is recommended to take a backup of any important partitions."
read -p "Continue? (Y/N): " CONTINUE
if [[ "${CONTINUE,,}" != "y" ]]; then
    echo "Operation cancelled by user."
    read -p "Press Enter to exit..."
    exit 1
fi

echo ""
echo "Checking for Python..."
if ! command -v python3 &> /dev/null; then
    echo "Error: Python 3 not found. Please install Python 3 then try again."
    read -p "Press Enter to exit..."
    exit 1
fi

echo ""
echo "Checking for Fastboot..."
if ! command -v fastboot &> /dev/null; then
    echo "Error: fastboot command not found. Please install android-tools or fastboot via your package manager."
    read -p "Press Enter to exit..."
    exit 1
fi
echo ""
echo "Checking for required vendor binaries..."
DA_FILE="MTK_AllInOne_DA.bin"
[ ! -f "$DA_FILE" ] && [ -f "DA.bin" ] && DA_FILE="DA.bin"
if [ ! -f "$DA_FILE" ]; then
    echo ""
    echo "[!] Error: MTK_AllInOne_DA.bin is missing from the bin directory!"
    echo "[!] Please extract MTK_AllInOne_DA.bin from your stock Fastboot ROM"
    echo "[!] and place it inside the bin/ directory."
    read -p "Press Enter to exit..."
    exit 1
fi

PL_FILE="preloader_ruby.bin"
[ ! -f "$PL_FILE" ] && [ -f "preloader.bin" ] && PL_FILE="preloader.bin"
[ ! -f "$PL_FILE" ] && [ -f "preloader_raw.bin" ] && PL_FILE="preloader_raw.bin"
if [ ! -f "$PL_FILE" ]; then
    echo ""
    echo "[!] Error: preloader_ruby.bin is missing from the bin directory!"
    echo "[!] Please extract preloader_ruby.bin from your stock ROM images/ folder"
    echo "[!] and place it inside the bin/ directory."
    read -p "Press Enter to exit..."
    exit 1
fi
echo ""
echo "Checking and installing required Python dependencies..."
python3 -m pip install cryptography git+https://github.com/R0rt1z2/liblk --break-system-packages
if [ $? -ne 0 ]; then
    echo ""
    echo "An error occurred while installing dependencies. Please check the output above."
    read -p "Press Enter to exit..."
    exit 1
fi

MM_STOPPED=0
if command -v systemctl &> /dev/null && systemctl is-active --quiet ModemManager 2>/dev/null; then
    echo ""
    echo "ModemManager is active and can interfere with MTK USB flashing. Stopping it for this session..."
    if sudo systemctl stop ModemManager 2>/dev/null; then
        MM_STOPPED=1
    else
        echo "Could not stop ModemManager automatically. If flashing fails with timeouts, run:"
        echo "    sudo systemctl stop ModemManager"
        echo "and re-run this script."
    fi
fi
restore_modemmanager() {
    if [ "$MM_STOPPED" = "1" ]; then
        echo "Restarting ModemManager..."
        sudo systemctl start ModemManager 2>/dev/null
    fi
}
trap restore_modemmanager EXIT

flash_retry() {
    local desc="$1"; shift
    local max_attempts=10
    local attempt
    for attempt in $(seq 1 "$max_attempts"); do
        if [ "$attempt" -gt 1 ]; then
            echo "  Retrying $desc (attempt $attempt/$max_attempts)..."
        fi
        if "$@"; then
            return 0
        fi
        sleep 1
    done
    echo ""
    echo "Error flashing $desc after $max_attempts attempts. Please check the output above."
    echo "Note: If you get a 'Permission denied' or USB error, try running this script with sudo."
    read -p "Press Enter to exit..."
    exit 1
}

read_retry() {
    local desc="$1"; shift
    local max_attempts=10
    local attempt
    for attempt in $(seq 1 "$max_attempts"); do
        if [ "$attempt" -gt 1 ]; then
            echo "  Retrying $desc (attempt $attempt/$max_attempts)..."
        fi
        if "$@"; then
            return 0
        fi
        sleep 1
    done
    echo ""
    echo "Error reading $desc after $max_attempts attempts. Please check the output above."
    echo "Note: If you get a 'Permission denied' or USB error, try running this script with sudo."
    read -p "Press Enter to exit..."
    exit 1
}

rm -f private.pem public.pem signature.bin lk_patched.img

echo ""
echo "[1/3] Reading preloader..."
echo "Please power off the device completely, then connect the USB cable and hold (Volume up + Volume down + Power)"
read_retry "preloader" ./antumbra r preloader "$PL_FILE" --da "$DA_FILE" -p "$PL_FILE"

echo ""
echo "[2/3] Reading lk_a..."
echo "If the device rebooted, please power it off again, then reconnect."
read_retry "lk_a" ./antumbra r lk_a lk_a.img --da "$DA_FILE" -p "$PL_FILE"

echo ""
echo "[3/3] Reading lk_b..."
echo "If the device rebooted, please power it off again, then reconnect."
read_retry "lk_b" ./antumbra r lk_b lk_b.img --da "$DA_FILE" -p "$PL_FILE"

if [ -f "backup/lk_a.img" ]; then
    echo "Backup already exists, skipping."
else
    echo "Creating backup..."
    mkdir -p backup
    cp lk_a.img backup/lk_a.img
    cp lk_b.img backup/lk_b.img
fi

echo "Patching lk..."
python3 lk-unlock.py patch lk_a.img -o lk_patched.img
if [ $? -ne 0 ]; then
    echo ""
    echo "[!] Error during patching LK."
    echo "[!] If 'Xiaomi's public key modulus not found', the image is likely already patched."
    echo "[!] Run Restore.sh then try again."
    read -p "Press Enter to exit..."
    exit 1
fi

echo ""
mkdir -p backup
rm -f backup/lk_a.img backup/lk_b.img
cp lk_a.img backup/lk_a.img
cp lk_b.img backup/lk_b.img

echo ""
echo "[1/2] Flashing lk_a..."
echo "If the device rebooted, please power it off again, then reconnect."
flash_retry "lk_a" ./antumbra w lk_a lk_patched.img --da "$DA_FILE" -p "$PL_FILE"

echo ""
echo "[2/2] Flashing lk_b..."
echo "If the device rebooted, please power it off again, then reconnect."
flash_retry "lk_b" ./antumbra w lk_b lk_patched.img --da "$DA_FILE" -p "$PL_FILE"

echo ""
echo ""
echo "================================================================="
echo "                [!] ACTION REQUIRED [!]"
echo "================================================================="
echo " 1. Disconnect the USB cable from the PC."
echo " 2. Wait 10s with the cable disconnected."
echo " 3. Power on into Fastboot mode:"
echo "    -> Press and hold (Volume Down + Power) until fastboot shows."
echo " 4. Reconnect the USB cable."
echo "================================================================="
echo ""
echo "Waiting for fastboot device..."

fastboot wait-for-device

echo ""
python3 lk-unlock.py unlock
if [ $? -ne 0 ]; then
    echo ""
    echo "Error during fastboot unlock. Please check the output above."
    read -p "Press Enter to exit..."
    exit 1
fi

echo ""
echo "Unlock success!"
read -p "Press Enter to exit..."
