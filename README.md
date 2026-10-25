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
