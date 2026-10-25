#!/usr/bin/env python3
"""9-point ADS7846 calibration for a 480x320 RGB565 framebuffer mirror."""
import os
import statistics
import struct
import subprocess
import time
from pathlib import Path

from evdev import InputDevice, ecodes
from PIL import Image, ImageDraw, ImageFont

FB = Path('/dev/fb0')
DEVICE = '/dev/input/event5'
RULE = Path('/etc/udev/rules.d/99-ads7846-calibration.rules')
SERVICE = 'spi-mirror.service'
W, H = 480, 320
POINTS = [(x, y) for y in (0.12, 0.50, 0.88) for x in (0.12, 0.50, 0.88)]


def show_target(index, x, y):
    image = Image.new('RGB', (W, H), '#101820')
    d = ImageDraw.Draw(image)
    px, py = round(x * (W - 1)), round(y * (H - 1))
    d.line((px - 17, py, px + 17, py), fill='#00e5ff', width=3)
    d.line((px, py - 17, px, py + 17), fill='#00e5ff', width=3)
    d.ellipse((px - 5, py - 5, px + 5, py + 5), outline='white', width=2)
    d.text((12, 12), f'Point {index}/9 - touch cross', fill='white')
    d.text((12, H - 23), 'Use a stylus. Lift after each touch.', fill='white')
    pixels = image.tobytes()
    out = bytearray(W * H * 2)
    for i in range(W * H):
        r, g, b = pixels[i * 3:i * 3 + 3]
        struct.pack_into('<H', out, i * 2, (r >> 3) << 11 | (g >> 2) << 5 | (b >> 3))
    with FB.open('wb', buffering=0) as f:
        f.write(out)


def read_touch(device):
    """Take median raw coordinates while finger/stylus is held down."""
    x = y = None
    active = False
    samples = []
    for event in device.read_loop():
        if event.type == ecodes.EV_ABS:
            if event.code == ecodes.ABS_X:
                x = event.value
            elif event.code == ecodes.ABS_Y:
                y = event.value
        elif event.type == ecodes.EV_KEY and event.code == ecodes.BTN_TOUCH:
            if event.value == 1:
                active, samples = True, []
            elif event.value == 0 and active:
                active = False
                if len(samples) >= 3:
                    return (statistics.median(p[0] for p in samples),
                            statistics.median(p[1] for p in samples))
                print('Touch too short. Hold for half a second and retry.')
        elif event.type == ecodes.EV_SYN and event.code == ecodes.SYN_REPORT:
            if active and x is not None and y is not None:
                samples.append((x, y))


def solve3(a, b):
    """Solve 3x3 linear system by Gaussian elimination."""
    a = [list(row) + [rhs] for row, rhs in zip(a, b)]
    for i in range(3):
        k = max(range(i, 3), key=lambda j: abs(a[j][i]))
        a[i], a[k] = a[k], a[i]
        if abs(a[i][i]) < 1e-12:
            raise ValueError('Calibration points are degenerate.')
        v = a[i][i]
        a[i] = [n / v for n in a[i]]
        for j in range(3):
            if j != i:
                v = a[j][i]
                a[j] = [p - v * q for p, q in zip(a[j], a[i])]
    return [a[i][3] for i in range(3)]


def fit(samples):
    """Least-squares affine map from normalized ABS values to screen fractions."""
    rows = [[rx / 4095, ry / 4095, 1] for rx, ry, _, _ in samples]
    ata = [[sum(row[i] * row[j] for row in rows) for j in range(3)] for i in range(3)]
    atx = [sum(row[i] * s[2] for row, s in zip(rows, samples)) for i in range(3)]
    aty = [sum(row[i] * s[3] for row, s in zip(rows, samples)) for i in range(3)]
    a, b, c = solve3(ata, atx)
    d, e, f = solve3(ata, aty)
    errors = [((a * rx / 4095 + b * ry / 4095 + c - tx) ** 2 * W ** 2 +
               (d * rx / 4095 + e * ry / 4095 + f - ty) ** 2 * H ** 2) ** 0.5
              for rx, ry, tx, ty in samples]
    return (a, b, c, d, e, f), errors


def main():
    if os.geteuid() != 0:
        raise SystemExit('Run with sudo.')
    size = FB.stat().st_size
    if size not in (0, W * H * 2):
        print(f'Warning: framebuffer file size is {size}; expected {W * H * 2}.')
    was_active = subprocess.run(['systemctl', 'is-active', '--quiet', SERVICE]).returncode == 0
    if was_active:
        subprocess.run(['systemctl', 'stop', SERVICE], check=True)
    try:
        device = InputDevice(DEVICE)
        print(f'Input device: {device.name} ({DEVICE})')
        print('Touch each cross and hold briefly, then release.')
        samples = []
        for i, (tx, ty) in enumerate(POINTS, 1):
            show_target(i, tx, ty)
            rx, ry = read_touch(device)
            samples.append((rx, ry, tx, ty))
            print(f'{i}/9: raw X={rx:.0f}, Y={ry:.0f}')
            time.sleep(0.35)
        matrix, errors = fit(samples)
        value = ' '.join(f'{v:.6f}' for v in matrix)
        print('\nLIBINPUT_CALIBRATION_MATRIX=' + value)
        print(f'Average error: {statistics.mean(errors):.1f} px; max: {max(errors):.1f} px')
        if max(errors) > 35:
            print('Warning: large error. Retake calibration if taps were inaccurate.')
        answer = input('\nSave calibration rule? [y/N]: ').strip().lower()
        if answer == 'y':
            if RULE.exists():
                backup = RULE.with_name(RULE.name + '.bak-' + time.strftime('%Y%m%d-%H%M%S'))
                backup.write_bytes(RULE.read_bytes())
                print('Backup:', backup)
            rule = ('ACTION=="add|change", SUBSYSTEM=="input", KERNEL=="event*", '
                    'ATTRS{name}=="ADS7846 Touchscreen", '
                    f'ENV{{LIBINPUT_CALIBRATION_MATRIX}}="{value}"\n')
            RULE.write_text(rule)
            print('Saved:', RULE)
            print('Reboot to apply: sudo reboot')
        else:
            print('No changes saved.')
    finally:
        if was_active:
            subprocess.run(['systemctl', 'start', SERVICE], check=False)


if __name__ == '__main__':
    main()
