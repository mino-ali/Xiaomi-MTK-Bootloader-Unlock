<h1 align="center"> Xiaomi MediaTek LK Bootloader Unlock</h1>

<p align="center">
  <b>Automated LK-Unlock Exploit for Xiaomi MediaTek Devices</b>
</p>

<p align="center">
  <a href="https://www.gnu.org/licenses/agpl-3.0"><img src="https://img.shields.io/badge/License-AGPL_v3-blue.svg" alt="License: AGPL v3"></a>
  <img src="https://img.shields.io/badge/Device-Xiaomi_MediaTek-orange.svg" alt="Device: Xiaomi MediaTek">
  <img src="https://img.shields.io/badge/SoC-MediaTek_MTK-red.svg" alt="SoC: MediaTek MTK">
  <img src="https://img.shields.io/badge/Platform-Windows%20%7C%20Linux-brightgreen.svg" alt="Platform">
</p>

---

## Disclaimers & Pre-Checks

> [!WARNING]
> **Device compatibility & liability warning:**  
> This script is designed for Xiaomi MediaTek (MTK) devices that are vulnerable to the Kamakiri BROM exploit (allowing partition read/write access via BROM mode) and use Xiaomi's RSA-2048 signature verification in Little Kernel (LK) for bootloader unlocking, Check [Discussion #5](https://github.com/mino-ali/Xiaomi-MTK-Bootloader-Unlock/discussions/5#discussioncomment-18721629).  
> Devices with newer non-RSA key formats or hardware-bound security architectures that cannot be modified via BROM are not supported. The author of this tool is not responsible for any damage, bricked devices, or hardware issues caused by misuse. Proceed entirely at your own risk.

> [!CAUTION]
> **Data loss warning:**  
> Unlocking the bootloader performs a full factory reset. All photos, apps, files, messages, and settings will be permanently wiped. Back up your important files to your computer or cloud before proceeding.

* **Battery:** Charge your device to at least 50% before starting. Never unplug the cable during read or write operations.
* **Cable & port:** Use a reliable USB-C data cable. Plug directly into the rear USB ports of your motherboard (a USB 2.0 port is best for MediaTek BROM stability). Do not use unpowered USB hubs or loose front-panel ports.

---

## Critical Notes

> [!IMPORTANT]
> ### 1. Bootloader relock after flashing any ROM
> **Please read this before flashing any ROM or system update:**  
> After you flash a new ROM (official MIUI, HyperOS, custom AOSP ROMs, or fastboot/recovery packages), the bootloader might automatically relock itself because the LK partition gets overwritten.
> 
> **Don't panic! Your phone is not permanently locked or broken.**  
> Simply reconnect the phone to your PC and run the unlock script again after flashing. Once the script finishes, the device will boot normally.

> [!NOTE]
> ### 2. Expected error screens
> If the bootloader relocks itself after you flash a ROM, you will see one of these two warning screens:
> 
> 1. **If locked on official MIUI or HyperOS:**  
>    `"This version of MIUI can't be installed on this device"` or  
>    `"This version of HyperOS can't be installed on this device"`
> 2. **If locked on an AOSP / Custom ROM (LineageOS, PixelOS, crDroid, etc.):**  
>    Black screen with red text: `"The system has been destroyed"`
> 
> **This is completely normal and expected.** Your phone is not bricked. Both of these errors disappear simply by running the unlock script again.

---

<span id="emergency-restore-scripts"></span>
## Emergency Restore Scripts

If something goes wrong during the unlock process and your device fails to boot up, a `Restore/` folder is included to flash your original stock partition backups back onto the device:

* **Windows:** Open the `Restore` folder, right-click `Restore-Windows.bat`, and select **Run as administrator**.
* **Linux:** Open a terminal in the folder and run:
  ```bash
  chmod +x Restore-Linux.sh && sudo ./Restore-Linux.sh
  ```

---

## Requirements

### Windows 10/11
1. Python (make sure it is added to your system PATH)
2. Git
3. Fastboot / Android USB drivers

### Linux
1. Install the required packages using your package manager:
   * **Ubuntu / Debian:** `sudo apt install python3 python3-pip git android-tools-fastboot libudev-dev`
   * **Fedora / RHEL:** `sudo dnf install python3 python3-pip git android-tools systemd-devel`
   * **Arch / Manjaro:** `sudo pacman -S python python-pip git android-tools systemd-libs`
2. *Note:* `libudev` (`libudev-dev` / `systemd-devel` / `systemd-libs`) is a required Linux dependency.

> [!TIP]
> After installing all requirements for the first time, a system reboot is required.
---

## Frequently Asked Questions (FAQ)

