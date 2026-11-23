#!/nix/store/gik3rh1vz2jlgnifb9dh6vc6sxwwz9jj-bash-5.3p9/bin/bash
SCHEME="SkwdMatugen"
ALT="${SCHEME}Alt"
SCHEME_DIR="/home/nate/.local/share/color-schemes"

command -v plasma-apply-colorscheme >/dev/null || exit 0

cp "$SCHEME_DIR/$SCHEME.colors" "$SCHEME_DIR/$ALT.colors" 2>/dev/null
sed -i "s/^Name=.*/Name=$ALT/" "$SCHEME_DIR/$ALT.colors" 2>/dev/null

CURRENT=$(grep '^ColorScheme=' "/home/nate/.config/kdeglobals" | cut -d= -f2)

if [ "$CURRENT" = "$ALT" ]; then
    plasma-apply-colorscheme "$SCHEME"
else
    plasma-apply-colorscheme "$ALT"
fi