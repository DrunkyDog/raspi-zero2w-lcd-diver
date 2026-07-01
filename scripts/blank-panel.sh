#!/bin/sh
# Blank SPI panel (fb0) to black on shutdown.
# Backlight ฮาร์ดไวร์ 3.3V ดับด้วย software ไม่ได้ — แต่จอดำดีกว่าขาวจ้า
for i in 1 2 3; do
  cat /dev/zero > /dev/fb0 2>/dev/null && break
  sleep 0.2
done
exit 0
