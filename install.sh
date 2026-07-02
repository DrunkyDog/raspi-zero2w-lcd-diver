#!/bin/bash
# ============================================================================
# install.sh — ติดตั้งจอ SHCHV MPI2411 2.8" ILI9341 320x240 + XPT2046 Touch
#              สำหรับ Raspberry Pi Zero 2 W (Raspberry Pi OS Bookworm, KMS)
#
# สิ่งที่สคริปต์นี้ทำ (ไฟล์เดียวจบ):
#   1. ติดตั้ง panel.bin (ILI9341 init sequence) -> /lib/firmware/
#   2. ติดตั้ง .dtbo (mipi-dbi-spi, ads7846) -> /boot/firmware/overlays/ ถ้ายังไม่มี
#   3. เขียนบล็อก config ลง /boot/firmware/config.txt (idempotent — รันซ้ำได้)
#   4. ติดตั้ง Xorg config บังคับ vc4/v3d เป็น PrimaryGPU
#   5. ติดตั้ง udev rule calibration ของ touch (libinput matrix)
#   6. ติดตั้ง blank-panel.sh + systemd service (ดับจอเป็นสีดำตอน shutdown)
#
# การต่อสาย (SPI0):
#   SCLK=GPIO11  MOSI=GPIO10  MISO=GPIO9
#   LCD CS=GPIO8 (CE0)   TOUCH CS=GPIO7 (CE1)
#   DC=GPIO22   RESET=GPIO27   PEN_IRQ=GPIO17
#   Backlight ต่อตรง 3.3V (ดับด้วย software ไม่ได้)
#
# ใช้งาน:  sudo ./install.sh          (ติดตั้ง)
#          sudo ./install.sh --uninstall  (ถอนการตั้งค่า config.txt + service)
# ============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MARK_BEGIN="# ===== BEGIN 2.8inch ILI9341 Touch LCD (managed by install.sh) ====="
MARK_END="# ===== END 2.8inch ILI9341 Touch LCD ====="

# --- ตรวจสภาพแวดล้อม ---------------------------------------------------------
[ "$(id -u)" -eq 0 ] || { echo "ต้องรันด้วย sudo: sudo $0"; exit 1; }

if   [ -f /boot/firmware/config.txt ]; then BOOTFW=/boot/firmware
elif [ -f /boot/config.txt ];          then BOOTFW=/boot
else echo "ไม่พบ config.txt — ไม่ใช่ Raspberry Pi OS?"; exit 1; fi
CONFIG="$BOOTFW/config.txt"

# --- โหมดถอนการติดตั้ง -------------------------------------------------------
if [ "${1:-}" = "--uninstall" ]; then
    echo ">> ถอนการตั้งค่า LCD ..."
    sed -i "/^${MARK_BEGIN}$/,/^${MARK_END}$/d" "$CONFIG"
    systemctl disable --now blank-panel.service 2>/dev/null || true
    rm -f /etc/systemd/system/blank-panel.service /usr/local/bin/blank-panel.sh
    rm -f /etc/udev/rules.d/99-touch-calibration.rules
    rm -f /etc/X11/xorg.conf.d/99-v3d.conf
    rm -f /lib/firmware/panel.bin
    systemctl daemon-reload
    echo ">> เสร็จ — reboot เพื่อให้มีผล"
    exit 0
fi

echo "== [1/7] ติดตั้ง panel firmware (ILI9341 init sequence) =="
install -m 644 "$SCRIPT_DIR/firmware/panel.bin" /lib/firmware/panel.bin

echo "== [2/7] ตรวจ device-tree overlays =="
for dtbo in mipi-dbi-spi.dtbo ads7846.dtbo; do
    if [ ! -f "$BOOTFW/overlays/$dtbo" ]; then
        echo "   ไม่พบ $dtbo ในระบบ — copy จากชุดติดตั้ง"
        install -m 755 "$SCRIPT_DIR/overlays/$dtbo" "$BOOTFW/overlays/$dtbo"
    else
        echo "   $dtbo มีอยู่แล้ว (ใช้ของระบบ)"
    fi
done

