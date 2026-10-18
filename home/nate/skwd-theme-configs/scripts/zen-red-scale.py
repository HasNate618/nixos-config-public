#!/etc/profiles/per-user/nate/bin/python3
"""Zen colour compensation.

Zen/Gecko renders matugen colours warmer (more red) than GTK/foot on this
display, so the colours handed to Zen are pre-compensated:

    R * 2/5, G * 10/13, B * 10/13   (user-calibrated; alpha preserved)

Usage:
    zen-red-scale.py --color '#rrggbb[aa]'   -> prints the scaled colour
    zen-red-scale.py <file.css>              -> legacy: scales every #hex
                                                in place. NOT idempotent —
                                                never call it per reload
                                                (multi-monitor matugen
                                                batches would compound).
"""
import re
import sys


def scale_hex(hex_str):
    h = hex_str.lstrip('#')
    r = int(h[0:2], 16)
    g = int(h[2:4], 16)
    b = int(h[4:6], 16)
    r = int(r * 2 / 5)
    g = int(g * 10 / 13)
    b = int(b * 10 / 13)
    return '#' + '%02x%02x%02x' % (r, g, b) + h[6:]


def main():
    args = sys.argv[1:]
    if len(args) == 2 and args[0] == '--color':
        c = args[1]
        if re.fullmatch(r'#[0-9a-fA-F]{6}([0-9a-fA-F]{2})?', c):
            print(scale_hex(c))
        else:
            print(c)  # passthrough on unrecognised input
        return 0
    if len(args) == 1:
        path = args[0]
        with open(path, 'r') as f:
            content = f.read()
        new = re.sub(r'#[0-9a-fA-F]{6}', lambda m: scale_hex(m.group(0)), content)
        if new != content:
            with open(path, 'w') as f:
                f.write(new)
        return 0
    print(__doc__)
    return 2


if __name__ == '__main__':
    sys.exit(main())
