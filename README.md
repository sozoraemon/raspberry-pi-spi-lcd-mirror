# Raspberry Pi SPI LCD Mirror

A program that mirrors the Raspberry Pi 5 desktop to a 3.5-inch MHS35 SPI LCD (480×320).

**By using Wayland DMA-BUF for screen capture and C for image processing, this program achieves stable screen mirroring at 20 FPS.**

It also supports the ADS7846 touchscreen, display rotation, and touch calibration.

## Features

- **DMA-BUF screen capture:** Uses the Wayland `zwlr_export_dmabuf_manager_v1` protocol
- **Fast image processing in C:** Performs image scaling, RGB565 conversion, and framebuffer output
- **20 FPS screen mirroring:** Controls frame timing for stable display updates
- **Automatic startup:** Starts the mirroring service automatically using systemd
- **Four display orientations:** Supports 0°, 90°, 180°, and 270° rotation
- **Touchscreen support:** Supports the ADS7846 touchscreen with 9-point calibration

## Tested Environment

- Raspberry Pi 5
- Raspberry Pi OS (Debian 13 / Trixie)
- MHS35 SPI LCD (480×320)
- ADS7846 touchscreen
- labwc (Wayland)
- Source display: `NOOP-1`

### Performance

The following results were measured on a Raspberry Pi 5.

| Item | Result |
|---|---|
| Screen capture method | Wayland DMA-BUF |
| Programming language | C |
| Source resolution | 960×640 |
| SPI LCD resolution | 480×320 |
| Frame rate | Approximately 20 FPS |
| CPU frequency limiting | None |

## How It Works

This program uses the Wayland `zwlr_export_dmabuf_manager_v1` protocol to capture the desktop screen as a DMA-BUF.

The captured image is then processed in C and displayed on the SPI LCD.

The processing flow is shown below.

```text
Raspberry Pi 5
     │
     ▼
Wayland (labwc)
     │
     ▼
Screen Capture via DMA-BUF
     │
     ▼
Image Processing in C
  ├─ Scale to 480×320
  └─ Convert to RGB565
     │
     ▼
/dev/fb0
     │
     ▼
MHS35 SPI LCD
```

Using DMA-BUF can reduce unnecessary memory copying during screen capture.

The captured image is still accessed by the CPU for scaling and RGB565 conversion, so this is not a completely zero-copy implementation.

## Installation

Open a terminal and run the following commands.

```bash
git clone https://github.com/sozoraemon/raspberry-pi-spi-lcd-mirror.git
cd raspberry-pi-spi-lcd-mirror
sudo bash install.sh
```

The installer automatically installs the required packages, compiles the C program, configures the SPI LCD, and registers the systemd service.

After installation, reboot your Raspberry Pi.

```bash
sudo reboot
```

After rebooting, the desktop will be mirrored to the SPI LCD automatically.

### Checking the Service

To check whether the mirroring service is running, execute:

```bash
sudo systemctl status spi-mirror
```

To monitor the frame rate, run:

```bash
sudo journalctl -u spi-mirror -f
```

When the program is running normally, the frame rate is displayed approximately every 10 seconds.

```text
FPS: 20.0
FPS: 20.0
FPS: 19.9
```
## Changing the Desktop Resolution

The MHS35 LCD has a resolution of 480×320, while the Raspberry Pi desktop is initially configured at 1920×1080.

When the entire desktop is scaled down to fit the small LCD, text and icons can become extremely small.

For better readability, we recommend changing the Raspberry Pi desktop resolution to **960×640**.

This resolution has the same 3:2 aspect ratio as the LCD, preventing image distortion and making text and icons easier to see.

Run the following commands to configure the resolution automatically at startup.

```bash
mkdir -p ~/.config/labwc
echo '( sleep 3; wlr-randr --output NOOP-1 --custom-mode 960x640 ) &' >> ~/.config/labwc/autostart
```

Reboot your Raspberry Pi to apply the changes.

```bash
sudo reboot
```

## Display Rotation

The `spi-rotate` command allows you to rotate the SPI LCD to four different orientations: 0°, 90°, 180°, and 270°.

```bash
sudo spi-rotate 0
sudo spi-rotate 90
sudo spi-rotate 180
sudo spi-rotate 270
```

The display resolution and touchscreen calibration values are automatically adjusted according to the selected orientation.

| Rotation | Resolution |
|---|---|
| 0° | 320×480 |
| 90° | 480×320 |
| 180° | 320×480 |
| 270° | 480×320 |

The default rotation is 270°.

After running the command, the following confirmation message appears:

```text
Reboot now? [Y/n]:
```

Press Enter to reboot and apply the changes.

Display output and touch input have been tested successfully in all four orientations.

## Touchscreen Calibration

If the screen responds at a different position from where you touch it, you can calibrate the touchscreen to correct the offset.

Run the following command to start the 9-point calibration process.

```bash
sudo /usr/bin/python3 /usr/local/bin/mhs35_calibrate.py
```

Nine crosshair markers will appear on the screen, one at a time.

Touch the center of each crosshair in the order shown. The program measures the touch position errors and calculates the correction values.

After the measurements are complete, the following confirmation message appears:

```text
Save calibration rule? [y/N]:
```

Type `y` and press Enter to save the calibration values.

Reboot your Raspberry Pi to apply the calibration.

## Notes

- This project has been tested on Raspberry Pi 5.
- It is designed for Raspberry Pi OS Trixie running Wayland (labwc).
- The Wayland socket is expected to be `wayland-0`, and the source display is expected to be `NOOP-1`.
- The Wayland compositor must support `zwlr_export_dmabuf_manager_v1` for DMA-BUF screen capture.
- The current C implementation supports CPU-accessible DMA-BUFs with a linear memory layout.
- The installer creates backups of existing configuration files.
- Other Raspberry Pi models and LCD modules have not been tested.

## Acknowledgments

The MHS35 device tree overlay (`mhs35.dtbo`) used in this project is based on the following open-source project:

**Robinbinu / pi5-mhs35-touchscreen**

https://github.com/Robinbinu/pi5-mhs35-touchscreen

Special thanks to Robinbinu for sharing the technical information and resources needed to use the MHS35 display with Raspberry Pi 5.

This project builds upon that work by adding Wayland desktop mirroring and touchscreen functionality.

The original project's copyright and license terms are respected.
