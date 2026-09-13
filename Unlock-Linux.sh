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
python3 -m pip install -q cryptography git+https://github.com/R0rt1z2/liblk --break-system-packages > /dev/null 2>&1 || python3 -m pip install -q cryptography git+https://github.com/R0rt1z2/liblk > /dev/null 2>&1
if [ $? -ne 0 ]; then
    echo "[!] Warning: Failed to install Python dependencies. Continuing in offline mode..."
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
    local max_attempts=5
    local attempt
    for ((attempt = 1; attempt <= max_attempts; attempt++)); do
        if [ "$attempt" -eq 1 ]; then
            echo "  [Attempt 1/$max_attempts] Connecting to $desc..."
        else
            echo "  [Attempt $attempt/$max_attempts] Retrying $desc..."
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
    local max_attempts=5
    local attempt
    for ((attempt = 1; attempt <= max_attempts; attempt++)); do
        if [ "$attempt" -eq 1 ]; then
            echo "  [Attempt 1/$max_attempts] Connecting to $desc..."
        else
            echo "  [Attempt $attempt/$max_attempts] Retrying $desc..."
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

if [ "$PL_FILE" = "preloader_ruby.bin" ] && [ -f "preloader_ruby.bin" ]; then
    PL_SIZE=$(stat -c%s "preloader_ruby.bin" 2>/dev/null || stat -f%z "preloader_ruby.bin" 2>/dev/null || echo 0)
    if [ "$PL_SIZE" -gt 0 ] && [ "$PL_SIZE" -lt 2097152 ] 2>/dev/null; then
        mkdir -p backup >/dev/null 2>&1
        cp -f "preloader_ruby.bin" "backup/preloader_ruby.bin" >/dev/null 2>&1
    fi
fi

echo ""
echo "[1/3] Reading preloader..."
echo "Please power off the device completely, then connect the USB cable and hold (Volume up + Volume down + Power)"
read_retry "preloader" ./antumbra -c r preloader "$PL_FILE" --da "$DA_FILE" -p "$PL_FILE"
echo ""
echo "[2/3] Reading lk_a..."
echo "If the device rebooted, please power it off again, then reconnect."
read_retry "lk_a" ./antumbra -c r lk_a lk_a.img --da "$DA_FILE" -p "$PL_FILE"

echo ""
echo "[3/3] Reading lk_b..."
echo "If the device rebooted, please power it off again, then reconnect."
read_retry "lk_b" ./antumbra -c r lk_b lk_b.img --da "$DA_FILE" -p "$PL_FILE"

echo "Patching lk..."
PATCH_OUTPUT=$(python3 lk-unlock.py patch lk_a.img -o lk_patched.img 2>&1)
PATCH_EXIT=$?
echo "$PATCH_OUTPUT"

