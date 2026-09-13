#!/usr/bin/env bash

BACKUP_DIR="$(cd "$(dirname "$0")" && pwd)"

cd "$BACKUP_DIR/../bin" || exit

if [ -f "./antumbra" ]; then
    chmod +x ./antumbra
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
LK_A_TARGET=""
LK_B_TARGET=""

if [ -f "backup/lk_a.img" ] && [ -f "backup/lk_b.img" ]; then
    LK_A_TARGET="backup/lk_a.img"
    LK_B_TARGET="backup/lk_b.img"
elif [ -f "backup/lk.img" ]; then
    LK_A_TARGET="backup/lk.img"
    LK_B_TARGET="backup/lk.img"
else
    echo ""
    echo "[!] Error: No valid LK backup found in bin/backup/ directory!"
    echo "[!] Cannot restore because backup is missing (need lk_a.img and lk_b.img, or lk.img)."
    read -p "Press Enter to exit..."
    exit 1
fi

DA_FILE="MTK_AllInOne_DA.bin"
[ ! -f "$DA_FILE" ] && [ -f "DA.bin" ] && DA_FILE="DA.bin"
if [ ! -f "$DA_FILE" ]; then
    echo ""
    echo "[!] Error: MTK_AllInOne_DA.bin is missing from the bin directory!"
    read -p "Press Enter to exit..."
    exit 1
fi

PL_FILE="preloader_ruby.bin"
[ ! -f "$PL_FILE" ] && [ -f "preloader.bin" ] && PL_FILE="preloader.bin"
[ ! -f "$PL_FILE" ] && [ -f "preloader_raw.bin" ] && PL_FILE="preloader_raw.bin"
if [ ! -f "$PL_FILE" ]; then
    echo ""
    echo "[!] Error: preloader_ruby.bin is missing from the bin directory!"
    read -p "Press Enter to exit..."
    exit 1
fi

BACKUP_PL=""
if [ -f "backup/preloader_ruby.bin" ]; then
    BACKUP_PL="backup/preloader_ruby.bin"
fi

if [ -n "$BACKUP_PL" ]; then
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
    flash_retry "lk_a" ./antumbra -c w lk_a "$LK_A_TARGET" --da "$DA_FILE" -p "$PL_FILE"

    echo ""
    echo "[4/4] Flashing lk_b..."
    echo "If the device rebooted, please power it off again, then reconnect."
    flash_retry "lk_b" ./antumbra -c w lk_b "$LK_B_TARGET" --da "$DA_FILE" -p "$PL_FILE"
else
    echo ""
    echo "[1/2] Flashing lk_a..."
    echo "Please power off the device completely, then connect the USB cable and hold (Volume up + Volume down + Power)"
    flash_retry "lk_a" ./antumbra -c w lk_a "$LK_A_TARGET" --da "$DA_FILE" -p "$PL_FILE"

    echo ""
    echo "[2/2] Flashing lk_b..."
    echo "If the device rebooted, please power it off again, then reconnect."
    flash_retry "lk_b" ./antumbra -c w lk_b "$LK_B_TARGET" --da "$DA_FILE" -p "$PL_FILE"
fi

echo ""
echo "Formatting para partition..."
echo "If the device rebooted, please power it off again, then reconnect."
flash_retry "para format" ./antumbra -c ft para --da "$DA_FILE" -p "$PL_FILE"
read -p "Press Enter to exit..."
exit 0
