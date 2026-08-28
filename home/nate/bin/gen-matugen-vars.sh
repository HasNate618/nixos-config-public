#!/bin/sh
# Generate matugen-vars.json for the zen bridge
# Called by skwd-wall after matugen renders colors
COLORS_INI="/home/nate/.config/foot/colors.ini"
OUT="/home/nate/.config/zen/7khcdo47.Default (release)/chrome/matugen-vars.json"
[ -f "$COLORS_INI" ] || exit 0

bg=$(sed -n 's/^background=//p' "$COLORS_INI" | head -1)
[ -n "$bg" ] || exit 0

# Write JSON with transparency color (80% alpha)
cat > "$OUT" << EOF
{"transparency_color":"#${bg}80"}
EOF
