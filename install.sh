#!/usr/bin/env bash
set -Eeuo pipefail

# Raspberry Pi 5 + MHS35 SPI LCD: Wayland DMA-BUF mirror installer
[[ $EUID -eq 0 ]] || { echo 'Run with: sudo bash install.sh' >&2; exit 1; }
BASE_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
USER_NAME="${SUDO_USER:-}"
[[ -n "$USER_NAME" && "$USER_NAME" != root ]] || { echo 'Run from the desktop user account using sudo.' >&2; exit 1; }
USER_UID="$(id -u "$USER_NAME")"
USER_HOME="$(getent passwd "$USER_NAME" | cut -d: -f6)"
USER_GROUP="$(id -gn "$USER_NAME")"
CONFIG=/boot/firmware/config.txt
CMDLINE=/boot/firmware/cmdline.txt
[[ -f "$CONFIG" && -f "$CMDLINE" ]] || { echo 'Raspberry Pi OS boot configuration not found.' >&2; exit 1; }
for f in mhs35.dtbo mhs35_calibrate.py spi-rotate spi-mirror.service spi-mirror-dmabuf.c build-spi-mirror-dmabuf.sh; do
    [[ -f "$BASE_DIR/$f" ]] || { echo "Missing: $BASE_DIR/$f" >&2; exit 1; }
done
if [[ -e /proc/device-tree/model ]] && ! grep -q 'Raspberry Pi 5' /proc/device-tree/model; then
    echo 'Warning: Only Raspberry Pi 5 has been tested.'
    read -r -p 'Continue? [y/N] ' reply
    [[ "$reply" =~ ^[Yy]$ ]] || exit 1
fi
STAMP="$(date +%Y%m%d-%H%M%S)"
backup() { [[ ! -e "$1" ]] || cp -a -- "$1" "$1.bak-$STAMP"; }

echo '[1/8] Installing DMA-BUF build and touchscreen dependencies'
apt-get update
apt-get install -y gcc pkg-config libwayland-dev libwayland-bin libdrm-dev \
    librust-wayland-protocols-wlr-dev python3-evdev python3-pil

echo '[2/8] Installing device-tree overlay'
install -d /boot/firmware/overlays
backup /boot/firmware/overlays/mhs35.dtbo
install -m 644 "$BASE_DIR/mhs35.dtbo" /boot/firmware/overlays/mhs35.dtbo

echo '[3/8] Updating boot configuration'
backup "$CONFIG"
backup "$CMDLINE"
python3 - "$CONFIG" "$CMDLINE" <<'PY'
from pathlib import Path
import sys
config, cmdline = map(Path, sys.argv[1:])
lines = config.read_text().splitlines()
required = [
    'dtoverlay=vc4-kms-v3d',
    'max_framebuffers=2',
    'dtoverlay=nospi10',
    'dtparam=spi=on',
    'dtoverlay=mhs35:rotate=270,speed=24000000',
]
active = [s for line in lines if (s := line.strip()) and not s.startswith('#')]
for item in required:
    key, value = item.split('=', 1)
    if key == 'dtoverlay':
        name = value.split(':', 1)[0]
        existing = [s for s in active if s.startswith('dtoverlay=') and s.split('=', 1)[1].split(':', 1)[0] == name]
    elif key == 'dtparam':
        param_name = value.split('=', 1)[0]
        existing = [s for s in active if s.startswith('dtparam=') and s.split('=', 1)[1].split('=', 1)[0] == param_name]
    else:
        existing = [s for s in active if s.startswith(key + '=')]
    if existing and item not in existing:
        raise SystemExit(f'Conflicting setting for {item}: {existing}. Check config.txt manually.')
missing = [item for item in required if item not in active]
if missing:
    if lines and lines[-1].strip(): lines.append('')
    lines.extend(['[all]', *missing])
    config.write_text('\n'.join(lines) + '\n')
