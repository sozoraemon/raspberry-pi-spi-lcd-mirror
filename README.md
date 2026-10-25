# Raspberry Pi SPI LCD Mirror

A program that mirrors the Raspberry Pi 5 desktop to a 3.5-inch MHS35 SPI LCD (480 × 320).

It also supports touch input using the ADS7846 touchscreen controller.

[English](README.md) | [日本語](README_ja.md)

## Tested Environment

- Raspberry Pi 5
- Raspberry Pi OS (Debian 13 / Trixie)
- MHS35 SPI LCD (480 × 320)
- labwc (Wayland)

## Installation

Open a terminal and run the following commands:

```bash
git clone https://github.com/sozoraemon/raspberry-pi-spi-lcd-mirror.git
cd raspberry-pi-spi-lcd-mirror
sudo bash install.sh
```

After installation, reboot your Raspberry Pi:

```bash
sudo reboot
```

Once the Raspberry Pi restarts, the desktop will be mirrored to the SPI LCD.

## Screen Rotation

Use the `spi-rotate` command to rotate the SPI LCD to 0°, 90°, 180°, or 270°.

```bash
sudo spi-rotate 0
sudo spi-rotate 90
sudo spi-rotate 180
sudo spi-rotate 270
```

The command automatically adjusts the display orientation, resolution, and touchscreen calibration.

| Rotation | Resolution |
|---|---|
| 0° | 320 × 480 |
| 90° | 480 × 320 |
| 180° | 320 × 480 |
| 270° | 480 × 320 |

The default orientation is 270°.

After running the command, the following prompt appears:

```text
Reboot now? [Y/n]:
```

Press Enter to reboot and apply the changes.

All four orientations have been tested successfully, including touchscreen operation.

## Screen Resolution

The MHS35 LCD has a resolution of 480 × 320, but the default desktop resolution is 1920 × 1080. Since the desktop is scaled down to fit the LCD, text and icons appear very small.

We recommend changing the desktop resolution to **960 × 640**. This maintains the same aspect ratio (3:2) as the LCD, preventing image distortion while making text and icons easier to see.

Run the following commands to automatically apply this resolution at startup:

```bash
mkdir -p ~/.config/labwc
echo '( sleep 3; wlr-randr --output NOOP-1 --custom-mode 960x640 ) &' >> ~/.config/labwc/autostart
```

After configuring the resolution, reboot your Raspberry Pi:

```bash
sudo reboot
```

## Touchscreen Calibration

If the touch position does not match where you tap, run the nine-point calibration tool:

```bash
sudo /usr/bin/python3 /usr/local/bin/mhs35_calibrate.py
```

Touch the center of each crosshair displayed on the screen.

After saving the calibration values, reboot your Raspberry Pi to apply the changes.

## Notes

- Tested on Raspberry Pi 5.
- The Wayland socket is assumed to be `wayland-0`, and the mirrored display output is assumed to be `NOOP-1`.
- The installer creates backups of existing configuration files before modifying them.
- Other Raspberry Pi models and LCDs have not been tested.

## Acknowledgements

The MHS35 device-tree overlay (`mhs35.dtbo`) used in this project was originally made available through the following project:

**Robinbinu / pi5-mhs35-touchscreen**

https://github.com/Robinbinu/pi5-mhs35-touchscreen

I would like to thank Robinbinu for sharing the technical information and resources needed to get the MHS35 display working on the Raspberry Pi 5.

Building on this work, this project adds Wayland desktop mirroring and touchscreen support.

The original project's copyright and license terms are respected.
