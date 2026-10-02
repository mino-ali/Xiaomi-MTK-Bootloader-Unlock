#!/usr/bin/env bash
shopt -s nullglob

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
echo "Select cert bypass mode:"
echo "  1. override (default)"
echo "  2. wrap"
read -p "Choice [1]: " WRAP_CHOICE
USE_WRAP=""
if [ "$WRAP_CHOICE" = "2" ]; then
    USE_WRAP="--wrap"
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
DA_FILE=""
for pattern in "MTK_AllInOne_DA*.bin" "*AllInOne_DA*.bin" "DA_v6*.bin" "DA_V6*.bin" "da_v6*.bin" "MTK_DA*.bin" "mtk_da*.bin" "DA_BR*.bin" "DA_PL*.bin" "DA.bin" "da.bin" "DA_*.bin"; do
    for f in $pattern; do
        if [ -f "$f" ]; then
            lower_name="$(basename "$f" | tr '[:upper:]' '[:lower:]')"
            case "$lower_name" in
                data*.bin|userdata*.bin|metadata*.bin) continue ;;
            esac
            DA_FILE="$f"
            break 2
        fi
    done
done
if [ -z "$DA_FILE" ]; then
    echo ""
    echo "[!] Error: Download Agent file is missing from bin/!"
    echo "[!] Please place your DA file inside the bin/ directory."
    read -p "Press Enter to exit..."
    exit 1
fi

PL_FILE=""
for f in preloader_*.bin; do
    if [ -f "$f" ]; then
        PL_FILE="$f"
        break
    fi
done
if [ -z "$PL_FILE" ] && [ -f "preloader.bin" ]; then
    PL_FILE="preloader.bin"
fi
if [ -z "$PL_FILE" ] && [ -f "preloader_raw.img" ]; then
    PL_FILE="preloader_raw.img"
fi
if [ -z "$PL_FILE" ] && [ -f "preloader_raw.bin" ]; then
    PL_FILE="preloader_raw.bin"
fi
if [ -z "$PL_FILE" ]; then
    echo ""
    echo "[!] Error: Preloader file is missing from bin/!"
    echo "[!] Please place your preloader file inside the bin/ directory."
    read -p "Press Enter to exit..."
    exit 1
fi
echo ""
echo "Checking and installing required Python dependencies..."
python3 -m pip install -q cryptography git+https://github.com/R0rt1z2/liblk --break-system-packages > /dev/null 2>&1 || python3 -m pip install -q cryptography git+https://github.com/R0rt1z2/liblk > /dev/null 2>&1
if [ $? -ne 0 ]; then
    echo "Warning: Failed to install Python dependencies. If patching LK fails, check your internet connection and that all requirements are installed."
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
trap restore_modemmanager EXIT INT TERM HUP

flash_retry() {
    local desc="$1"; shift
    local max_attempts=5
    local attempt
    for ((attempt = 1; attempt <= max_attempts; attempt++)); do
        if [ "$attempt" -eq 1 ]; then
            echo "  [Attempt 1/$max_attempts] Connecting to $desc..."
        else
            echo "  [Attempt $attempt/$max_attempts] Retrying $desc..."
            rm -f .antumbra_state
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
        rm -f .antumbra_state
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

rm -f private.pem public.pem signature.bin lk_patched.img .antumbra_state

if [ -n "$PL_FILE" ] && [ -f "$PL_FILE" ]; then
    PL_SIZE=$(stat -c%s "$PL_FILE" 2>/dev/null || stat -f%z "$PL_FILE" 2>/dev/null || echo 0)
    if [ "$PL_SIZE" -gt 0 ] && [ "$PL_SIZE" -lt 2097152 ] 2>/dev/null; then
        mkdir -p backup >/dev/null 2>&1
        cp -f "$PL_FILE" "backup/$PL_FILE" >/dev/null 2>&1
        cp -f "$PL_FILE" "backup/preloader.bin" >/dev/null 2>&1
    fi
fi
echo ""
echo "Reading lk_a..."
echo "Please power off the device completely, then connect the USB cable and hold (Volume up + Volume down + Power)"
read_retry "lk_a" ./antumbra -c r lk_a lk_a.img --da "$DA_FILE" -p "$PL_FILE"
cp -f lk_a.img lk_b.img >/dev/null 2>&1

echo "Patching lk..."
PATCH_OUTPUT=$(python3 lk-unlock.py patch lk_a.img -o lk_patched.img $USE_WRAP 2>&1)
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
    if [ -n "$PL_FILE" ] && [ -f "backup/$PL_FILE" ]; then
        BACKUP_PL="backup/$PL_FILE"
    elif [ -f "backup/preloader.bin" ]; then
        BACKUP_PL="backup/preloader.bin"
    else
        for f in backup/preloader*.bin backup/preloader*.img; do
            if [ -f "$f" ]; then
                BACKUP_PL="$f"
                break
            fi
        done
    fi

    if [ -z "$SPOOF_RESTORE_LK_A" ]; then
        echo ""
        echo "[!] Error: No stock LK backup found to restore from!"
        echo "[!] Please copy your stock lk and preloader into bin/backup/,"
        echo "[!] then run Restore-Linux.sh to restore stock firmware first."
        read -p "Press Enter to exit..."
        exit 1
    fi

    if [ -z "$BACKUP_PL" ]; then
        echo ""
        echo "[!] Error: No stock preloader backup found in bin/backup/!"
        echo "[!] Cannot safely restore without stock preloader."
        echo "[!] Please copy your stock preloader into bin/backup/ and try again."
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
    echo "[*] Please reboot then run Unlock-Linux.sh again to unlock your bootloader."
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
        python3 lk-unlock.py patch lk_a.img -o lk_patched.img $USE_WRAP
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
echo " Unable to reboot? Run Restore-Linux.sh and try again!"
echo "================================================================="
echo ""
echo "Waiting for fastboot device..."

while [ -z "$(fastboot devices 2>/dev/null)" ]; do
    sleep 1
done

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
exit 0
