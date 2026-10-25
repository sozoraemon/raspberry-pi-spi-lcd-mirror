#!/usr/bin/env bash
set -Eeuo pipefail

# Installer for Raspberry Pi 5 + MHS35 SPI LCD (480x320, RGB565)

# =========================================================
# 1. Check environment
# =========================================================

[[ $EUID -eq 0 ]] || {
    echo 'Run with: sudo bash install.sh' >&2
    exit 1
}

BASE_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

USER_NAME="${SUDO_USER:-}"

[[ -n "$USER_NAME" && "$USER_NAME" != root ]] || {
    echo 'Run from your desktop user account using sudo.' >&2
    exit 1
}

USER_UID="$(id -u "$USER_NAME")"
USER_HOME="$(getent passwd "$USER_NAME" | cut -d: -f6)"
USER_GROUP="$(id -gn "$USER_NAME")"

CONFIG=/boot/firmware/config.txt
CMDLINE=/boot/firmware/cmdline.txt

[[ -f "$CONFIG" && -f "$CMDLINE" ]] || {
    echo 'Raspberry Pi OS boot configuration not found.' >&2
    exit 1
}

for f in mhs35.dtbo spi-mirror.sh spi-mirror.service mhs35_calibrate.py spi-rotate; do
    [[ -f "$BASE_DIR/$f" ]] || {
        echo "Missing: $BASE_DIR/$f" >&2
        exit 1
    }
done

if [[ -e /proc/device-tree/model ]] &&
   ! grep -q 'Raspberry Pi 5' /proc/device-tree/model; then

    echo 'Warning: Only Raspberry Pi 5 has been tested.'
    read -r -p 'Continue? [y/N] ' reply
    [[ "$reply" =~ ^[Yy]$ ]] || exit 1
fi

echo "Desktop user: $USER_NAME"
echo "User UID: $USER_UID"
echo "Home directory: $USER_HOME"

STAMP="$(date +%Y%m%d-%H%M%S)"

backup() {
    [[ ! -e "$1" ]] || cp -a -- "$1" "$1.bak-$STAMP"
}


# =========================================================
# 2. Install dependencies
# =========================================================

echo '[1/8] Installing dependencies'

apt-get update
apt-get install -y grim ffmpeg python3-evdev python3-pil


# =========================================================
# 3. Install device-tree overlay
# =========================================================

echo '[2/8] Installing device-tree overlay'

install -d /boot/firmware/overlays

backup /boot/firmware/overlays/mhs35.dtbo

install -m 644 \
    "$BASE_DIR/mhs35.dtbo" \
    /boot/firmware/overlays/mhs35.dtbo


# =========================================================
# 4. Update boot configuration
# =========================================================

echo '[3/8] Updating config.txt and cmdline.txt'

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

# Check existing active settings.
# Different dtparam names, such as audio and spi, do not conflict.

def active_setting(line):
    s = line.strip()
    return s if s and not s.startswith('#') else None


active = [
    s for line in lines
    if (s := active_setting(line)) is not None
]

for item in required:

    key, value = item.split('=', 1)

    if key == 'dtoverlay':

        name = value.split(':', 1)[0]

        existing = [
            s for s in active
            if s.startswith('dtoverlay=')
            and s.split('=', 1)[1].split(':', 1)[0] == name
        ]

    elif key == 'dtparam':

        param_name = value.split('=', 1)[0]

        existing = [
            s for s in active
            if s.startswith('dtparam=')
            and s.split('=', 1)[1].split('=', 1)[0] == param_name
        ]

    else:

        existing = [
            s for s in active
            if s.startswith(key + '=')
        ]

    if existing and item not in existing:
        raise SystemExit(
            f'Conflicting setting for {item}: {existing}. '
            'Check config.txt manually.'
        )

# Add settings only if they are missing.
# Place them under [all] so they are not restricted by
# a preceding conditional section.

missing = [item for item in required if item not in active]

if missing:

    if lines and lines[-1].strip():
        lines.append('')

    lines.append('[all]')
    lines.extend(missing)

    config.write_text('\n'.join(lines) + '\n')

# Keep cmdline.txt on a single line.

args = cmdline.read_text().strip().split()

args = [
    x for x in args
    if not x.startswith('vt.global_cursor_default=')
]

args.append('vt.global_cursor_default=0')

cmdline.write_text(' '.join(args) + '\n')

PY


# =========================================================
# 5. Install mirroring script and service
# =========================================================

echo '[4/8] Installing mirroring script and service'

install -m 755 \
    "$BASE_DIR/spi-mirror.sh" \
    /usr/local/bin/spi-mirror.sh