> [!NOTE]
> **Q: When trying to reboot into Fastboot mode, my phone is stuck in BROM mode. What should I do?**  
> **A:** First, run the [Restore script](#emergency-restore-scripts) for your operating system, then try the unlock process again. If the issue persists, place **lk.img** and your device's **preloader** from your stock firmware inside the `bin/backup/` folder, then run the [Restore script](#emergency-restore-scripts).
> 
> **Q: I get "Failed to get storage for partition parsing" or "Partition 'lk_a' not found on device". What should I do?**  
> **A:**  
> 1. Make sure your phone is **completely powered off** before connecting (hold Power for 15 seconds until completely shut down, then wait 5 seconds before connecting to BROM).  
> 2. Ensure the preloader and Download Agent placed in `bin/` were extracted from the Fastboot ROM matching the **exact firmware version** (MIUI vs HyperOS) currently installed on the phone.  
> 3. Use a direct **USB 2.0 port** on the back of your motherboard (avoid USB 3.0/3.2 ports, USB hubs, or Type-C to Type-C cables as they can cause transfer timeouts).

---

## Required Files Setup

To respect copyright and open-source licensing laws, proprietary vendor firmware binaries are **not** included in this repository. You must extract them from your device's official stock Fastboot ROM before running the scripts:

1. Download the official Xiaomi Fastboot ROM (`.tgz`) matching the exact firmware version currently running on your phone.
2. Extract the downloaded Fastboot ROM package on your computer.
3. Copy the following 2 files directly into the `bin/` folder:
   * From the `images/` folder of the extracted ROM:  
     Copy your device's preloader file (e.g. `preloader_ruby.bin` or `preloader.bin`) into the `bin/` folder.
   * From the extracted ROM folder:  
     Copy your Download Agent binary (e.g. `MTK_AllInOne_DA.bin` or `DA.bin`) into the `bin/` folder.

Ensure both your preloader and Download Agent files are placed inside the `bin/` folder before proceeding.

---

## Step-by-Step Unlock Tutorial

### Step 1 (Windows): Launch the script
1. Right-click `Unlock-Windows.bat` and select **Run as administrator**.
2. When prompted by the data wipe warning, type `Y` and press Enter.
3. When prompted for cert bypass mode, just press **Enter** (defaults to `1. override`).
4. Proceed to Step 2.

### Step 1 (Linux): Launch the script
1. Open a terminal in the directory, make the script executable, and run with sudo:
   ```bash
   chmod +x Unlock-Linux.sh
   sudo ./Unlock-Linux.sh
   ```
2. When prompted by the data wipe warning, type `Y` and press Enter.
3. When prompted for cert bypass mode, just press **Enter** (defaults to `1. override`).
4. Proceed to Step 2.

> [!NOTE]
> **Cert bypass mode selection:**  
> Just press **Enter** (default option 1).  
> Wrap mode (option 2) is only for older legacy devices. If after rebooting your phone gets stuck in BROM or boots to a "Red State" screen, check if the terminal says `cert2 could not be parsed` during patching LK. If so, run the restore script first, then re-run unlock and choose option **2 (wrap)**.

---

### Step 2: Connect the phone in BROM mode
1. Turn off your phone completely.
2. Press and hold **`[Volume Up]` + `[Volume Down]`** (also hold **`[Power]`** on some devices).
3. While holding the buttons, connect the USB cable.
4. As soon as the script detects the device, release the buttons.

---

### Step 3: Reboot to Fastboot mode & finish unlock
1. When partition flashing finishes, the script will prompt you:
   * Unplug the USB cable from the phone.
   * Wait 10 seconds with the cable unplugged.
   * Boot into Fastboot mode: Press and hold `[Volume Down]` + `[Power]` until the orange/yellow fastboot logo appears.
   * Reconnect the USB cable.
2. The script will automatically detect your phone in Fastboot and send the unlock command.
3. The terminal will display: `Unlock success!`
4. The phone will perform a factory reset and boot up with an unlocked bootloader.

---

## Credits

* [lk-unlock](https://github.com/georgiynesterov/lk-unlock) by [@georgiynesterov](https://github.com/georgiynesterov) for the original public key patching and token forging exploit.
* Cert bypass code adapted from [lkpatcher](https://github.com/R0rt1z2/lkpatcher) and [liblk](https://github.com/R0rt1z2/liblk) by [@R0rt1z2](https://github.com/R0rt1z2).
* [Penumbra](https://github.com/shomykohai/penumbra) (Antumbra CLI) by [@shomykohai](https://github.com/shomykohai) for dumping and flashing partitions via MediaTek BROM.
* [mtkclient](https://github.com/bkerler/mtkclient) by [@bkerler](https://github.com/bkerler) for MediaTek exploitation and research.
* [libwdi](https://github.com/pbatard/libwdi) (`wdi-simple`) by [@pbatard](https://github.com/pbatard) for automated USB driver installation.
* [@LucaCraft89](https://github.com/LucaCraft89) for script improvements.
* [@YagizErdemir06](https://github.com/YagizErdemir06) for overall support.
* Xiaomi & MediaTek bootloader research community.
---

## License

This project is licensed under the **GNU Affero General Public License v3.0** — see [LICENSE](https://www.gnu.org/licenses/agpl-3.0) for details.
