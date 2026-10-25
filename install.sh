#!/usr/bin/env bash
set -Eeuo pipefail

# Installer for Raspberry Pi 5 + MHS35 SPI LCD (480x320, RGB565)
[[ $EUID -eq 0 ]] || { echo 'Run with: sudo bash install.sh' >&2; exit 1; }
BASE_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
USER_NAME="${SUDO_USER:-}"
[[ -n "$USER_NAME" && "$USER_NAME" != root ]] || { echo 'Run from your desktop user account using sudo.' >&2; exit 1; }
USER_UID="$(id -u "$USER_NAME")"
USER_HOME="$(getent passwd "$USER_NAME" | cut -d: -f6)"
CONFIG=/boot/firmware/config.txt
CMDLINE=/boot/firmware/cmdline.txt
[[ -f "$CONFIG" && -f "$CMDLINE" ]] || { echo 'Raspberry Pi OS boot configuration not found.' >&2; exit 1; }
for f in mhs35.dtbo spi-mirror.sh spi-mirror.service mhs35_calibrate.py; do
  [[ -f "$BASE_DIR/$f" ]] || { echo "Missing: $BASE_DIR/$f" >&2; exit 1; }
done
if [[ -e /proc/device-tree/model ]] && ! grep -q 'Raspberry Pi 5' /proc/device-tree/model; then
  echo 'Warning: Only Raspberry Pi 5 has been tested.'
  read -r -p 'Continue? [y/N] ' reply
  [[ "$reply" =~ ^[Yy]$ ]] || exit 1
fi

STAMP="$(date +%Y%m%d-%H%M%S)"
backup() { [[ ! -e "$1" ]] || cp -a -- "$1" "$1.bak-$STAMP"; }

echo '[1/8] Installing dependencies'
apt-get update
apt-get install -y grim ffmpeg python3-evdev python3-pil

echo '[2/8] Installing device-tree overlay'
echo '[3/8] Updating config.txt and cmdline.txt'
backup "$CONFIG"
backup "$CMDLINE"
install -m 644 "$BASE_DIR/mhs35.dtbo" /boot/firmware/overlays/mhs35.dtbo
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
# Preserve unrelated settings and reject conflicting active values.
for item in required:
    key = item.split('=', 1)[0]
    if key == 'dtoverlay':
        name = item.split('=', 1)[1].split(':', 1)[0]
        present = any(x.strip().split('=', 1)[-1].split(':', 1)[0] == name
                      for x in lines if x.strip().startswith('dtoverlay='))
    else:
        present = any(x.strip().startswith(key + '=') for x in lines)
    if key != 'dtoverlay':
        existing = [x.strip() for x in lines if x.strip().startswith(key + '=')]
        if existing and item not in existing:
            raise SystemExit(f'Conflicting {key} setting: {existing}. Check config.txt manually.')
    if key == 'dtoverlay' and present and item not in [x.strip() for x in lines]:
        raise SystemExit(f'Conflicting overlay options for {name}. Check config.txt manually.')
    if not present:
        lines.append(item)
config.write_text('\n'.join(lines) + '\n')
args = cmdline.read_text().strip().split()
if 'vt.global_cursor_default=0' not in args:
    args = [x for x in args if not x.startswith('vt.global_cursor_default=')]
    args.append('vt.global_cursor_default=0')
cmdline.write_text(' '.join(args) + '\n')
PY

echo '[4/8] Installing mirroring script and service'
# The bundled script is configured for pi/UID 1000. Adjust its runtime credentials
# to the account invoking this installer without modifying the repository copy.
install -m 755 "$BASE_DIR/spi-mirror.sh" /usr/local/bin/spi-mirror.sh
python3 - /usr/local/bin/spi-mirror.sh "$USER_NAME" "$USER_UID" <<'PY'
from pathlib import Path
import sys
p = Path(sys.argv[1])
s = p.read_text()
s = s.replace('sudo -u pi env', 'sudo -u ' + sys.argv[2] + ' env')
s = s.replace('XDG_RUNTIME_DIR=/run/user/1000', 'XDG_RUNTIME_DIR=/run/user/' + sys.argv[3])
p.write_text(s)
PY
install -m 644 "$BASE_DIR/spi-mirror.service" /etc/systemd/system/spi-mirror.service
install -m 755 "$BASE_DIR/mhs35_calibrate.py" /usr/local/bin/mhs35_calibrate.py

echo '[5/8] Configuring labwc touch mapping'
LABWC="$USER_HOME/.config/labwc/rc.xml"
install -d -o "$USER_NAME" -g "$(id -gn "$USER_NAME")" "$(dirname "$LABWC")"
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
ET.SubElement(root, name, {'deviceName': 'ADS7846 Touchscreen',
                           'mapToOutput': 'NOOP-1', 'mouseEmulation': 'yes'})
if ns:
    ET.register_namespace('', ns)
ET.indent(tree, space='  ')
tree.write(p, encoding='unicode', xml_declaration=True)
PY
chown "$USER_NAME:$(id -gn "$USER_NAME")" "$LABWC"

echo '[6/8] Installing tested touchscreen calibration'
RULE=/etc/udev/rules.d/99-ads7846-calibration.rules
backup "$RULE"
cat > "$RULE" <<'RULE_EOF'
ACTION=="add|change", SUBSYSTEM=="input", KERNEL=="event*", ATTRS{name}=="ADS7846 Touchscreen", ENV{LIBINPUT_CALIBRATION_MATRIX}="0.000462 1.092691 -0.053591 -1.112591 0.000905 1.062629"
RULE_EOF
chmod 644 "$RULE"

echo '[7/8] Enabling mirror service'
systemctl daemon-reload
systemctl enable spi-mirror.service
echo '[8/8] Reboot instructions'
cat <<'MESSAGE'

Installation completed. Reboot to apply the LCD and touchscreen settings:
  sudo reboot

After reboot, check:
  systemctl status spi-mirror.service

If touch alignment is inaccurate, run:
  sudo /usr/bin/python3 /usr/local/bin/mhs35_calibrate.py

Notes:
- The Wayland socket is assumed to be wayland-0.
- The mirrored labwc output is assumed to be NOOP-1.
- Boot and labwc configuration backups were saved with .bak-TIMESTAMP suffixes.
MESSAGE
