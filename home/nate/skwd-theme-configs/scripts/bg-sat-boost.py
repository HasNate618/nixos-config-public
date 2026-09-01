#!/etc/profiles/per-user/nate/bin/python3
"""Boost background saturation across themed apps.

MD3 surface roles cap chroma (~12), so generated bgs look grey.
This takes the scheme's primary hue and rebuilds the bg color with
forced saturation at dark lightness, then patches all app configs.

Env override: SKWD_BG_SAT (0.0-1.0, default 0.42), SKWD_BG_LIGHT (default 0.16).
"""
import colorsys
import glob
import os
import re

SAT = float(os.environ.get("SKWD_BG_SAT", "0.42"))
LIGHT = float(os.environ.get("SKWD_BG_LIGHT", "0.16"))

PRIMARY_FILE = "/home/nate/.config/quickshell/colors.toml"


def read_primary_hue():
    c = open(PRIMARY_FILE).read()
    m = re.search(r'accent\s*=\s*"#([0-9a-fA-F]{6})"', c)
    if not m:
        m = re.search(r'primary\s*=\s*"#([0-9a-fA-F]{6})"', c)
    hx = m.group(1)
    r, g, b = int(hx[0:2], 16) / 255, int(hx[2:4], 16) / 255, int(hx[4:6], 16) / 255
    h, l, s = colorsys.rgb_to_hls(r, g, b)
    return h


def build_hex(h):
    r, g, b = colorsys.hls_to_rgb(h, LIGHT, SAT)
    return "%02x%02x%02x" % (round(r * 255), round(g * 255), round(b * 255))


def rewrite(path, pattern, repl_fmt, count=1):
    """Replace regex matches; repl_fmt gets match.expand-style groups."""
    try:
        c = open(path).read()
    except FileNotFoundError:
        return False
    new, n = re.subn(pattern, repl_fmt, c)
    if n and new != c:
        open(path, "w").write(new)
    return bool(n)


def main():
    h = read_primary_hue()
    bg = build_hex(h)
    r = int(bg[0:2], 16)
    g = int(bg[2:4], 16)
    b = int(bg[4:6], 16)
    print(f"hue={h * 360:.0f} -> bg #{bg}")

    # foot
    rewrite("/home/nate/.config/foot/colors.ini",
            r"(?m)^background=[0-9a-fA-F]+$", f"background={bg}")
    # quickshell
    rewrite("/home/nate/.config/quickshell/colors.toml",
            r'(?m)^background\s*=\s*"[^"]*"$', f'background = "#{bg}"')
    rewrite("/home/nate/.cache/skwd-wall/colors.json",
            r'"background":\s*"#[^"]*"', f'"background": "#{bg}"')
    rewrite("/home/nate/.cache/skwd/colors.json",
            r'"background":\s*"#[^"]*"', f'"background": "#{bg}"')
    # gtk css (matugen_surface rgba line, any alpha)
    for p in ("/home/nate/.config/gtk-3.0/gtk.css",
              "/home/nate/.config/gtk-4.0/gtk.css"):
        rewrite(p, r"@define-color matugen_surface rgba\([^)]*\)",
                f"@define-color matugen_surface rgba({r}, {g}, {b}, 0.20)")
    # MonoThemeDark patched line
    for p in glob.glob("/home/nate/.themes/MonoThemeDark/gtk-[34].0/gtk.css"):
        rewrite(p, r"@define-color theme_base_color rgba\([0-9., ]+\);",
                f"@define-color theme_base_color rgba({r}, {g}, {b}, 0.20)")
    # zen (bg var without alpha, transparency vars keep their 33 alpha suffix)
    zen = "/home/nate/.config/zen/7khcdo47.Default (release)/chrome/zen-themes/matugen-transparency/chrome.css"
    rewrite(zen, r"--zen-main-browser-background:\s*#[0-9a-fA-F]+\s*!(important)",
            f"--zen-main-browser-background: #{bg} !\\1")
    rewrite(zen, r"(--(?:mod-sameerasw-)?zen_transparency_color):\s*#[0-9a-fA-F]+",
            f"\\1: #{bg}33")
    rewrite(zen, r"(--zen-transparency-color):\s*#[0-9a-fA-F]+", f"\\1: #{bg}33")
    rewrite(zen, r"(--zen-sidebar-bg):\s*#[0-9a-fA-F]+", f"\\1: #{bg}33")

    # push opaque bg to running foot instances (alpha handled by foot config;
    # OSC sets raw color, foot applies its own alpha on top)
    for tty in glob.glob("/dev/pts/[0-9]*"):
        try:
            if os.stat(tty).st_uid == os.getuid():
                with open(tty, "w") as f:
                    f.write(f"\033]11;[100]#{bg}\007")
        except OSError:
            pass


if __name__ == "__main__":
    main()
