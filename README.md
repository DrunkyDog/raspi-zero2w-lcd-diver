# Raspberry Pi Zero 2 W — 2.8" Touch LCD HAT (SHCHV MPI2411, ILI9341 + XPT2046)

ไฟล์ทั้งหมด export จากเครื่องจริง `project-alice` (Pi Zero 2 W, Raspberry Pi OS Bookworm 64-bit)
เมื่อ 2026-07-02 — สภาพที่จอแสดงผล + touch ใช้งานได้แล้ว

> **หมายเหตุ:** ชุดไฟล์ของ **Waveshare Zero LCD HAT (A) 3 จอ** แยกอยู่ที่โฟลเดอร์
> พี่น้อง [`Raspberry_Pi_Zero_LCD_HAT_A/`](../Raspberry_Pi_Zero_LCD_HAT_A/)
> (deploy + ทดสอบผ่านแล้วทั้งสามจอ) — **สลับ HAT = รัน install.sh ของชุดนั้น ๆ
> ตัวเดียวจบ** เพราะแต่ละ install.sh ล้าง config ของอีกชุดออกให้อัตโนมัติก่อนติดตั้ง

## สถาปัตยกรรม

ใช้ **DRM/KMS สมัยใหม่** (ไม่ใช่ fbtft/fbcp แบบเก่า):

- `mipi-dbi-spi.dtbo` — kernel driver สร้าง DRM card ให้ panel บน SPI0 CE0
  และ kernel สร้าง `/dev/fb0` ให้อัตโนมัติผ่าน fbdev emulation
- `/lib/firmware/panel.bin` — init sequence ของ ILI9341 (driver โหลดตอน probe)
  source ที่อ่านได้อยู่ที่ `firmware/panel.mipi` (rebuild ด้วย `mipi-dbi-cmd`)
- `ads7846.dtbo` — touch controller XPT2046 บน SPI0 CE1 (compatible กับ ads7846)
- `99-v3d.conf` — บังคับ Xorg ใช้ vc4/v3d เป็น PrimaryGPU (ระบบมี DRM card 2 ตัว
  ถ้าไม่มีไฟล์นี้ Xorg อาจเลือก card ผิดแล้วเดสก์ท็อปไม่ขึ้นบนจอ)
- `99-touch-calibration.rules` — calibration matrix ของ touch ผ่าน libinput
- `blank-panel.service` + `blank-panel.sh` — เคลียร์จอเป็นสีดำตอน shutdown
  (backlight ฮาร์ดไวร์ 3.3V ดับด้วย software ไม่ได้)
- `kanshi/config` → `~/.config/kanshi/config` — **สำคัญ:** จอติดตั้งกลับหัวเทียบ
  ทิศ MADCTL ใน panel.bin ต้องชดเชยที่ compositor (labwc/Wayland) ด้วย
  `transform flipped-180` + `scale 0.6` ถ้าไม่มีไฟล์นี้**จอจะแสดงผลกลับด้าน**
  ข้อควรรู้: kanshi อ่าน config เฉพาะตอน start — แก้ไฟล์แล้วต้อง restart kanshi
  หรือ reboot ถึงจะเห็นผล (ชื่อ output `SPI-1` ใช้ได้เพราะระบบนี้มี panel เดียว)

## การต่อสาย (SPI0)

| สัญญาณ | GPIO (BCM) | Pin |
|---|---|---|
| SCLK | GPIO11 | 23 |
| MOSI | GPIO10 | 19 |
| MISO | GPIO9 | 21 |
| LCD CS (CE0) | GPIO8 | 24 |
| TOUCH CS (CE1) | GPIO7 | 26 |
| LCD DC | GPIO22 | 15 |
| LCD RESET | GPIO27 | 13 |
| TOUCH IRQ | GPIO17 | 11 |
| Backlight | 3.3V ตรง | — |

## โครงสร้างไฟล์

```
├── install.sh                  # ติดตั้ง/ตั้งค่าทั้งหมดในไฟล์เดียว (sudo ./install.sh)
├── boot/
│   ├── config.txt              # สำเนา config.txt จริงจากเครื่อง (อ้างอิง)
│   └── cmdline.txt             # สำเนา cmdline.txt จริงจากเครื่อง (อ้างอิง)
├── overlays/
│   ├── mipi-dbi-spi.dtbo       # overlay จอ (ปกติมากับ OS อยู่แล้ว)
│   └── ads7846.dtbo            # overlay touch (ปกติมากับ OS อยู่แล้ว)
├── firmware/
│   ├── panel.bin               # ILI9341 init blob -> /lib/firmware/
│   └── panel.mipi              # source ของ panel.bin (อ่าน/แก้ได้)
├── xorg.conf.d/99-v3d.conf     # -> /etc/X11/xorg.conf.d/
├── udev/99-touch-calibration.rules  # -> /etc/udev/rules.d/
├── systemd/blank-panel.service # -> /etc/systemd/system/
└── scripts/blank-panel.sh      # -> /usr/local/bin/
```

## ติดตั้งบนเครื่องใหม่

```bash
scp -r Raspberry_Pi_Zero_2inch8_Touch_LCD_HAT/ user@pi:~/
ssh user@pi
cd ~/Raspberry_Pi_Zero_2inch8_Touch_LCD_HAT
sudo ./install.sh
sudo reboot
```

ถอนการติดตั้ง: `sudo ./install.sh --uninstall`

## หมายเหตุ

- `boot/config.txt` (สำเนาจากเครื่องจริง) มีบรรทัด `dtoverlay=mipi-dbi-spi`
  เปล่า ๆ ซ้ำอยู่หนึ่งบรรทัดเหนือบล็อกจอ — เป็นของตกค้าง ไม่จำเป็น
  `install.sh` เขียนเฉพาะบล็อกที่ถูกต้อง (มี marker ครอบ รันซ้ำได้ไม่ซ้ำซ้อน)
- ปรับ rotation: แก้ค่า MADCTL (`command 0x36 0x68`) ใน `firmware/panel.mipi`
  แล้ว rebuild เป็น panel.bin หรือเพิ่ม `dtparam=rotation=90|180|270` ที่ overlay
- calibration matrix ปัจจุบัน: `0 1.16006 -0.04618 -1.16418 0 1.07335`
  (swap แกน + สเกล สำหรับ landscape) ถ้าจอหมุนต้อง calibrate ใหม่