echo "== [3/7] ตั้งค่า $CONFIG =="
cp "$CONFIG" "$CONFIG.bak.$(date +%Y%m%d%H%M%S)"
# เปิด SPI (uncomment ถ้าถูก comment ไว้)
sed -i 's/^#dtparam=spi=on/dtparam=spi=on/' "$CONFIG"
grep -q '^dtparam=spi=on' "$CONFIG" || echo 'dtparam=spi=on' >> "$CONFIG"
# ลบบล็อกเดิม (ถ้ามี) แล้วเขียนใหม่ — ทำให้รันซ้ำได้โดยไม่ซ้ำซ้อน
sed -i "/^${MARK_BEGIN}$/,/^${MARK_END}$/d" "$CONFIG"
# --- ล้าง config ของ Zero LCD HAT (A) 3 จอ ถ้าเคยติดตั้งไว้ (สลับ HAT) ---
sed -i "/^# ===== BEGIN Zero LCD HAT (A)/,/^# ===== END Zero LCD HAT (A)/d" "$CONFIG"
systemctl disable --now fbcon-map.service 2>/dev/null || true
rm -f /etc/systemd/system/fbcon-map.service /usr/local/bin/fbcon-map.py \
      /usr/local/bin/hat-layout.py /lib/firmware/st7735s.bin
if [ -n "${SUDO_USER:-}" ]; then
    U_HOME="$(getent passwd "$SUDO_USER" | cut -d: -f6)"
    sed -i "\|hat-layout|d" "$U_HOME/.config/labwc/autostart" 2>/dev/null || true
fi
cat >> "$CONFIG" <<EOF

${MARK_BEGIN}
# จอ SHCHV MPI2411 ILI9341 320x240 ผ่าน mipi-dbi-spi (DRM/KMS)
# init sequence โหลดจาก /lib/firmware/panel.bin
dtoverlay=mipi-dbi-spi,spi0-0,speed=16000000,write-only
dtparam=width=320,height=240
dtparam=reset-gpio=27,dc-gpio=22
# XPT2046 touch ผ่าน ads7846 (CE1)
dtoverlay=ads7846,cs=1,penirq=17,penirq_pull=2,speed=1000000,keep-vref-on=1,swapxy=0,pmax=255,xohms=100
${MARK_END}
EOF

echo "== [4/7] Xorg: บังคับ vc4/v3d เป็น PrimaryGPU =="
install -d /etc/X11/xorg.conf.d
install -m 644 "$SCRIPT_DIR/xorg.conf.d/99-v3d.conf" /etc/X11/xorg.conf.d/99-v3d.conf

echo "== [5/7] udev: touch calibration matrix (libinput) =="
install -m 644 "$SCRIPT_DIR/udev/99-touch-calibration.rules" \
    /etc/udev/rules.d/99-touch-calibration.rules
udevadm control --reload || true

echo "== [6/7] blank-panel service (จอดำตอน shutdown) =="
install -m 755 "$SCRIPT_DIR/scripts/blank-panel.sh" /usr/local/bin/blank-panel.sh
install -m 644 "$SCRIPT_DIR/systemd/blank-panel.service" \
    /etc/systemd/system/blank-panel.service
systemctl daemon-reload
systemctl enable blank-panel.service

echo "== [7/7] kanshi: พลิกจอ 180 + scale (labwc/Wayland) =="
# จอ 2.8" ติดตั้งกลับหัวเทียบทิศ MADCTL — ต้องชดเชยที่ compositor ด้วย kanshi
TARGET_USER="${SUDO_USER:-$(id -un 1000 2>/dev/null || echo pi)}"
TARGET_HOME="$(getent passwd "$TARGET_USER" | cut -d: -f6)"
if [ -n "$TARGET_HOME" ]; then
    install -d -o "$TARGET_USER" -g "$TARGET_USER" "$TARGET_HOME/.config/kanshi"
    if [ -f "$TARGET_HOME/.config/kanshi/config" ]; then
        cp "$TARGET_HOME/.config/kanshi/config" "$TARGET_HOME/.config/kanshi/config.pre-2.8inch"
    fi
    install -m 644 -o "$TARGET_USER" -g "$TARGET_USER" \
        "$SCRIPT_DIR/kanshi/config" "$TARGET_HOME/.config/kanshi/config"
fi

echo
echo "============================================================"
echo " ติดตั้งเสร็จแล้ว — reboot เพื่อให้จอทำงาน:  sudo reboot"
echo " (kanshi อ่าน config ตอน start เท่านั้น — reboot จะจัดการให้เอง)"
echo " หลัง reboot ตรวจสอบด้วย:"
echo "   ls /dev/fb0                        # framebuffer ของจอ"
echo "   dmesg | grep -Ei 'mipi|ili|ads7846' # driver โหลดสำเร็จ"
echo "   libinput list-devices               # เห็น ADS7846 Touchscreen"
echo "============================================================"
