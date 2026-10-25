# raspberry-pi-spi-lcd-mirror
Mirror the Raspberry Pi desktop to an SPI LCD using grim and FFmpeg.
Raspberry Pi SPI LCD Mirror
Mirror a Raspberry Pi Wayland desktop to a 3.5-inch MHS35 SPI LCD, with ADS7846 touchscreen support.

The display is driven through the Linux framebuffer (/dev/fb0), while grim captures the Wayland desktop and FFmpeg converts frames to RGB565. A systemd service runs the mirror automatically.
Tested setup: Raspberry Pi 5, Raspberry Pi OS based on Debian 13 (Trixie), labwc (Wayland), MHS35 480 × 320 SPI LCD with ADS7846 touchscreen. Other Raspberry Pi models and LCDs have not been verified.

Files
File	Purpose
mhs35.dtbo	Device-tree overlay for the MHS35 LCD and touchscreen
spi-mirror.sh	Capture and transfer Wayland frames to /dev/fb0
spi-mirror.service	Start the mirror automatically with systemd
mhs35_calibrate.py	Optional nine-point touchscreen calibration


1. Install packages
Open a terminal on the Raspberry Pi:
sudo apt update
sudo apt install -y grim ffmpeg evtest libinput-tools python3-evdev python3-pil
The mirror script assumes the desktop user is pi, with UID 1000, and the Wayland socket is wayland-0. If your username, UID, or socket differs, edit spi-mirror.sh before enabling the service.
2. Enable the SPI LCD
Copy the included overlay:
sudo cp mhs35.dtbo /boot/firmware/overlays/
Edit the boot configuration:
sudo nano /boot/firmware/config.txt
Ensure the following settings are present once (do not duplicate existing lines):
dtoverlay=vc4-kms-v3d
max_framebuffers=2
dtoverlay=nospi10
dtparam=spi=on
dtoverlay=mhs35:rotate=270,speed=24000000
To hide the framebuffer console's blinking cursor, add vt.global_cursor_default=0 to the existing single line in /boot/firmware/cmdline.txt. Do not add a new line or remove existing boot parameters.

Reboot:
sudo reboot
After rebooting, confirm the framebuffer exists:
ls -l /dev/fb0
Important: /dev/fb0 must be the MHS35 LCD at 480 × 320, 16-bit RGB565. The scripts assume this framebuffer layout. Confirm it on your system before proceeding.

3. Install and start the mirror
From the directory containing the downloaded repository files:
sudo install -m 755 spi-mirror.sh /usr/local/bin/spi-mirror.sh
sudo install -m 644 spi-mirror.service /etc/systemd/system/spi-mirror.service
sudo systemctl daemon-reload
sudo systemctl enable --now spi-mirror.service
Check its status:
systemctl status spi-mirror.service
The current script captures the whole Wayland desktop and scales it to 480 × 320. The tested virtual Wayland output was NOOP-1 at 1280 × 720. Other source resolutions can work, but a different aspect ratio may stretch the picture.
4. Configure touchscreen input in labwc
The ADS7846 touchscreen must be mapped to the Wayland output that is being mirrored. The tested output name is NOOP-1; verify yours with:
wlr-randr
libinput list-devices
Edit your labwc configuration:
mkdir -p ~/.config/labwc
nano ~/.config/labwc/rc.xml
Add the <touch> element inside the existing <openbox_config> element (preserve other settings). A minimal example is:
<?xml version="1.0"?>
<openbox_config xmlns="http://openbox.org/3.4/rc">
  <touch deviceName="ADS7846 Touchscreen" mapToOutput="NOOP-1" mouseEmulation="yes"/>
</openbox_config>
Apply the configuration:
labwc --reconfigure
If your output is not NOOP-1, replace NOOP-1 with the output name reported by wlr-randr.
5. Apply the tested touchscreen calibration
The following six-value calibration matrix was obtained using nine-point calibration on the tested MHS35 panel. Try it first; calibrate again only if the touch positions do not match. Individual panels can differ.
sudo tee /etc/udev/rules.d/99-ads7846-calibration.rules > /dev/null <<'EOF_RULE'
ACTION=="add|change", SUBSYSTEM=="input", KERNEL=="event*", ATTRS{name}=="ADS7846 Touchscreen", ENV{LIBINPUT_CALIBRATION_MATRIX}="0.000462 1.092691 -0.053591 -1.112591 0.000905 1.062629"
EOF_RULE
sudo reboot
After rebooting, test touch accuracy near the top, center, bottom, and both edges. If it is satisfactory, no further calibration is needed.
6. Optional: nine-point calibration
If the touch position is still inaccurate, use the included Python calibration tool:
sudo install -m 755 mhs35_calibrate.py /usr/local/bin/mhs35_calibrate.py
sudo /usr/bin/python3 /usr/local/bin/mhs35_calibrate.py
The script:
1. Temporarily stops spi-mirror.service if it is running.
2. Draws nine targets directly on the SPI framebuffer.
3. Records the raw ADS7846 coordinates for each target.
4. Calculates an affine calibration matrix using least squares.
5. Shows average and maximum measurement errors.
6. Asks before saving the new udev rule; backs up any existing rule.
7. Restarts the mirror service when finished.
Use a fine-tipped stylus, touch the center of each cross, hold briefly, then release. When asked Save calibration rule? [y/N]:, enter y to save the new calibration, then reboot:
sudo reboot
Note: The calibration script currently expects the touchscreen at /dev/input/event5 and the LCD at /dev/fb0. Input event numbers can change across boots. Check with libinput list-devices and adjust DEVICE near the top of mhs35_calibrate.py if needed. The script also assumes a 480 × 320 LCD.
Troubleshooting
The screen stays blank: Check systemctl status spi-mirror.service, confirm /dev/fb0 is the MHS35 framebuffer, and verify that a Wayland session is running. The script explicitly uses pi, UID 1000, and wayland-0.

Touch works but selects the wrong position: Confirm the labwc mapToOutput matches the mirrored output. Apply the default matrix above, then use nine-point calibration only if needed.

Calibration script reports ModuleNotFoundError: No module named 'evdev': Install python3-evdev using apt and run the script with /usr/bin/python3.

The picture looks stretched: The mirror always scales to 480 × 320. A source output with a 3:2 aspect ratio avoids stretching; ensure the compositor supports your chosen resolution.
Overlay attribution and licensing
The mhs35.dtbo overlay used in this setup originated from the Robinbinu/pi5-mhs35-touchscreen project. Review and preserve its original copyright and license notices when redistributing it. A license for this repository's original scripts should be chosen separately; including an upstream binary does not transfer its copyright.
Limitations
- Verified on Raspberry Pi 5 only.
- The SPI LCD mirrors an existing Wayland output; it is not a separate Wayland display.
- The current mirror script performs repeated screen capture and conversion, which can use significant CPU resources and may not provide smooth video playback.
- The calibration matrix is an affine approximation; resistive touchscreen nonlinearities may leave small residual errors.