# Install screen rotation tool
backup /usr/local/bin/spi-rotate

install -m 755 \
    "$BASE_DIR/spi-rotate" \
    /usr/local/bin/spi-rotate

# Replace the default pi/UID 1000 settings with the
# actual desktop user's name and UID.

python3 - \
    /usr/local/bin/spi-mirror.sh \
    "$USER_NAME" \
    "$USER_UID" <<'PY'

from pathlib import Path
import sys

p = Path(sys.argv[1])

user_name = sys.argv[2]
user_uid = sys.argv[3]

s = p.read_text()

old_user = 'sudo -u pi env'
old_runtime = 'XDG_RUNTIME_DIR=/run/user/1000'

if old_user not in s:
    raise SystemExit(
        'Expected user setting not found in spi-mirror.sh'
    )

if old_runtime not in s:
    raise SystemExit(
        'Expected runtime directory not found in spi-mirror.sh'
    )

s = s.replace(
    old_user,
    f'sudo -u {user_name} env'
)

s = s.replace(
    old_runtime,
    f'XDG_RUNTIME_DIR=/run/user/{user_uid}'
)

p.write_text(s)

PY

backup /etc/systemd/system/spi-mirror.service

install -m 644 \
    "$BASE_DIR/spi-mirror.service" \
    /etc/systemd/system/spi-mirror.service

backup /usr/local/bin/mhs35_calibrate.py

install -m 755 \
    "$BASE_DIR/mhs35_calibrate.py" \
    /usr/local/bin/mhs35_calibrate.py


# =========================================================
# 6. Configure labwc touchscreen
# =========================================================

echo '[5/8] Configuring labwc touch mapping'

LABWC="$USER_HOME/.config/labwc/rc.xml"

install -d \
    -o "$USER_NAME" \
    -g "$USER_GROUP" \
    "$(dirname "$LABWC")"

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

    root = ET.Element(
        'openbox_config',
        {'xmlns': 'http://openbox.org/3.4/rc'}
    )

    tree = ET.ElementTree(root)

if root.tag.split('}')[-1] != 'openbox_config':
    raise SystemExit(
        'Unexpected labwc rc.xml format; no changes made.'
    )

# Remove only the existing ADS7846 mapping.

for node in list(root):

    if (
        node.tag.split('}')[-1] == 'touch'
        and node.get('deviceName') == 'ADS7846 Touchscreen'
    ):
        root.remove(node)

# Preserve the XML namespace.

ns = (
    root.tag.split('}')[0][1:]
    if root.tag.startswith('{')
    else ''
)

name = f'{{{ns}}}touch' if ns else 'touch'

ET.SubElement(
    root,
    name,
    {
        'deviceName': 'ADS7846 Touchscreen',
        'mapToOutput': 'NOOP-1',
        'mouseEmulation': 'yes'
    }
)

if ns:
    ET.register_namespace('', ns)

ET.indent(tree, space='  ')

tree.write(
    p,
    encoding='unicode',
    xml_declaration=True
)

PY

chown "$USER_NAME:$USER_GROUP" "$LABWC"


# =========================================================
# 7. Install touchscreen calibration
# =========================================================

echo '[6/8] Installing tested touchscreen calibration'

RULE=/etc/udev/rules.d/99-ads7846-calibration.rules

backup "$RULE"

cat > "$RULE" <<'RULE_EOF'
ACTION=="add|change", SUBSYSTEM=="input", KERNEL=="event*", ATTRS{name}=="ADS7846 Touchscreen", ENV{LIBINPUT_CALIBRATION_MATRIX}="0.000462 1.092691 -0.053591 -1.112591 0.000905 1.062629"
RULE_EOF

chmod 644 "$RULE"


# =========================================================
# 8. Enable systemd service
# =========================================================

echo '[7/8] Enabling mirror service'

systemctl daemon-reload
systemctl enable spi-mirror.service


# =========================================================
# 9. Finish
# =========================================================

echo '[8/8] Reboot instructions'

cat <<'MESSAGE'

==================================================
 Installation completed successfully
==================================================

Reboot your Raspberry Pi to apply the settings:

  sudo reboot

After reboot, check the mirror service:

  systemctl status spi-mirror.service

If the touch position is inaccurate, run:

  sudo /usr/bin/python3 /usr/local/bin/mhs35_calibrate.py

When prompted:

  Save calibration rule? [y/N]:

Enter y and press Enter to save the calibration.

Notes:
- Wayland socket: wayland-0
- Mirrored output: NOOP-1
- Existing configuration files are backed up.
- Only Raspberry Pi 5 has been tested.

==================================================

MESSAGE
