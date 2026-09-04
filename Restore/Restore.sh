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
if [ ! -f "backup/lk_a.img" ]; then
    echo ""
    echo "[!] Error: No backup found in bin/backup/ directory!"
    echo "[!] Cannot restore because backup/lk_a.img is missing."
    read -p "Press Enter to exit..."
    exit 1
fi
if [ ! -f "backup/lk_b.img" ]; then
    echo ""
    echo "[!] Error: No backup found in bin/backup/ directory!"
    echo "[!] Cannot restore because backup/lk_b.img is missing."
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

echo ""
echo "[1/2] Flashing lk_a..."
echo "Please power off the device completely, then connect the USB cable and hold (Volume up + Volume down + Power)"
flash_retry "lk_a" ./antumbra w lk_a backup/lk_a.img --da "$DA_FILE" -p "$PL_FILE"

echo ""
echo "[2/2] Flashing lk_b..."
echo "If the device rebooted, please power it off again, then reconnect."
flash_retry "lk_b" ./antumbra w lk_b backup/lk_b.img --da "$DA_FILE" -p "$PL_FILE"

read -p "Press Enter to exit..."
exit 0
