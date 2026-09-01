#!/etc/profiles/per-user/nate/bin/python3
"""Scale zen RGB channels to match GTK/foot rendering.
R: R * 2/5, G/B: G/B * 10/13 (user-calibrated)."""
import re

CSS_FILE = "/home/nate/.config/zen/7khcdo47.Default (release)/chrome/zen-themes/matugen-transparency/chrome.css"

def scale_hex(hex_str):
    h = hex_str.lstrip('#')
    r = int(h[0:2], 16)
    g = int(h[2:4], 16)
    b = int(h[4:6], 16)
    r = int(r * 2 / 5)
    g = int(g * 10 / 13)
    b = int(b * 10 / 13)
    return '#' + '%02x%02x%02x' % (r, g, b)

if __name__ == '__main__':
    with open(CSS_FILE, 'r') as f:
        c = f.read()
    new = re.sub(r'#[0-9a-fA-F]{6}', lambda m: scale_hex(m.group(0)), c)
    if new != c:
        with open(CSS_FILE, 'w') as f:
            f.write(new)