args = [x for x in cmdline.read_text().strip().split() if not x.startswith('vt.global_cursor_default=')]
args.append('vt.global_cursor_default=0')
cmdline.write_text(' '.join(args) + '\n')
PY

echo '[4/8] Building and installing DMA-BUF mirror and service'
(
    cd "$BASE_DIR"
    bash ./build-spi-mirror-dmabuf.sh
)
backup /usr/local/bin/spi-mirror-dmabuf
install -m 755 "$BASE_DIR/spi-mirror-dmabuf" /usr/local/bin/spi-mirror-dmabuf
backup /usr/local/bin/spi-rotate
install -m 755 "$BASE_DIR/spi-rotate" /usr/local/bin/spi-rotate
backup /usr/local/bin/mhs35_calibrate.py
install -m 755 "$BASE_DIR/mhs35_calibrate.py" /usr/local/bin/mhs35_calibrate.py
backup /etc/systemd/system/spi-mirror.service
install -m 644 "$BASE_DIR/spi-mirror.service" /etc/systemd/system/spi-mirror.service
sed -i "s|@USER_UID@|$USER_UID|g" /etc/systemd/system/spi-mirror.service

echo '[5/8] Configuring labwc touchscreen mapping'
LABWC="$USER_HOME/.config/labwc/rc.xml"
install -d -o "$USER_NAME" -g "$USER_GROUP" "$(dirname "$LABWC")"
backup "$LABWC"
python3 - "$LABWC" <<'PY'
from pathlib import Path
import sys
import xml.etree.ElementTree as ET
p = Path(sys.argv[1])
if p.exists():
    tree = ET.parse(p)
    root = tree.getroot()
else:
    root = ET.Element('openbox_config', {'xmlns': 'http://openbox.org/3.4/rc'})
    tree = ET.ElementTree(root)
if root.tag.split('}')[-1] != 'openbox_config':
    raise SystemExit('Unexpected labwc rc.xml format; no changes made.')
for node in list(root):
    if node.tag.split('}')[-1] == 'touch' and node.get('deviceName') == 'ADS7846 Touchscreen':
        root.remove(node)
ns = root.tag.split('}')[0][1:] if root.tag.startswith('{') else ''
name = f'{{{ns}}}touch' if ns else 'touch'
ET.SubElement(root, name, {'deviceName': 'ADS7846 Touchscreen', 'mapToOutput': 'NOOP-1', 'mouseEmulation': 'yes'})
if ns: ET.register_namespace('', ns)
ET.indent(tree, space='  ')
tree.write(p, encoding='unicode', xml_declaration=True)
PY
chown "$USER_NAME:$USER_GROUP" "$LABWC"

echo '[6/8] Installing touchscreen calibration'
RULE=/etc/udev/rules.d/99-ads7846-calibration.rules
backup "$RULE"
cat > "$RULE" <<'RULE_EOF'
ACTION=="add|change", SUBSYSTEM=="input", KERNEL=="event*", ATTRS{name}=="ADS7846 Touchscreen", ENV{LIBINPUT_CALIBRATION_MATRIX}="0.000462 1.092691 -0.053591 -1.112591 0.000905 1.062629"
RULE_EOF
chmod 644 "$RULE"

echo '[7/8] Enabling mirror service'
systemctl daemon-reload
systemctl enable spi-mirror.service

echo '[8/8] Installation completed'
cat <<'MESSAGE'

Reboot to apply the settings:
  sudo reboot

After reboot:
  systemctl status spi-mirror.service
  journalctl -u spi-mirror.service -f

For touchscreen calibration:
  sudo /usr/bin/python3 /usr/local/bin/mhs35_calibrate.py

Notes:
- Wayland socket: wayland-0
- Mirrored output: NOOP-1
- Mirror engine: C / DMA-BUF (20 FPS)
- Existing configuration files are backed up.
- Only Raspberry Pi 5 has been tested.
MESSAGE