if echo "$PATCH_OUTPUT" | grep -qi "Skipping cert bypass"; then
    echo ""
    echo "[*] Notice: Bootloader is spoofed as locked!"

    SPOOF_RESTORE_LK_A=""
    SPOOF_RESTORE_LK_B=""

    if [ -f "backup/lk_a.img" ] && [ -f "backup/lk_b.img" ]; then
        SPOOF_RESTORE_LK_A="backup/lk_a.img"
        SPOOF_RESTORE_LK_B="backup/lk_b.img"
    elif [ -f "backup/lk.img" ]; then
        SPOOF_RESTORE_LK_A="backup/lk.img"
        SPOOF_RESTORE_LK_B="backup/lk.img"
    fi

    BACKUP_PL=""
    if [ -f "backup/preloader_ruby.bin" ]; then
        BACKUP_PL="backup/preloader_ruby.bin"
    fi

    if [ -z "$SPOOF_RESTORE_LK_A" ]; then
        echo ""
        echo "[!] Error: No stock LK backup was found to restore from!"
        echo "[!] To fix this, extract lk.img (or lk_a.img/lk_b.img) and preloader_ruby.bin"
        echo "[!] from your official stock Fastboot ROM and copy them into the bin/backup/ directory."
        echo "[!] Then run Restore-Linux.sh (in the Restore directory) to restore stock firmware first."
        read -p "Press Enter to exit..."
        exit 1
    fi

    if [ -z "$BACKUP_PL" ]; then
        echo ""
        echo "[!] Error: No stock preloader backup found in the backup directory!"
        echo "[!] Cannot safely restore from a spoofed bootloader without stock preloader."
        echo "[!] Please copy preloader_ruby.bin into the bin/backup/ directory, then try again."
        read -p "Press Enter to exit..."
        exit 1
    fi

    echo "[*] Stock backups found. Restoring device to stock firmware..."
    echo ""
    echo "[1/4] Flashing preloader..."
    echo "Please power off the device completely, then connect the USB cable and hold (Volume up + Volume down + Power)"
    flash_retry "preloader" ./antumbra -c w preloader "$BACKUP_PL" --da "$DA_FILE" -p "$PL_FILE"

    echo ""
    echo "[2/4] Flashing preloader_backup..."
    echo "If the device rebooted, please power it off again, then reconnect."
    flash_retry "preloader_backup" ./antumbra -c w preloader_backup "$BACKUP_PL" --da "$DA_FILE" -p "$PL_FILE"

    echo ""
    echo "[3/4] Flashing lk_a..."
    echo "If the device rebooted, please power it off again, then reconnect."
    flash_retry "lk_a" ./antumbra -c w lk_a "$SPOOF_RESTORE_LK_A" --da "$DA_FILE" -p "$PL_FILE"

    echo ""
    echo "[4/4] Flashing lk_b..."
    echo "If the device rebooted, please power it off again, then reconnect."
    flash_retry "lk_b" ./antumbra -c w lk_b "$SPOOF_RESTORE_LK_B" --da "$DA_FILE" -p "$PL_FILE"

    echo ""
    echo "Formatting para partition..."
    echo "If the device rebooted, please power it off again, then reconnect."
    flash_retry "para format" ./antumbra -c ft para --da "$DA_FILE" -p "$PL_FILE"

    echo ""
    echo "[*] Device successfully restored to stock!"
    echo "[*] Please run Unlock-Linux.sh again to unlock your clean stock bootloader."
    read -p "Press Enter to exit..."
    exit 0
fi

if [ $PATCH_EXIT -ne 0 ]; then
    if echo "$PATCH_OUTPUT" | grep -qi "public key modulus not found"; then
        echo ""
        echo "[*] Notice: The LK image on your device is already patched."

        STOCK_LK_SOURCE=""
        if [ -f "backup/lk_a.img" ]; then
            STOCK_LK_SOURCE="backup/lk_a.img"
        elif [ -f "backup/lk.img" ]; then
            STOCK_LK_SOURCE="backup/lk.img"
        fi

        if [ -z "$STOCK_LK_SOURCE" ]; then
            echo ""
            echo "[!] Error: No stock backup was found in the backup directory!"
            echo "[!] Cannot re-patch without a clean stock backup."
            echo "[!] Please place your stock lk.img (or lk_a.img) into the backup directory, or restore stock firmware, then try again."
            read -p "Press Enter to exit..."
            exit 1
        fi
        echo "[*] Found stock backup in backup directory. Using it to re-patch and synchronize keys..."
        cp "$STOCK_LK_SOURCE" lk_a.img
        python3 lk-unlock.py patch lk_a.img -o lk_patched.img
        if [ $? -ne 0 ]; then
            echo ""
            echo "[!] Error during re-patching backup LK."
            read -p "Press Enter to exit..."
            exit 1
        fi
    else
        echo ""
        echo "[!] Error during patching LK."
        read -p "Press Enter to exit..."
        exit 1
    fi
else
    mkdir -p backup
    if [ ! -f "backup/lk_a.img" ]; then
        cp lk_a.img backup/lk_a.img
        cp lk_b.img backup/lk_b.img
    fi
fi

echo ""
echo "[1/2] Flashing lk_a..."
echo "If the device rebooted, please power it off again, then reconnect."
flash_retry "lk_a" ./antumbra -c w lk_a lk_patched.img --da "$DA_FILE" -p "$PL_FILE"

echo ""
echo "[2/2] Flashing lk_b..."
echo "If the device rebooted, please power it off again, then reconnect."
flash_retry "lk_b" ./antumbra -c w lk_b lk_patched.img --da "$DA_FILE" -p "$PL_FILE"
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
echo ""
echo " Unable to reboot? Run the restore script and try again!"
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
